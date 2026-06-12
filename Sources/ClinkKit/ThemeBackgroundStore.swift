/**
 `ThemeBackgroundStore`: manages per-theme background and key-background photos
 in the App Group container. Down-scales picked photos to keyboard-sized JPEGs
 before storing, so the extension never loads a full-resolution image.
 

 Module: settings · Target: ClinkKit
 Learn: docs/01-settings-and-storage.md
 */
import UIKit
import ImageIO
import UniformTypeIdentifiers

/// Stores theme background **photos** in the App Group container so both
/// processes can reach them. The image bytes live as files on disk — NOT inside
/// the settings JSON — for the same reason settings do: the blob would bloat
/// every save and every cross-process notification. A `Theme` only carries the
/// image's id (`backgroundImageID`); the actual pixels are resolved here.
///
/// The container app writes (after downscaling — keyboard extensions have a tight
/// memory budget, so a full-resolution photo would crash the keyboard); the
/// extension only reads. An in-memory `NSCache` keeps a decoded copy so the live
/// keyboard doesn't hit disk on every re-render. Ids are unique per import, so a
/// cached image is never stale for its id.
public final class ThemeBackgroundStore: @unchecked Sendable {
    public static let shared = ThemeBackgroundStore()

    private let appGroupID: String
    /// Decoded images — keyed by id; invalidated on write/delete for that id.
    private let cache = NSCache<NSString, UIImage>()

    public init(appGroupID: String = SharedStore.appGroupID) {
        self.appGroupID = appGroupID
    }

    /// `…/<AppGroup>/theme-backgrounds/` — created lazily.
    private var directoryURL: URL? {
        guard let base = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupID) else { return nil }
        let dir = base.appendingPathComponent("theme-backgrounds", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    public func imageURL(for id: String) -> URL? {
        directoryURL?.appendingPathComponent("\(id).jpg")
    }

    /// The decoded background image for `id`, or nil if there's no file (e.g. a
    /// theme imported from a `.clink` that referenced a photo we don't have).
    public func image(for id: String) -> UIImage? {
        let key = id as NSString
        if let cached = cache.object(forKey: key) { return cached }
        guard let url = imageURL(for: id),
              let data = try? Data(contentsOf: url),
              let image = UIImage(data: data) else { return nil }
        cache.setObject(image, forKey: key)
        return image
    }

    /// Persist already-encoded JPEG bytes for `id`. Drops any cached copy so the
    /// next read reflects the new file.
    @discardableResult
    public func save(_ jpeg: Data, for id: String) -> Bool {
        guard let url = imageURL(for: id) else { return false }
        do {
            try jpeg.write(to: url, options: .atomic)
            cache.removeObject(forKey: id as NSString)
            return true
        } catch { return false }
    }

    public func delete(id: String) {
        if let url = imageURL(for: id) { try? FileManager.default.removeItem(at: url) }
        cache.removeObject(forKey: id as NSString)
    }

    /// Downscale arbitrary image `data` to a JPEG whose longest edge is at most
    /// `maxDimension` px. Uses ImageIO thumbnailing so the full-resolution source
    /// is never fully decoded into memory — important when the picked photo is a
    /// 12-megapixel original and we only need a keyboard-sized backdrop. Runs in
    /// the container app at import time; the extension never calls this.
    public static func downscaledJPEG(from data: Data,
                                      maxDimension: CGFloat = 1600,
                                      quality: CGFloat = 0.8) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxDimension,
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        let out = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(
            out, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dest, cgImage,
            [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return out as Data
    }
}
