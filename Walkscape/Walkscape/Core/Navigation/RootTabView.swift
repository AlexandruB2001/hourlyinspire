import SwiftUI
import UIKit

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
                .tabItem { Label("Friends", systemImage: "person.2.fill") }
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
        .alert("Account", isPresented: Binding(get: { model.accountError != nil },
                                               set: { if !$0 { model.accountError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.accountError ?? "")
        }
    }
}
