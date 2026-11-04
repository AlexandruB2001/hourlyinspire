import SwiftUI
import UIKit
import WalkscapeDomain

struct RootTabView: View {
    @Environment(AppModel.self) private var model

    init() {
        let appearance = UITabBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = UIColor(Theme.Palette.forestDeep)
        appearance.shadowColor = UIColor(Theme.Palette.ink)
        UITabBar.appearance().standardAppearance = appearance
        UITabBar.appearance().scrollEdgeAppearance = appearance
    }

    var body: some View {
        @Bindable var model = model
        TabView(selection: $model.selectedTab) {
            JourneyView()
                .tabItem { Label("Journey", systemImage: "figure.walk") }
                .tag(AppModel.Tab.journey)
            FriendsView()
                .tabItem { Label("Social", systemImage: "person.3.fill") }
                .tag(AppModel.Tab.friends)
            WorldView()
                .tabItem { Label("World", systemImage: "map.fill") }
                .tag(AppModel.Tab.world)
            ShopView()
                .tabItem { Label("Shop", systemImage: "bag.fill") }
                .tag(AppModel.Tab.shop)
            ProfileView()
                .tabItem { Label("Profile", systemImage: "person.crop.circle.fill") }
                .tag(AppModel.Tab.profile)
        }
        .tint(Theme.Palette.gold)
        .overlay(alignment: .top) {
            if let celebration = model.celebration {
                ZoneCelebrationBanner(celebration: celebration, coins: model.celebrationCoins) { model.celebration = nil }
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .padding(.horizontal, Theme.Spacing.l)
            }
        }
        .overlay(alignment: .top) {
            if model.celebration == nil, let level = model.levelUp {
                LevelUpBanner(level: level) { model.levelUp = nil }
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .padding(.horizontal, Theme.Spacing.l)
            }
        }
        .animation(.spring(response: 0.45, dampingFraction: 0.8), value: model.celebration)
        .overlay(alignment: .top) {
            if model.celebration == nil, model.levelUp == nil, let news = model.discovery {
                DiscoveryBanner(news: news) { model.discovery = nil }
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .padding(.horizontal, Theme.Spacing.l)
            }
        }
        .animation(.spring(response: 0.45, dampingFraction: 0.8), value: model.levelUp)
        .animation(.spring(response: 0.45, dampingFraction: 0.8), value: model.discovery)
        // Waits until the companion is chosen, so the two full-screen views never compete.
        .fullScreenCover(item: Binding(get: { model.needsCompanionChoice ? nil : model.teamWorldArrival },
                                       set: { model.teamWorldArrival = $0 })) { TeamWorldArrivalView(arrival: $0) }
        .fullScreenCover(isPresented: Binding(get: { model.needsCompanionChoice }, set: { _ in })) {
            CompanionOnboardingView()
        }
        // Waits for the companion choice and the arrival scene.
        .sheet(item: Binding(get: { model.needsCompanionChoice || model.teamWorldArrival != nil ? nil : model.availableUpdate },
                             set: { if $0 == nil, let update = model.availableUpdate { model.snoozeBetaUpdate(update) } })) {
            BetaUpdateSheet(update: $0)
        }
        .alert("Account", isPresented: Binding(get: { model.accountError != nil },
                                               set: { if !$0 { model.accountError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.accountError ?? "")
        }
    }
}

/// "A new update is out": sends TestFlight testers to the TestFlight app.
private struct BetaUpdateSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openURL) private var openURL
    let update: BetaUpdate

    var body: some View {
        VStack(spacing: Theme.Spacing.l) {
            Eyebrow("New update!", color: Theme.Palette.gold)
            ItemIcon(spriteID: "mystery-box", pixel: 6)
            VStack(spacing: Theme.Spacing.xs) {
                Text("Build \(update.build) is out")
                    .font(Theme.Typography.title)
                    .foregroundStyle(Theme.Palette.cream)
                Text(update.notes)
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Palette.creamDim)
                    .multilineTextAlignment(.center)
                Text("Open TestFlight and tap Update to get it.")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Palette.creamDim)
            }
            HStack(spacing: Theme.Spacing.m) {
                Button {
                    openURL(BetaUpdate.testFlightURL)
                    model.availableUpdate = nil
                } label: {
                    Label("Update in TestFlight", systemImage: "arrow.down.circle.fill")
                }
                .buttonStyle(.pixel)
                Button("Later") { model.snoozeBetaUpdate(update) }
                    .buttonStyle(.pixelQuiet)
            }
        }
        .padding(Theme.Spacing.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.Palette.forestDeep.ignoresSafeArea())
        .presentationDetents([.medium])
    }
}
