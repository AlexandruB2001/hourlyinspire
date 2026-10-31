import SwiftUI
import WalkscapeDomain

/// One group: today's and this week's standings, the invite, members and,
/// for the owner, management.
struct GroupDashboardView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let groupID: String
    @State private var period: LeaderboardPeriod = .day
    @State private var page: GroupLeaderboardPage?
    @State private var loadError: String?
    @State private var showingFullBoard = false
    @State private var showingMembers = false
    @State private var editing = false
    @State private var confirmingLeave = false
    @State private var confirmingNewCode = false
    @State private var message: String?

    private var group: CommunityGroup? { model.groups.first { $0.id == groupID } }

    var body: some View {
        NavigationStack {
            ScrollView {
                if let group {
                    VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                        header(group)
                        Picker("Leaderboard", selection: $period) {
                            ForEach(LeaderboardPeriod.allCases) { Text($0.title).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        leaderboard(group)
                        GroupInviteCard(group: group)
                        Button { showingMembers = true } label: {
                            Label("Members (\(group.memberCount))", systemImage: "person.3.fill").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.pixelSecondary)
                        if group.isOwner { ownerTools(group) }
                        Button("Leave group", role: .destructive) { confirmingLeave = true }
                            .buttonStyle(.pixelQuiet)
                        if let message {
                            Text(message)
                                .font(Theme.Typography.caption)
                                .foregroundStyle(Theme.Palette.ember)
                        }
                    }
                    .padding(Theme.Spacing.l)
                } else {
                    ContentUnavailableView("Not in this group", systemImage: "person.3",
                                           description: Text("You've left this group, or it has closed."))
                        .foregroundStyle(Theme.Palette.cream)
                        .padding(.top, Theme.Spacing.xxl)
                }
            }
            .background(Theme.Palette.night.ignoresSafeArea())
            .navigationTitle(group?.name ?? "Group")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Theme.Palette.night, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() }.foregroundStyle(Theme.Palette.gold) }
            }
            .refreshable { await load() }
            .task(id: period) { await load() }
            .sheet(isPresented: $showingFullBoard) {
                if let group { FullLeaderboardView(group: group, period: period) }
            }
            .sheet(isPresented: $showingMembers) {
                if let group { GroupMembersView(group: group) }
            }
            .sheet(isPresented: $editing) {
                if let group { EditGroupSheet(group: group) }
            }
            .confirmationDialog(leaveTitle, isPresented: $confirmingLeave, titleVisibility: .visible) {
                Button("Leave", role: .destructive) {
                    guard let group else { return }
                    Task {
                        message = await model.leaveGroup(group)
                        if message == nil { dismiss() }
                    }
                }
            } message: {
                Text(leaveMessage)
            }
            .confirmationDialog("Make a new joining code?", isPresented: $confirmingNewCode, titleVisibility: .visible) {
                Button("New code") {
                    guard let group else { return }
                    Task {
                        if case .failure(let error) = await model.regenerateCode(for: group) { message = error.message }
                    }
                }
            } message: {
                Text("The old code and QR code stop working straight away. Members stay in the group.")
            }
        }
    }

    private var leaveTitle: String { "Leave \(group?.name ?? "this group")?" }

    private var leaveMessage: String {
        guard let group, group.isOwner else { return "You can join again later with the code." }
        return group.memberCount > 1
            ? "The member who joined earliest becomes the owner."
            : "You're the last member, so the group will close."
    }

    private func header(_ group: CommunityGroup) -> some View {
        HStack(alignment: .top, spacing: Theme.Spacing.m) {
            GroupEmblem(spriteID: group.emblem, size: 64)
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text(group.name)
                    .font(Theme.Typography.title)
                    .foregroundStyle(Theme.Palette.cream)
                if !group.description.isEmpty {
                    Text(group.description)
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Palette.creamDim)
                }
                HStack(spacing: Theme.Spacing.m) {
                    Label(group.memberCount == 1 ? "1 member" : "\(group.memberCount) members", systemImage: "person.3.fill")
                    if let me = page?.me {
                        Label(me.isSharing ? "You're #\(me.rank)" : "Not sharing", systemImage: "medal.fill")
                    }
                }
                .font(Theme.Typography.micro)
                .foregroundStyle(Theme.Palette.gold)
            }
            Spacer(minLength: 0)
        }
        .pixelPanel(fill: Theme.Palette.forestRaised)
    }

    @ViewBuilder private func leaderboard(_ group: CommunityGroup) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            SectionHeader(title: period == .day ? "Today's leaderboard" : "This week's leaderboard") {
                if let updated = page?.lastUpdated {
                    Text("Updated \(RelativeTime.short(since: updated, now: model.now))")
                        .font(Theme.Typography.micro)
                        .foregroundStyle(Theme.Palette.creamDim)
                }
            }
            if let page {
                ForEach(page.rows) { StandingRow(standing: $0) }
                if page.meIsElsewhere, let me = page.me {
                    Text("···").font(Theme.Typography.caption).foregroundStyle(Theme.Palette.creamDim).frame(maxWidth: .infinity)
                    StandingRow(standing: me)
                }
                if page.memberCount > GroupRules.topCount {
                    Button("See all \(page.memberCount)") { showingFullBoard = true }
                        .buttonStyle(.pixelQuiet)
                }
                Text(period == .day
                     ? "Ranked by distance on today's date, reset at midnight."
                     : "Ranked by distance since Monday, reset Monday at midnight.")
                    .font(Theme.Typography.micro)
                    .foregroundStyle(Theme.Palette.creamDim)
            } else if let loadError {
                Label(loadError, systemImage: "wifi.exclamationmark")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Palette.ember)
            } else {
                ProgressView().tint(Theme.Palette.gold).frame(maxWidth: .infinity, minHeight: 80)
            }
        }
        .pixelPanel()
    }

    private func ownerTools(_ group: CommunityGroup) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            Eyebrow("Owner tools", color: Theme.Palette.gold)
            HStack(spacing: Theme.Spacing.m) {
                Button { editing = true } label: { Label("Edit", systemImage: "pencil") }
                    .buttonStyle(.pixelSecondary)
                Button { confirmingNewCode = true } label: { Label("New code", systemImage: "arrow.triangle.2.circlepath") }
                    .buttonStyle(.pixelSecondary)
            }
            Text("Remove members from the member list.")
                .font(Theme.Typography.micro)
                .foregroundStyle(Theme.Palette.creamDim)
        }
        .pixelPanel()
    }

    private func load() async {
        guard let group else { return }
        switch await model.groupLeaderboard(group, period: period, offset: 0, limit: GroupRules.topCount) {
        case .success(let loaded):
            page = loaded
            loadError = nil
        case .failure(let error):
            loadError = error.message
            if error == .notFound { await model.refreshGroups() }
        }
    }
}

/// One member's row: place, walker, name, distance and steps.
struct StandingRow: View {
    let standing: GroupStanding

    var body: some View {
        HStack(spacing: Theme.Spacing.m) {
            RankBadge(rank: standing.rank, highlighted: standing.isSharing)
            AvatarPortrait(avatarID: standing.avatarID, size: 34, ring: standing.isMe ? Theme.Palette.gold : Theme.Palette.ink)
            VStack(alignment: .leading, spacing: 0) {
                Text(standing.isMe ? "\(standing.username) (you)" : standing.username)
                    .font(Theme.Typography.headline)
                    .foregroundStyle(standing.isMe ? Theme.Palette.gold : Theme.Palette.cream)
                    .lineLimit(1)
                if let steps = standing.steps {
                    Text("\(DistanceFormatting.steps(steps)) steps")
                        .font(Theme.Typography.micro)
                        .foregroundStyle(Theme.Palette.creamDim)
                }
                if standing.underReview {
                    Text("A day is being double-checked")
                        .font(Theme.Typography.micro)
                        .foregroundStyle(Theme.Palette.gold)
                }
            }
            Spacer(minLength: 0)
            if let meters = standing.meters {
                Text((standing.estimated ? "≈ " : "") + DistanceFormatting.kilometres(meters))
                    .font(Theme.Typography.stat)
                    .foregroundStyle(Theme.Palette.cream)
            } else {
                Text("Not sharing")
                    .font(Theme.Typography.micro)
                    .foregroundStyle(Theme.Palette.creamDim)
            }
        }
        .padding(.vertical, Theme.Spacing.xs)
        .padding(.horizontal, Theme.Spacing.s)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.s)
            .fill(standing.isMe ? Theme.Palette.forestRaised : Color.clear))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        let name = standing.isMe ? "You" : standing.username
        guard let meters = standing.meters else { return "\(name), not sharing" }
        let estimated = standing.estimated ? ", estimated" : ""
        let review = standing.underReview ? ", a day is being double-checked" : ""
        return "Number \(standing.rank), \(name), \(DistanceFormatting.kilometres(meters))\(estimated), \(standing.steps ?? 0) steps\(review)"
    }
}

/// Gold, silver and bronze for the top three.
private struct RankBadge: View {
    let rank: Int
    let highlighted: Bool

    var body: some View {
        let colors: [Color] = [Theme.Palette.gold, Color(hex: 0xC9D2DC), Color(hex: 0xD08A5A)]
        let medal = highlighted && rank <= 3 ? colors[rank - 1] : nil
        Text(highlighted ? "\(rank)" : "–")
            .font(.system(size: 14, weight: .heavy, design: .rounded).monospacedDigit())
            .foregroundStyle(medal == nil ? Theme.Palette.creamDim : Theme.Palette.ink)
            .frame(width: 30, height: 30)
            .background(RoundedRectangle(cornerRadius: Theme.Radius.s).fill(medal ?? Theme.Palette.forestRaised))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.s).strokeBorder(Theme.Palette.ink, lineWidth: 2))
    }
}

// MARK: - Full leaderboard

private struct FullLeaderboardView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let group: CommunityGroup
    let period: LeaderboardPeriod
    @State private var rows: [GroupStanding] = []
    @State private var me: GroupStanding?
    @State private var total = 0
    @State private var error: String?
    @State private var isLoading = false

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    if let me, !rows.contains(me) {
                        Eyebrow("Your place", color: Theme.Palette.gold)
                        StandingRow(standing: me)
                        Divider().overlay(Theme.Palette.ink)
                    }
                    ForEach(rows) { StandingRow(standing: $0) }
                    if rows.count < total {
                        Button(isLoading ? "Loading…" : "Show more") { Task { await loadMore() } }
                            .buttonStyle(.pixelQuiet)
                            .disabled(isLoading)
                            .frame(maxWidth: .infinity)
                    }
                    if let error {
                        Text(error).font(Theme.Typography.caption).foregroundStyle(Theme.Palette.ember)
                    }
                }
                .padding(Theme.Spacing.l)
            }
            .background(Theme.Palette.night.ignoresSafeArea())
            .navigationTitle(period == .day ? "Today" : "This week")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Theme.Palette.night, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() }.foregroundStyle(Theme.Palette.gold) }
            }
            .task { if rows.isEmpty { await loadMore() } }
        }
    }

    private func loadMore() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        switch await model.groupLeaderboard(group, period: period, offset: rows.count, limit: GroupRules.pageSize) {
        case .success(let page):
            let seen = Set(rows.map(\.id))
            rows += page.rows.filter { !seen.contains($0.id) }
            me = page.me
            total = page.memberCount
            error = nil
        case .failure(let failure):
            error = failure.message
        }
    }
}

// MARK: - Members

private struct GroupMembersView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let group: CommunityGroup
    @State private var members: [GroupMember] = []
    @State private var total = 0
    @State private var error: String?
    @State private var removing: GroupMember?
    @State private var isLoading = false

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: Theme.Spacing.s) {
                    ForEach(members) { member in
                        HStack(spacing: Theme.Spacing.m) {
                            AvatarPortrait(avatarID: member.avatarID, size: 34)
                            Text(member.username)
                                .font(Theme.Typography.headline)
                                .foregroundStyle(Theme.Palette.cream)
                            if member.isOwner {
                                Label("Owner", systemImage: "crown.fill")
                                    .font(Theme.Typography.micro)
                                    .foregroundStyle(Theme.Palette.gold)
                            }
                            Spacer(minLength: 0)
                            if group.isOwner && !member.isOwner {
                                Button("Remove", role: .destructive) { removing = member }
                                    .buttonStyle(.pixelQuiet)
                            }
                        }
                    }
                    if members.count < total {
                        Button(isLoading ? "Loading…" : "Show more") { Task { await load(reset: false) } }
                            .buttonStyle(.pixelQuiet)
                            .disabled(isLoading)
                            .frame(maxWidth: .infinity)
                    }
                    if let error {
                        Text(error).font(Theme.Typography.caption).foregroundStyle(Theme.Palette.ember)
                    }
                }
                .padding(Theme.Spacing.l)
            }
            .background(Theme.Palette.night.ignoresSafeArea())
            .navigationTitle("Members (\(total))")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Theme.Palette.night, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() }.foregroundStyle(Theme.Palette.gold) }
            }
            .task { await load(reset: true) }
            .confirmationDialog("Remove \(removing?.username ?? "member")?", isPresented: Binding(
                get: { removing != nil }, set: { if !$0 { removing = nil } }), titleVisibility: .visible) {
                Button("Remove", role: .destructive) {
                    guard let member = removing else { return }
                    Task {
                        error = await model.removeMember(member, from: group)
                        await load(reset: true)
                    }
                }
            } message: {
                Text("They'll lose access to the group. They could join again with the code, so make a new one if needed.")
            }
        }
    }

    private func load(reset: Bool) async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        switch await model.groupMembers(group, offset: reset ? 0 : members.count) {
        case .success(let loaded):
            members = reset ? loaded.members : members + loaded.members
            total = loaded.total
        case .failure(let failure):
            error = failure.message
        }
    }
}

// MARK: - Editing

private struct EditGroupSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let group: CommunityGroup
    @State private var name = ""
    @State private var description = ""
    @State private var emblem = ""
    @State private var error: String?
    @State private var isWorking = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                    GroupFields(name: $name, description: $description, emblem: $emblem)
                    if let error {
                        Text(error).font(Theme.Typography.caption).foregroundStyle(Theme.Palette.ember)
                    }
                    Button {
                        guard let clean = GroupRules.cleanName(name) else { return }
                        isWorking = true
                        Task {
                            error = await model.updateGroup(group, name: clean, description: description, emblem: emblem)
                            isWorking = false
                            if error == nil { dismiss() }
                        }
                    } label: {
                        Text("Save").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.pixel)
                    .disabled(GroupRules.cleanName(name) == nil || !GroupRules.isValidDescription(description) || isWorking)
                }
                .padding(Theme.Spacing.l)
            }
            .background(Theme.Palette.night.ignoresSafeArea())
            .navigationTitle("Edit group")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Theme.Palette.night, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("Cancel") { dismiss() }.foregroundStyle(Theme.Palette.gold) }
            }
            .onAppear {
                name = group.name
                description = group.description
                emblem = group.emblem
            }
        }
    }
}
