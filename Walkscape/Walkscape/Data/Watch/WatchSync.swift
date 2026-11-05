import Foundation
import WalkscapeDomain
import WatchConnectivity

/// Sends the Apple Watch app the same snapshot the widgets get (outfit,
/// companion, zone and totals). Only the latest one matters, so it goes as the
/// application context, which the watch receives whenever it next wakes.
final class WatchSync: NSObject, WCSessionDelegate, @unchecked Sendable {
    static let shared = WatchSync()

    /// The key the watch reads (WatchModel.contextKey).
    static let contextKey = "snapshot"

    private let lock = NSLock()
    private var pending: Data?

    func start() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    func send(_ snapshot: WidgetSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        lock.lock()
        pending = data
        lock.unlock()
        push()
    }

    private func push() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.activationState == .activated, session.isPaired, session.isWatchAppInstalled else { return }
        lock.lock()
        let data = pending
        lock.unlock()
        guard let data else { return }
        try? session.updateApplicationContext([Self.contextKey: data])
    }

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        push()
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
