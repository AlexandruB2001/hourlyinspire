import CoreGraphics
import Foundation
import Observation
import WalkscapeDomain
import WatchConnectivity
import WidgetKit

/// The watch's state: today's walk read from Apple Health on the watch, plus
/// the outfit, companion and totals the iPhone app last sent.
@MainActor
@Observable
final class WatchModel: NSObject {
    private(set) var glance: WatchGlance
    private(set) var frames: [CGImage] = []
    /// Apple Health hasn't been allowed on the watch yet.
    private(set) var needsHealth = false
    private(set) var healthUnavailable = false

    @ObservationIgnored private var snapshot: WidgetSnapshot?
    @ObservationIgnored private var live: DailyProgress?
    @ObservationIgnored private var framesKey: WatchArt.Key?
    @ObservationIgnored private let health = HealthKitWalkingDataProvider()

    static let snapshotKey = "walkscape.watch.snapshot.v1"
    /// The key the iPhone app sends its snapshot under (see WatchSync).
    static let contextKey = "snapshot"
    /// Asks the iPhone app for its latest snapshot (WatchSync.requestKey).
    static let requestKey = "request"

    var hasPhoneData: Bool { snapshot != nil }

    override init() {
        let saved = UserDefaults.standard.data(forKey: Self.snapshotKey).flatMap { try? JSONDecoder().decode(WidgetSnapshot.self, from: $0) }
        snapshot = saved
        glance = WatchGlance.make(snapshot: saved, live: nil, today: LocalDay(date: Date(), timeZone: .current))
        super.init()
        rebuild()
        if WCSession.isSupported() {
            WCSession.default.delegate = self
            WCSession.default.activate()
        }
    }

    /// Reads today's steps and distance from Apple Health on the watch, and
    /// asks the iPhone for the latest outfit and companion.
    func refresh() async {
        requestFromPhone()
        switch await health.authorizationState() {
        case .unavailable:
            healthUnavailable = true
        case .notDetermined:
            needsHealth = true
        default:
            needsHealth = false
            let now = Date()
            let today = LocalDay(date: now, timeZone: .current)
            if let reading = try? await health.fetchDailyTotals(for: today, timeZone: .current, now: now), reading.hasAnyData {
                live = DailyProgress(snapshot: reading, userID: UserID("watch"))
            }
        }
        rebuild()
        WidgetCenter.shared.reloadAllTimelines()
    }

    func connectHealth() async {
        try? await health.requestAuthorization()
        await refresh()
    }

    /// Wakes the iPhone app if needed; its reply is the latest snapshot.
    private func requestFromPhone() {
        guard WCSession.isSupported(), WCSession.default.activationState == .activated, WCSession.default.isReachable else { return }
        WCSession.default.sendMessage([Self.requestKey: "snapshot"], replyHandler: { reply in
            let data = reply[Self.contextKey] as? Data
            Task { @MainActor in if let data { self.receive(data) } }
        }, errorHandler: nil)
    }

    private func receive(_ data: Data) {
        guard let received = try? JSONDecoder().decode(WidgetSnapshot.self, from: data) else { return }
        snapshot = received
        UserDefaults.standard.set(data, forKey: Self.snapshotKey)
        rebuild()
    }

    private func rebuild() {
        glance = WatchGlance.make(snapshot: snapshot, live: live, today: LocalDay(date: Date(), timeZone: .current))
        let key = WatchArt.Key(glance)
        guard key != framesKey else { return }
        framesKey = key
        frames = WatchArt.frames(for: key)
    }
}

extension WatchModel: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState,
                             error: Error?) {
        let data = session.receivedApplicationContext[Self.contextKey] as? Data
        Task { @MainActor in
            if let data { self.receive(data) }
            self.requestFromPhone()
        }
    }

    /// The iPhone came into reach (Bluetooth or Wi-Fi): get its latest look.
    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        guard session.isReachable else { return }
        Task { @MainActor in self.requestFromPhone() }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        let data = applicationContext[Self.contextKey] as? Data
        Task { @MainActor in if let data { self.receive(data) } }
    }
}
