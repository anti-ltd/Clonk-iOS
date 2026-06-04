import Foundation

/// The bridge between Clink's two processes. The container app writes settings
/// here; the keyboard extension reads them.
///
/// Settings are stored as a JSON **file** in the App Group container — NOT in
/// the App Group `UserDefaults` suite. Cross-process `UserDefaults` reads are
/// cached per-process by cfprefsd, so a long-lived keyboard extension can hold
/// a stale snapshot and never see the app's later writes (this is exactly why
/// theme changes stopped propagating). A fresh `Data(contentsOf:)` read always
/// reflects the latest bytes on disk.
///
/// A Darwin notification is still posted on save so a *running* keyboard can
/// reload immediately (e.g. iPad split view); on iPhone the keyboard reloads
/// on `viewWillAppear`, which now reads the file fresh.
public final class SharedStore: @unchecked Sendable {
    public static let appGroupID = "group.ltd.anti.clink"

    /// Darwin notification name posted whenever settings change.
    public static let didChangeNotification = "ltd.anti.clink.settingsDidChange"

    public static let shared = SharedStore()

    private let appGroupID: String

    public init(appGroupID: String = SharedStore.appGroupID) {
        self.appGroupID = appGroupID
    }

    /// `…/<AppGroup>/clink-settings.v1.json`
    private var settingsFileURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupID)?
            .appendingPathComponent("clink-settings.v1.json")
    }

    public func load() -> KeyboardSettings {
        if let url = settingsFileURL,
           let data = try? Data(contentsOf: url),
           let decoded = try? JSONDecoder().decode(KeyboardSettings.self, from: data) {
            return decoded
        }
        // App Group container unavailable (self-signed build without a matching
        // provisioning profile). Fall back to standard UserDefaults so settings
        // at least survive within this process rather than resetting every time.
        if let data = UserDefaults.standard.data(forKey: "clink-settings-v1"),
           let decoded = try? JSONDecoder().decode(KeyboardSettings.self, from: data) {
            return decoded
        }
        return .default
    }

    public func save(_ settings: KeyboardSettings) {
        if let url = settingsFileURL,
           let data = try? JSONEncoder().encode(settings) {
            try? data.write(to: url, options: .atomic)
            postDidChange()
            return
        }
        // App Group unavailable — persist locally so settings survive re-launches.
        if let data = try? JSONEncoder().encode(settings) {
            UserDefaults.standard.set(data, forKey: "clink-settings-v1")
        }
    }

    // MARK: - Runtime status (extension → app)

    /// `…/<AppGroup>/clink-status.v1.json`  Written by the keyboard extension;
    /// read by the container app to reflect the real Full Access state.
    private var statusFileURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupID)?
            .appendingPathComponent("clink-status.v1.json")
    }

    /// The keyboard extension calls this on launch so the container app can
    /// reflect the real Full Access state (which only the extension can read).
    /// Uses a file — not UserDefaults — because keyboard extensions cannot write
    /// to App Group UserDefaults without Full Access, which is circular.
    public func reportFullAccess(_ granted: Bool) {
        guard lastKnownFullAccess != granted else { return }
        guard let url = statusFileURL,
              let data = try? JSONEncoder().encode(["fullAccess": granted]) else { return }
        try? data.write(to: url, options: .atomic)
    }

    public var lastKnownFullAccess: Bool {
        guard let url = statusFileURL,
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([String: Bool].self, from: data)
        else { return false }
        return decoded["fullAccess"] ?? false
    }

    // MARK: - Cross-process change notification

    private func postDidChange() {
        let center = CFNotificationCenterGetDarwinNotifyCenter()
        CFNotificationCenterPostNotification(
            center,
            CFNotificationName(Self.didChangeNotification as CFString),
            nil, nil, true
        )
    }

    /// Register a callback fired (on the main run loop) when settings change in
    /// the other process. Keep the returned token alive for as long as you want
    /// the callback; releasing it automatically unregisters (see the token's
    /// `deinit`). Used by the keyboard extension for live theme/layout updates.
    public func observeChanges(_ handler: @escaping @Sendable () -> Void) -> AnyObject {
        NotificationToken(name: Self.didChangeNotification, handler: handler)
    }

    public func stopObserving(_ token: AnyObject) {
        (token as? NotificationToken)?.unregister()
    }
}

/// Retains the Swift closure for the lifetime of a Darwin notification
/// registration (CFNotificationCenter only stores a raw pointer) and removes
/// the observer when it deallocates — so the caller just has to hold/drop it.
private final class NotificationToken: @unchecked Sendable {
    let handler: @Sendable () -> Void

    init(name: String, handler: @escaping @Sendable () -> Void) {
        self.handler = handler
        let center = CFNotificationCenterGetDarwinNotifyCenter()
        let observer = Unmanaged.passUnretained(self).toOpaque()
        CFNotificationCenterAddObserver(
            center, observer,
            { _, observer, _, _, _ in
                guard let observer else { return }
                Unmanaged<NotificationToken>.fromOpaque(observer)
                    .takeUnretainedValue().handler()
            },
            name as CFString, nil, .deliverImmediately
        )
    }

    func unregister() {
        let center = CFNotificationCenterGetDarwinNotifyCenter()
        CFNotificationCenterRemoveEveryObserver(center, Unmanaged.passUnretained(self).toOpaque())
    }

    deinit { unregister() }
}
