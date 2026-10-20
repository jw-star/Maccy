import AppKit

struct Accessibility {
  private static var allowed: Bool { AXIsProcessTrustedWithOptions(nil) }

  @discardableResult
  static func check() -> Bool {
    check(allowed: allowed, prompt: prompt)
  }

  @discardableResult
  static func check(allowed: Bool, prompt: () -> Void) -> Bool {
    guard !allowed else {
      return true
    }

    prompt()
    return false
  }

  private static func prompt() {
    // kAXTrustedCheckOptionPrompt. The string avoids the Swift 6 import of that C global.
    _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
  }

  /// Opens Privacy & Security → Accessibility. Tries the current System Settings URL,
  /// then the older Security & Privacy URL if that open fails.
  @MainActor
  static func openSystemSettings(openURL: @MainActor (URL) -> Bool = { NSWorkspace.shared.open($0) }) {
    let urls = [
      URL(string: "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Accessibility"),
      URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
    ]

    for url in urls {
      guard let url else { continue }
      if openURL(url) {
        return
      }
    }
  }
}
