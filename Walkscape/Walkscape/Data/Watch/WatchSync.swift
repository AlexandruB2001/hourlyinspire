import Foundation
import WalkscapeDomain
import WatchConnectivity

/// Sends the Apple Watch app the same snapshot the widgets get (outfit,
/// companion, zone and totals). Only the latest one matters, so it goes as the
/// application context, which the watch receives whenever it next wakes. The
/// watch can also ask for it, which wakes this app in the background.
final class WatchSync: NSObject, WCSessionDelegate, @unchecked Sendable {
    static let shared = WatchSync()

    /// The key the watch reads (WatchModel.contextKey).
    static let contextKey = "snapshot"
    /// The watch's request (WatchModel.requestKey).
    static let requestKey = "request"

    private let lock = NSLock()
    private var pending: Data?

    func start() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    /// Sends `snapshot` now if the watch app is installed, else as soon as it is.
    func send(_ snapshot: WidgetSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        lock.lock()
        pending = data
        lock.unlock()
        push()
    }

    /// Sends the latest snapshot again (on every app open, in case an earlier
    /// one went out before the watch app was installed).
    func resend() {
        push()
    }

    /// The latest snapshot: the one sent this run, or the widgets' saved copy.
    private var latest: Data? {
        lock.lock()
        let data = pending
        lock.unlock()
        return data ?? UserDefaults(suiteName: WidgetSnapshot.appGroup)?.data(forKey: WidgetSnapshot.storageKey)
    }

    private func push() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.activationState == .activated, session.isPaired, session.isWatchAppInstalled,
              let data = latest else { return }
        try? session.updateApplicationContext([Self.contextKey: data])
    }

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        push()
    }

    /// The watch app asked (it just opened and has nothing, or wants the latest).
    func session(_ session: WCSession, didReceiveMessage message: [String: Any],
                 replyHandler: @escaping ([String: Any]) -> Void) {
        guard message[Self.requestKey] != nil, let data = latest else { return replyHandler([:]) }
        replyHandler([Self.contextKey: data])
    }

    /// The Watch app was just installed or the watch was paired: send the latest.
    func sessionWatchStateDidChange(_ session: WCSession) {
        push()
    }

    func sessionDidBecomeInactive(_ session: WCSession) {}

    /// Switching to another watch: activate again for the new one.
    func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }
}
