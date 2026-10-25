import SwiftUI
import WalkscapeDomain

struct FriendsView: View {
    @Environment(AppModel.self) private var model
    @State private var showingAddFriend = false
    @State private var pendingRemoval: TrackParticipant?
    @State private var pendingBlock: TrackParticipant?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                    trackSection
                    FocusCard()
                    leaderboardSection
                    FriendRequestsSection()
                    privacyNote
                }
                .padding(Theme.Spacing.l)
            }
            .background(Theme.Palette.night.ignoresSafeArea())
            .navigationTitle("Friends")
            .toolbarBackground(Theme.Palette.night, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showingAddFriend = true } label: {
                        Label("Add friend", systemImage: "person.badge.plus")
                    }
                    .tint(Theme.Palette.gold)
                }
            }
            .refreshable { await model.refreshFriends() }
            .sheet(isPresented: $showingAddFriend) { AddFriendSheet() }
            .confirmationDialog("Remove \(pendingRemoval?.name ?? "friend")?", isPresented: removalBinding,
                                titleVisibility: .visible, presenting: pendingRemoval) { friend in
                Button("Remove", role: .destructive) { Task { await model.removeFriend(friend.id) } }
            } message: { friend in
                Text("\(friend.name) won't see your daily progress any more.")
            }
            .confirmationDialog("Block \(pendingBlock?.name ?? "user")?", isPresented: blockBinding,
                                titleVisibility: .visible, presenting: pendingBlock) { friend in
                Button("Block", role: .destructive) { Task { await model.blockFriend(friend.id) } }
            } message: { friend in
                Text("\(friend.name) will be removed and can't send you requests.")
            }
        }
    }

    private var removalBinding: Binding<Bool> {
        Binding(get: { pendingRemoval != nil }, set: { if !$0 { pendingRemoval = nil } })
    }

    private var blockBinding: Binding<Bool> {
        Binding(get: { pendingBlock != nil }, set: { if !$0 { pendingBlock = nil } })
    }

    private var trackSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            HStack {
                Eyebrow("Today's shared trail")
                Spacer()
                Text(model.today.isoString)
                    .font(Theme.Typography.caption.monospacedDigit())
                    .foregroundStyle(Theme.Palette.creamDim)
            }
            FriendTrackView(style: .full)
            if let error = model.friendsError {
                Label(error, systemImage: "wifi.exclamationmark")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Palette.ember)
            }
            Text("Drag to explore. Tap a walker or an edge badge to jump to them.")
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Palette.creamDim)
        }
    }

    private var leaderboardSection: some View {
        let entries = Leaderboard.rank(model.trackParticipants)
        return VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            SectionHeader(title: "Today's leaderboard")
            if model.friends.isEmpty {
                ContentUnavailableView {
                    Label("No friends yet", systemImage: "person.2")
                } description: {
                    Text("Invite a friend to compare today's walking distance.")
                } actions: {
                    Button("Add a friend") { showingAddFriend = true }.buttonStyle(.pixel)
                }
            } else {
                ForEach(entries) { entry in
                    LeaderboardRow(entry: entry)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            guard entry.participant.isPlaceable else { return }
                            withAnimation(.trackFocus) {
                                model.trackFocus.focus(on: entry.participant.id, currentUserID: model.currentUserID)
                            }
                        }
                        .contextMenu {
                            if !entry.participant.isCurrentUser {
                                Button("Show on track", systemImage: "scope") {
                                    model.trackFocus.focus(on: entry.participant.id, currentUserID: model.currentUserID)
                                }
                                .disabled(!entry.participant.isPlaceable)
                                Button("Remove friend", systemImage: "person.badge.minus", role: .destructive) {
                                    pendingRemoval = entry.participant
                                }
                                Button("Block", systemImage: "hand.raised", role: .destructive) {
                                    pendingBlock = entry.participant
                                }
                            }
                        }
                    if entry.id != entries.last?.id {
                        Divider().overlay(Theme.Palette.ink)
                    }
                }
                Text("Only distances recorded by Apple Health are ranked. Estimated distances are shown but unranked.")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Palette.creamDim)
            }
        }
        .pixelPanel()
    }

    private var privacyNote: some View {
        Label {
            Text("Friends see only your daily step and distance totals. Walkscape never uses or shares your location — the track compares distance walked, not where anyone is.")
        } icon: {
            Image(systemName: "lock.shield")
        }
        .font(Theme.Typography.caption)
        .foregroundStyle(Theme.Palette.creamDim)
    }
}

/// Details for the focused friend, with "Back to me".
private struct FocusCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Group {
            if let id = model.trackFocus.focusedFriendID,
               let friend = model.trackParticipants.first(where: { $0.id == id }),
               let meters = friend.distanceMeters {
                let gap = meters - (model.me.distanceMeters ?? 0)
                let zone = model.engine.catalog.zone(forMeters: meters)
                VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                    HStack(spacing: Theme.Spacing.m) {
                        AvatarPortrait(avatarID: friend.avatarID, size: 48, ring: Theme.Palette.gold)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(friend.name).font(Theme.Typography.title).foregroundStyle(Theme.Palette.cream)
                            Text("\((friend.isDistanceEstimated ? "≈" : "") + DistanceFormatting.kilometres(meters)) today · \(zone.name)")
                                .font(Theme.Typography.caption)
                                .foregroundStyle(Theme.Palette.creamDim)
                        }
                        Spacer()
                    }
                    Text(GapText.comparison(name: friend.name, gap: gap))
                        .font(Theme.Typography.body)
                        .foregroundStyle(Theme.Palette.cream)
                    HStack {
                        Text("You: \(DistanceFormatting.kilometres(model.distanceMeters))")
                            .font(Theme.Typography.caption)
                            .foregroundStyle(Theme.Palette.gold)
                        Spacer()
                        BackToMeButton { withAnimation(.trackFocus) { model.trackFocus.backToMe() } }
                    }
                }
                .pixelPanel(fill: Theme.Palette.forestRaised)
                .transition(.move(edge: .top).combined(with: .opacity))
            } else if case .free(let center, let span) = model.trackFocus.focus {
                HStack {
                    Text("Exploring \(DistanceFormatting.kilometres(max(0, center - span / 2)))–\(DistanceFormatting.kilometres(center + span / 2))")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Palette.creamDim)
                    Spacer()
                    BackToMeButton { withAnimation(.trackFocus) { model.trackFocus.backToMe() } }
                }
                .pixelPanel(padding: Theme.Spacing.m)
            }
        }
        .animation(.trackFocus, value: model.trackFocus)
    }
}
