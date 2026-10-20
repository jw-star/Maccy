import AppKit.NSImage
import ImageIO

// CGImage is immutable, so it is safe to hand over from a background decode.
nonisolated struct DownsampledImage: @unchecked Sendable {
  let cgImage: CGImage
  let size: NSSize
}

extension NSImage {
  /// Returns the pixel dimensions of the encoded image without decoding it.
  nonisolated static func pixelSize(of data: Data) -> NSSize? {
    guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
      return nil
    }

    return imageGeometry(of: source)?.pixelSize
  }

  /// Decodes only as many pixels as needed to fit `maxSize` points at `scale`.
  /// The resulting `size` is in points and is never bigger than the original image.
  @concurrent
  nonisolated static func downsampled(
    from data: Data,
    fitting maxSize: NSSize,
    scale: CGFloat
  ) async -> DownsampledImage? {
    let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
    guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions),
          let geometry = imageGeometry(of: source),
          geometry.pointSize.width > 0,
          geometry.pointSize.height > 0 else {
      return nil
    }

    let ratio = min(
      maxSize.width / geometry.pointSize.width,
      maxSize.height / geometry.pointSize.height,
      1
    )
    let size = NSSize(
      width: max((geometry.pointSize.width * ratio).rounded(), 1),
      height: max((geometry.pointSize.height * ratio).rounded(), 1)
    )
    let maxPixelSize = min(
      max(size.width, size.height) * max(scale, 1),
      max(geometry.pixelSize.width, geometry.pixelSize.height)
    )

    let thumbnailOptions = [
      kCGImageSourceCreateThumbnailFromImageAlways: true,
      kCGImageSourceCreateThumbnailWithTransform: true,
      kCGImageSourceShouldCacheImmediately: true,
      kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
    ] as CFDictionary
    guard let cgImage = CGImageSourceCreateThumbnailAtIndex(
      source,
      CGImageSourceGetPrimaryImageIndex(source),
      thumbnailOptions
    ) else {
      return nil
    }

    return DownsampledImage(cgImage: cgImage, size: size)
  }

  private nonisolated static func imageGeometry(
    of source: CGImageSource
  ) -> (pixelSize: NSSize, pointSize: NSSize)? {
    let index = CGImageSourceGetPrimaryImageIndex(source)
    guard let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any],
          let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.doubleValue,
          let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.doubleValue else {
      return nil
    }

    // EXIF orientations 5-8 rotate the image by 90 degrees.
    let orientation = (properties[kCGImagePropertyOrientation] as? NSNumber)?.intValue ?? 1
    let pixelSize = orientation >= 5
      ? NSSize(width: height, height: width)
      : NSSize(width: width, height: height)

    // Match NSBitmapImageRep, which derives the size in points from the DPI.
    let dpiWidth = (properties[kCGImagePropertyDPIWidth] as? NSNumber)?.doubleValue ?? 72
    let dpiHeight = (properties[kCGImagePropertyDPIHeight] as? NSNumber)?.doubleValue ?? 72
    let (horizontalDPI, verticalDPI) = orientation >= 5 ? (dpiHeight, dpiWidth) : (dpiWidth, dpiHeight)
    let pointSize = NSSize(
      width: pixelSize.width * 72 / (horizontalDPI > 0 ? horizontalDPI : 72),
      height: pixelSize.height * 72 / (verticalDPI > 0 ? verticalDPI : 72)
    )

    return (pixelSize, pointSize)
  }
}
