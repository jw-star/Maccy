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

  nonisolated static func pixelSize(of url: URL) -> NSSize? {
    let accessed = url.startAccessingSecurityScopedResource()
    defer {
      if accessed {
        url.stopAccessingSecurityScopedResource()
      }
    }
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
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
    guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
      return nil
    }

    return downsampled(from: source, fitting: maxSize, scale: scale)
  }

  /// Same as the data variant, reading the file only at the thumbnail size.
  @concurrent
  nonisolated static func downsampled(
    from url: URL,
    fitting maxSize: NSSize,
    scale: CGFloat
  ) async -> DownsampledImage? {
    let accessed = url.startAccessingSecurityScopedResource()
    defer {
      if accessed {
        url.stopAccessingSecurityScopedResource()
      }
    }
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
      return nil
    }

    return downsampled(from: source, fitting: maxSize, scale: scale)
  }

  private nonisolated static func downsampled(
    from source: CGImageSource,
    fitting maxSize: NSSize,
    scale: CGFloat
  ) -> DownsampledImage? {
    guard let geometry = imageGeometry(of: source),
          geometry.pointSize.width > 0,
          geometry.pointSize.height > 0 else {
      // Header we don't understand: still produce a thumbnail at the target size.
      // https://github.com/p0deje/Maccy/pull/1550
      return thumbnail(
        from: source,
        maxPixelSize: max(maxSize.width, maxSize.height) * max(scale, 1),
        scale: scale
      )
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

    return thumbnail(from: source, maxPixelSize: maxPixelSize, scale: scale, pointSize: size)
  }

  private nonisolated static func thumbnail(
    from source: CGImageSource,
    maxPixelSize: CGFloat,
    scale: CGFloat,
    pointSize: NSSize? = nil
  ) -> DownsampledImage? {
    let thumbnailOptions = [
      kCGImageSourceCreateThumbnailFromImageAlways: true,
      kCGImageSourceCreateThumbnailWithTransform: true,
      kCGImageSourceShouldCacheImmediately: true,
      kCGImageSourceThumbnailMaxPixelSize: max(1, maxPixelSize)
    ] as CFDictionary
    guard let cgImage = CGImageSourceCreateThumbnailAtIndex(
      source,
      CGImageSourceGetPrimaryImageIndex(source),
      thumbnailOptions
    ) else {
      return nil
    }

    let size = pointSize ?? NSSize(
      width: max(CGFloat(cgImage.width) / max(scale, 1), 1),
      height: max(CGFloat(cgImage.height) / max(scale, 1), 1)
    )
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
