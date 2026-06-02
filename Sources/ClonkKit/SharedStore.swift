import Foundation

/// The bridge between Clonk's two processes. The container app writes settings
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
    public static let appGroupID = "group.ltd.anti.clonk"

    /// Darwin notification name posted whenever settings change.
    public static let didChangeNotification = "ltd.anti.clonk.settingsDidChange"

    public static let shared = SharedStore()

    private let appGroupID: String
    /// Kept only for the small extension→app status flag (Full Access).
    private let defaults: UserDefaults?

    public init(appGroupID: String = SharedStore.appGroupID) {
        self.appGroupID = appGroupID
        defaults = UserDefaults(suiteName: appGroupID)
    }

    /// `…/<AppGroup>/clonk-settings.v1.json`
    private var settingsFileURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupID)?
            .appendingPathComponent("clonk-settings.v1.json")
    }

    public func load() -> KeyboardSettings {
        guard let url = settingsFileURL,
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode(KeyboardSettings.self, from: data)
        else { return .default }
        return decoded
    }

    public func save(_ settings: KeyboardSettings) {
        guard let url = settingsFileURL,
              let data = try? JSONEncoder().encode(settings) else { return }
        try? data.write(to: url, options: .atomic)
        postDidChange()
    }

    // MARK: - Runtime status (extension → app)

    private let fullAccessKey = "clonk.status.fullAccess.v1"

    /// The keyboard extension calls this on launch so the container app can
    /// reflect the real Full Access state (which only the extension can read).
    /// May be stale until the keyboard has run at least once.
    public func reportFullAccess(_ granted: Bool) {
        defaults?.set(granted, forKey: fullAccessKey)
    }

    public var lastKnownFullAccess: Bool {
        defaults?.bool(forKey: fullAccessKey) ?? false
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
