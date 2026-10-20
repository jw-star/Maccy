import AppKit
import Defaults
import Sauce
import SwiftData
import Vision

@Model
class HistoryItem {
  @MainActor
  static var supportedPins: Set<String> {
    // "a" reserved for select all
    // "q" reserved for quit
    // "v" reserved for paste
    // "w" reserved for close window
    // "z" reserved for undo/redo
    // "," reserved for preferences
    // "`" reserved for cycling through windows
    var keys = Set([
      "b", "c", "d", "e", "f", "g", "h", "i", "j", "k", "l",
      "m", "n", "o", "p", "r", "s", "t", "u", "x", "y",
      "[", "]", ";", "'", ".", "/", "-", "=", "\\"
    ])

    if let deleteKey = KeyChord.deleteKey,
       let character = Sauce.shared.character(for: Int(deleteKey.QWERTYKeyCode), modifiers: .cocoa([])) {
      keys.remove(character)
    }

    if let pinKey = KeyChord.pinKey,
       let character = Sauce.shared.character(for: Int(pinKey.QWERTYKeyCode), modifiers: .cocoa([])) {
      keys.remove(character)
    }
    if let previewKey = KeyChord.previewKey,
       let character = Sauce.shared.character(for: Int(previewKey.QWERTYKeyCode), modifiers: .cocoa([])) {
      keys.remove(character)
    }

    return keys
  }

  // Letters first, then symbols.
  static func sortedPins(_ pins: some Sequence<String>) -> [String] {
    pins.sorted { lhs, rhs in
      let lhsIsLetter = lhs.first?.isLetter ?? false
      let rhsIsLetter = rhs.first?.isLetter ?? false
      return lhsIsLetter == rhsIsLetter ? lhs < rhs : lhsIsLetter
    }
  }

  @MainActor
  static var availablePins: [String] {
    History.shared.availablePins
  }

  @MainActor
  static func availablePins(in items: [HistoryItem]) -> [String] {
    let assignedPins = Set(items.compactMap(\.pin))
    return Array(supportedPins.subtracting(assignedPins))
  }

  @MainActor
  static var randomAvailablePin: String { availablePins.randomElement() ?? "" }

  private static let transientTypes: [String] = [
    NSPasteboard.PasteboardType.modified.rawValue,
    NSPasteboard.PasteboardType.fromMaccy.rawValue,
    NSPasteboard.PasteboardType.linkPresentationMetadata.rawValue,
    NSPasteboard.PasteboardType.customWebKitPasteboardData.rawValue,
    NSPasteboard.PasteboardType.source.rawValue,
    NSPasteboard.PasteboardType.customChromiumWebData.rawValue,
    NSPasteboard.PasteboardType.chromiumSourceUrl.rawValue,
    NSPasteboard.PasteboardType.chromiumSourceToken.rawValue,
    NSPasteboard.PasteboardType.notesRichText.rawValue
  ]
  private static let imageTypes: [NSPasteboard.PasteboardType] = StorageType.images.types
  // Copied photos often arrive as a file URL ("….jpg") with no image bytes.
  static let imageFileExtensions: Set<String> = ["jpg", "jpeg", "png", "tif", "tiff", "heic", "heif"]

  var application: String?
  var firstCopiedAt: Date = Date.now
  var lastCopiedAt: Date = Date.now
  var numberOfCopies: Int = 1
  var pin: String?
  var title = ""

  @Relationship(deleteRule: .cascade, inverse: \HistoryItemContent.item)
  var contents: [HistoryItemContent] = []

  @Transient private var cachedDecodedImage: NSImage?

  init(contents: [HistoryItemContent] = []) {
    self.firstCopiedAt = firstCopiedAt
    self.lastCopiedAt = lastCopiedAt
    self.contents = contents
  }

  func supersedes(_ item: HistoryItem) -> Bool {
    return item.contents
      .filter { content in
        !Self.transientTypes.contains(content.type)
      }
      .allSatisfy { content in
        contents.contains(where: { $0.type == content.type && $0.value == content.value })
      }
  }

  @MainActor
  func generateTitle() -> String {
    let pasteboardImageData = storedImageData
    // A readable image file is shown as a picture. Leave the path as the title when
    // the file cannot be read, so the row is not blank.
    let imageURL = pasteboardImageData == nil && imagesEnabled ? readableImageFileURL : nil
    guard pasteboardImageData == nil && imageURL == nil else {
      Task {
        if let recognizedText = await Self.recognizeText(
          imageData: pasteboardImageData,
          fileURL: imageURL
        ) {
          self.title = recognizedText
        }
      }
      return ""
    }

    // 1k characters is trade-off for performance
    var title = previewableText
      .shortened(to: 1_000)
      .removingScalarsUnsafeForTitleLayout()

    if Defaults[.showSpecialSymbols] {
      if let range = title.range(of: "^ +", options: .regularExpression) {
        title = title.replacingOccurrences(of: " ", with: "·", range: range)
      }
      if let range = title.range(of: " +$", options: .regularExpression) {
        title = title.replacingOccurrences(of: " ", with: "·", range: range)
      }
      title = title
        .replacingOccurrences(of: "\n", with: "⏎")
        .replacingOccurrences(of: "\t", with: "⇥")
    } else {
      title = title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    return title
  }

  var previewableText: String {
    if !fileURLs.isEmpty {
      fileURLs
        .compactMap { $0.absoluteString.removingPercentEncoding }
        .joined(separator: "\n")
    } else if let text = text, !text.isEmpty {
      text
    } else if let rtf = rtf, !rtf.string.isEmpty {
      rtf.string
    } else if let html = html, !html.string.isEmpty {
      html.string
    } else {
      title
    }
  }

  var fileURLs: [URL] {
    guard !universalClipboardText else {
      return []
    }

    return allContentData([.fileURL])
      .compactMap { URL(dataRepresentation: $0, relativeTo: nil, isAbsolute: true) }
  }

  var htmlData: Data? { contentData([.html]) }
  var html: NSAttributedString? {
    guard let data = htmlData else {
      return nil
    }

    return NSAttributedString(html: data, documentAttributes: nil)
  }

  /// Image bytes stored on the item. Does not read a file URL.
  var storedImageData: Data? { contentData(Self.imageTypes) }

  /// First copied file that is an image, for example a photo copied from Finder.
  var imageFileURL: URL? {
    fileURLs.first { Self.isImageFile($0) }
  }

  var imageData: Data? {
    if let data = storedImageData {
      return data
    }
    guard let url = imageFileURL else {
      return nil
    }

    return Self.imageData(at: url)
  }

  var hasImage: Bool {
    storedImageData != nil || (imagesEnabled && readableImageFileURL != nil)
  }

  private var imagesEnabled: Bool {
    !Defaults[.enabledPasteboardTypes].isDisjoint(with: StorageType.images.types)
  }

  static func isImageFile(_ url: URL) -> Bool {
    imageFileExtensions.contains(url.pathExtension.lowercased())
  }

  static func pasteboardType(forImageFile url: URL) -> NSPasteboard.PasteboardType? {
    switch url.pathExtension.lowercased() {
    case "jpg", "jpeg":
      return .jpeg
    case "png":
      return .png
    case "tif", "tiff":
      return .tiff
    case "heic", "heif":
      return .heic
    default:
      return nil
    }
  }

  /// Reads an image file while pasteboard access is still valid.
  static func imageData(at url: URL) -> Data? {
    let accessed = url.startAccessingSecurityScopedResource()
    defer {
      if accessed {
        url.stopAccessingSecurityScopedResource()
      }
    }
    return try? Data(contentsOf: url)
  }

  private var readableImageFileURL: URL? {
    guard let url = imageFileURL else {
      return nil
    }
    var isDirectory: ObjCBool = false
    guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
          !isDirectory.boolValue,
          FileManager.default.isReadableFile(atPath: url.path) else {
      return nil
    }
    return url
  }

  var image: NSImage? {
    if let img = cachedDecodedImage {
      return img
    }
    guard let data = imageData else {
      return nil
    }

    cachedDecodedImage = NSImage(data: data)
    return cachedDecodedImage
  }

  var rtfData: Data? { contentData([.rtf]) }
  var rtf: NSAttributedString? {
    guard let data = rtfData else {
      return nil
    }

    return NSAttributedString(rtf: data, documentAttributes: nil)
  }

  func clearDecodedImageCache() {
    cachedDecodedImage?.recache()
    cachedDecodedImage = nil
  }

  var text: String? {
    guard let data = contentData([.string]) else {
      return nil
    }

    return String(data: data, encoding: .utf8)
  }

  var modified: Int? {
    guard let data = contentData([.modified]),
          let modified = String(data: data, encoding: .utf8) else {
      return nil
    }

    return Int(modified)
  }

  var fromMaccy: Bool { contentData([.fromMaccy]) != nil }
  var universalClipboard: Bool { contentData([.universalClipboard]) != nil }

  private var universalClipboardText: Bool {
    universalClipboard && contentData([.html, .tiff, .png, .jpeg, .rtf, .string, .heic]) != nil
  }

  private func contentData(_ types: [NSPasteboard.PasteboardType]) -> Data? {
    let content = contents.first(where: { content in
      return types.contains(NSPasteboard.PasteboardType(content.type))
    })

    return content?.value
  }

  private func allContentData(_ types: [NSPasteboard.PasteboardType]) -> [Data] {
    return contents
      .filter { types.contains(NSPasteboard.PasteboardType($0.type)) }
      .compactMap { $0.value }
  }

  /// Runs OCR on the global concurrent executor so the main thread stays free.
  @concurrent
  nonisolated private static func recognizeText(imageData: Data?, fileURL: URL?) async -> String? {
    guard let data = imageData ?? fileURL.flatMap({ try? Data(contentsOf: $0) }) else {
      return nil
    }

    let requestHandler = VNImageRequestHandler(data: data)
    let request = VNRecognizeTextRequest()
    request.recognitionLevel = .accurate
    request.automaticallyDetectsLanguage = true

    do {
      try requestHandler.perform([request])
    } catch {
      print("Unable to perform the request: \(error).")
      return nil
    }

    guard let observations = request.results else {
      return nil
    }

    return observations
      .compactMap { $0.topCandidates(1).first?.string }
      .joined(separator: "\n")
  }
}
