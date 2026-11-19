import Foundation
import ImageIO
import UniformTypeIdentifiers

public enum ImageRendering {
    public static func isDecodable(_ data: Data) -> Bool {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetStatus(source) == .statusComplete,
              CGImageSourceGetCount(source) > 0,
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = props[kCGImagePropertyPixelWidth] as? Int, width > 0
        else { return false }
        return true
    }

    /// Longest side of images copied to the pasteboard. A 50 MP photo would otherwise become a ~45 MB PNG;
    /// screenshots are below this and stay untouched.
    public static let pasteboardMaxPixelSize = 4096

    /// First frame with EXIF orientation applied, scaled down so its longest side is at most `maxPixelSize`
    /// (nil keeps the full size). Never scales up.
    public static func orientedImage(at url: URL, maxPixelSize: Int? = nil) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = props[kCGImagePropertyPixelWidth] as? Int,
              let height = props[kCGImagePropertyPixelHeight] as? Int
        else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: min(maxPixelSize ?? Int.max, max(width, height)),
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    public static func pngData(contentsOf url: URL, maxPixelSize: Int? = pasteboardMaxPixelSize) -> Data? {
        guard let image = orientedImage(at: url, maxPixelSize: maxPixelSize) else { return nil }
        let out = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(out, UTType.png.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dest, image, nil)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return out as Data
    }
}
