import Foundation
import HarnessgramSettings
import UIKit
import HarnessgramHouseCore

/// Where a room's picture comes from: the owner's replacement when he set one (a file in the app group, fitted by
/// `HouseArtFitter`), otherwise the catalog default that ships with the app (the "everything editable" rule).
public enum HouseArtVariant: Sendable {
    /// The small picture on a room card (132 x 88 pt).
    case card
    /// The room's header master (390 x 260 pt, 3:2; the header crops it).
    case header
}

public final class HouseArtStore: @unchecked Sendable {
    public static let shared = HouseArtStore(directory: HouseArtStore.appGroupDirectory(), bundle: .main)

    static let folderName = "harnessgram-house-art"

    private let directory: URL?
    private let bundle: Bundle
    private let lock = NSLock()
    private var cache: [String: UIImage] = [:]

    public init(directory: URL?, bundle: Bundle) {
        self.directory = directory
        self.bundle = bundle
    }

    public static func appGroupDirectory() -> URL? {
        guard var id = Bundle.main.bundleIdentifier else {
            return nil
        }
        if Bundle.main.bundleURL.pathExtension == "appex", let dot = id.range(of: ".", options: .backwards) {
            id = String(id[..<dot.lowerBound])
        }
        return FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group." + id)?.appendingPathComponent(folderName, isDirectory: true)
    }

    /// The file name an art key is stored under; only the key's own characters are allowed, so a key can never leave
    /// the folder. A replacement is one photo, fitted once for the header; the card is cut from it when drawn.
    static func fileName(for key: HouseRoomArtKey) -> String? {
        let storageKey = HarnessgramLocalConfig.bundled.roomArtStorageKeys?[key.rawValue] ?? key.rawValue
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789-")
        guard !storageKey.isEmpty, storageKey.count <= 40, storageKey.unicodeScalars.allSatisfy({ allowed.contains($0) }) else {
            return nil
        }
        return storageKey + ".png"
    }

    /// The image name in the catalog (HarnessgramHouse.xcassets, folder "House" with a namespace), see
    /// Resources/make-house-assets.sh.
    static func catalogName(for key: HouseRoomArtKey, variant: HouseArtVariant) -> String {
        switch variant {
        case .card:
            return "House/RoomCards/" + key.rawValue + "-card"
        case .header:
            return "House/Rooms/" + key.rawValue
        }
    }

    /// The owner's replacement, else the catalog default, else nil.
    public func image(for key: HouseRoomArtKey, variant: HouseArtVariant = .card) -> UIImage? {
        guard let name = HouseArtStore.fileName(for: key) else {
            return nil
        }
        let cacheKey = key.rawValue + "|" + (variant == .card ? "card" : "header")
        self.lock.lock()
        defer { self.lock.unlock() }
        if let cached = self.cache[cacheKey] {
            return cached
        }
        if let directory = self.directory, let image = UIImage(contentsOfFile: directory.appendingPathComponent(name).path) {
            self.cache[cacheKey] = image
            return image
        }
        let image = UIImage(named: HouseArtStore.catalogName(for: key, variant: variant), in: self.bundle, compatibleWith: nil)
        if let image {
            self.cache[cacheKey] = image
        }
        return image
    }

    /// Stores the owner's replacement (already fitted) and forgets the cached one.
    @discardableResult
    public func setReplacement(_ png: Data, for key: HouseRoomArtKey) -> Bool {
        guard let directory = self.directory, let name = HouseArtStore.fileName(for: key), UIImage(data: png) != nil else {
            return false
        }
        self.lock.lock()
        defer { self.lock.unlock() }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try png.write(to: directory.appendingPathComponent(name), options: .atomic)
        } catch {
            return false
        }
        self.forgetCached(key)
        return true
    }

    /// "Back to default": removes the replacement.
    public func removeReplacement(for key: HouseRoomArtKey) {
        guard let directory = self.directory, let name = HouseArtStore.fileName(for: key) else {
            return
        }
        self.lock.lock()
        defer { self.lock.unlock() }
        try? FileManager.default.removeItem(at: directory.appendingPathComponent(name))
        self.forgetCached(key)
    }

    private func forgetCached(_ key: HouseRoomArtKey) {
        self.cache[key.rawValue + "|card"] = nil
        self.cache[key.rawValue + "|header"] = nil
    }
}

/// Fits the owner's photo to a room's art frame: the largest centred crop with the frame's aspect ratio (the card art is
/// 132 x 88, the header 390 x 200). Pure geometry, so it is unit tested.
public enum HouseArtFitter {
    public static func cropRect(imageSize: CGSize, aspect: CGFloat) -> CGRect {
        guard imageSize.width > 0.0, imageSize.height > 0.0, aspect > 0.0, aspect.isFinite else {
            return CGRect(origin: .zero, size: imageSize)
        }
        let imageAspect = imageSize.width / imageSize.height
        if imageAspect > aspect {
            let width = imageSize.height * aspect
            return CGRect(x: (imageSize.width - width) / 2.0, y: 0.0, width: width, height: imageSize.height)
        } else {
            let height = imageSize.width / aspect
            return CGRect(x: 0.0, y: (imageSize.height - height) / 2.0, width: imageSize.width, height: height)
        }
    }
}
