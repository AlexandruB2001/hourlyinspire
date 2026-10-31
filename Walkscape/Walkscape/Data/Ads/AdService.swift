import AppTrackingTransparency
import Foundation
import GoogleMobileAds
import Observation
import UIKit
import UserMessagingPlatform

/// Ad unit ids. Every build that isn't from the App Store (simulator, Debug,
/// TestFlight) uses Google's test ads, so testers can never trigger real
/// ads and get the AdMob account flagged for invalid traffic.
enum AdConfig {
    static let testAppOpenUnit = "ca-app-pub-3940256099942544/5575463023"
    static let testRewardedUnit = "ca-app-pub-3940256099942544/1712485313"

    static var appOpenUnit: String { unit("AdMobAppOpenUnit", test: testAppOpenUnit) }
    static var rewardedUnit: String { unit("AdMobRewardedUnit", test: testRewardedUnit) }

    static var isAppStoreBuild: Bool {
        #if DEBUG || targetEnvironment(simulator)
        return false
        #else
        // TestFlight and development installs carry a sandbox receipt.
        return Bundle.main.appStoreReceiptURL?.lastPathComponent != "sandboxReceipt"
        #endif
    }

    private static func unit(_ key: String, test: String) -> String {
        guard isAppStoreBuild, let id = Bundle.main.object(forInfoDictionaryKey: key) as? String, !id.isEmpty else { return test }
        return id
    }
}

/// Wraps the Google Mobile Ads SDK: consent, then one app-open ad and one
/// rewarded ad kept loaded. When to show them is decided by `AdState`.
@MainActor
@Observable
final class AdService: NSObject {
    /// True once consent allows ads and the SDK has started.
    private(set) var canRequestAds = false
    private(set) var isRewardedReady = false
    /// People in the EEA/UK must be able to change their ad consent later.
    private(set) var needsPrivacyOptions = false

    @ObservationIgnored private var started = false
    @ObservationIgnored private var appOpenAd: GADAppOpenAd?
    @ObservationIgnored private var appOpenLoadedAt: Date?
    @ObservationIgnored private var rewardedAd: GADRewardedAd?
    @ObservationIgnored private var isLoadingAppOpen = false
    @ObservationIgnored private var isLoadingRewarded = false
    @ObservationIgnored private var dismissal: CheckedContinuation<Void, Never>?
    private(set) var isShowingAd = false

    /// Asks for consent (and tracking permission) if needed, starts the SDK
    /// and loads the first ads. Safe to call more than once.
    func start() async {
        guard !started else { return }
        started = true
        await gatherConsent()
        if ATTrackingManager.trackingAuthorizationStatus == .notDetermined {
            _ = await ATTrackingManager.requestTrackingAuthorization()
        }
        guard UMPConsentInformation.sharedInstance.canRequestAds else { return }
        GADMobileAds.sharedInstance().start(completionHandler: nil)
        canRequestAds = true
        async let appOpen: Void = loadAppOpenAd()
        async let rewarded: Void = loadRewardedAd()
        _ = await (appOpen, rewarded)
    }

    private func gatherConsent() async {
        let info = UMPConsentInformation.sharedInstance
        await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
            info.requestConsentInfoUpdate(with: UMPRequestParameters()) { _ in done.resume() }
        }
        guard let root = Self.topViewController else { return }
        await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
            UMPConsentForm.loadAndPresentIfRequired(from: root) { _ in done.resume() }
        }
        needsPrivacyOptions = info.privacyOptionsRequirementStatus == .required
    }

    func presentPrivacyOptions() async {
        guard let root = Self.topViewController else { return }
        await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
            UMPConsentForm.presentPrivacyOptionsForm(from: root) { _ in done.resume() }
        }
    }

    // MARK: App-open ad

    private func loadAppOpenAd() async {
        guard canRequestAds, !isLoadingAppOpen else { return }
        isLoadingAppOpen = true
        defer { isLoadingAppOpen = false }
        appOpenAd = try? await GADAppOpenAd.load(withAdUnitID: AdConfig.appOpenUnit, request: GADRequest())
        appOpenAd?.fullScreenContentDelegate = self
        appOpenLoadedAt = appOpenAd == nil ? nil : Date()
    }

    /// Shows the app-open ad if one is loaded. Returns whether it was shown.
    func presentAppOpenAd() -> Bool {
        // Loaded app-open ads expire after four hours.
        guard !isShowingAd, let ad = appOpenAd, let loaded = appOpenLoadedAt,
              Date().timeIntervalSince(loaded) < 4 * 60 * 60, let root = Self.topViewController else {
            appOpenAd = nil
            Task { await loadAppOpenAd() }
            return false
        }
        appOpenAd = nil
        isShowingAd = true
        ad.present(fromRootViewController: root)
        return true
    }

    // MARK: Rewarded ad

    private func loadRewardedAd() async {
        guard canRequestAds, !isLoadingRewarded, rewardedAd == nil else { return }
        isLoadingRewarded = true
        defer { isLoadingRewarded = false }
        rewardedAd = try? await GADRewardedAd.load(withAdUnitID: AdConfig.rewardedUnit, request: GADRequest())
        rewardedAd?.fullScreenContentDelegate = self
        isRewardedReady = rewardedAd != nil
    }

    /// Plays the rewarded ad and waits until it's closed. Returns true only
    /// if it was watched far enough to earn the reward.
    /// With `accountID`, AdMob also reports the ad to our server (server-side
    /// verification) with `rewardID`, the key the coins are stored under.
    func presentRewardedAd(accountID: String?, rewardID: String) async -> Bool {
        if rewardedAd == nil { await loadRewardedAd() }
        guard !isShowingAd, let ad = rewardedAd, let root = Self.topViewController else { return false }
        if let accountID {
            let options = GADServerSideVerificationOptions()
            options.userIdentifier = accountID
            options.customRewardString = rewardID
            ad.serverSideVerificationOptions = options
        }
        rewardedAd = nil
        isRewardedReady = false
        isShowingAd = true
        var earned = false
        await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
            dismissal = done
            ad.present(fromRootViewController: root) { earned = true }
        }
        Task { await loadRewardedAd() }
        return earned
    }

    // MARK: Helpers

    private func adClosed() {
        isShowingAd = false
        dismissal?.resume()
        dismissal = nil
        if appOpenAd == nil { Task { await loadAppOpenAd() } }
    }

    private static var topViewController: UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let scene = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
        var top = scene?.keyWindow?.rootViewController
        while let presented = top?.presentedViewController { top = presented }
        return top
    }
}

extension AdService: GADFullScreenContentDelegate {
    nonisolated func adDidDismissFullScreenContent(_ ad: GADFullScreenPresentingAd) {
        Task { @MainActor in self.adClosed() }
    }

    nonisolated func ad(_ ad: GADFullScreenPresentingAd, didFailToPresentFullScreenContentWithError error: Error) {
        Task { @MainActor in self.adClosed() }
    }
}
