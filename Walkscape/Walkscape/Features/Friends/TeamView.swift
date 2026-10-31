import SwiftUI
import WalkscapeDomain

/// The Teams view of the Social tab: create or join a team, then walk
/// together toward expeditions and climb the weekly standings.
struct TeamSection: View {
    @Environment(AppModel.self) private var model
    @State private var message: String?
    @State private var guide: GuideSection.ID?

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.l) {
            if model.isSignedIn, model.shouldShowTip(.team) {
                TipCard(tip: .team) { guide = $0 }
            }
            if model.usesSampleFriends {
                ContentUnavailableView {
                    Label("Teams need an account", systemImage: "person.3.fill")
                } description: {
                    Text("This preview build has no server, so there are no real teams to join.")
                }
                .foregroundStyle(Theme.Palette.cream)
            } else if !model.isSignedIn {
                SignInCard()
                Text("Teams are real walkers on the Walkscape server. Sign in with Apple to create or join one.")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Palette.creamDim)
            } else if let team = model.team {
                TeamDashboardView(dashboard: team, message: $message)
            } else if model.isLoadingTeam && !model.hasLoadedTeam {
                ProgressView().tint(Theme.Palette.gold).frame(maxWidth: .infinity, minHeight: 120)
            } else {
                if !model.teamInvites.isEmpty { TeamInvitesCard(message: $message) }
                CreateTeamCard(message: $message)
                JoinTeamCard(message: $message)
            }
            if let error = model.teamError {
                Label(error, systemImage: "wifi.exclamationmark")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Palette.ember)
            }
            Text("Teammates see your daily and weekly distance only while sharing is on (Profile). Other teams only see team names and combined distance.")
                .font(Theme.Typography.micro)
                .foregroundStyle(Theme.Palette.creamDim.opacity(0.85))
        }
        .sheet(item: $guide) { GuideView(start: $0) }
        .alert("Team", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(message ?? "")
        }
    }
}

private struct CreateTeamCard: View {
    @Environment(AppModel.self) private var model
    @Binding var message: String?
    @State private var name = ""
    @State private var isWorking = false
    /// Kept across retries of one attempt, so it's only ever charged once.
    @State private var requestID = UUID()

    var body: some View {
        let cost = CreationCosts.team
        let affordable = model.spendableCoins >= cost
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            HStack(spacing: Theme.Spacing.m) {
                ItemIcon(spriteID: "team-badge", pixel: 3)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Start a team")
                        .font(Theme.Typography.headline)
                        .foregroundStyle(Theme.Palette.cream)
                    Text("Up to 12 walkers. Your distance adds up to shared expeditions.")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Palette.creamDim)
                }
            }
            CreationCostRow(cost: cost, balance: model.spendableCoins)
            HStack {
                TextField("Team name", text: $name)
                    .font(Theme.Typography.body)
                    .padding(Theme.Spacing.s)
                    .background(RoundedRectangle(cornerRadius: Theme.Radius.s).fill(Theme.Palette.forestRaised))
                    .foregroundStyle(Theme.Palette.cream)
                Button {
                    isWorking = true
                    Task {
                        message = await model.createTeam(named: name, requestID: requestID)
                        if message == nil { requestID = UUID() }
                        isWorking = false
                    }
                } label: {
                    if isWorking { ProgressView().tint(Theme.Palette.ink) } else { CoinPriceLabel(text: "Create", price: cost) }
                }
                .buttonStyle(.pixel)
                .disabled(name.trimmingCharacters(in: .whitespaces).count < 3 || isWorking || !affordable)
                .opacity(affordable ? 1 : 0.5)
            }
        }
        .pixelPanel()
    }
}

private struct JoinTeamCard: View {
    @Environment(AppModel.self) private var model
    @Binding var message: String?
    @State private var code = ""
    @State private var isWorking = false

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            Text("Join with a code")
                .font(Theme.Typography.headline)
                .foregroundStyle(Theme.Palette.cream)
            HStack {
                TextField("Team code", text: $code)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .font(Theme.Typography.headline.monospaced())
                    .padding(Theme.Spacing.s)
                    .background(RoundedRectangle(cornerRadius: Theme.Radius.s).fill(Theme.Palette.forestRaised))
                    .foregroundStyle(Theme.Palette.cream)
                Button("Join") {
                    isWorking = true
                    Task {
                        message = await model.joinTeam(code: code)
                        isWorking = false
                    }
                }
                .buttonStyle(.pixelSecondary)
                .disabled(code.isEmpty || isWorking)
            }
        }
        .pixelPanel()
    }
}

private struct TeamInvitesCard: View {
    @Environment(AppModel.self) private var model
    @Binding var message: String?

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            SectionHeader(title: "Team invites")
            ForEach(model.teamInvites) { invite in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(invite.teamName)
                            .font(Theme.Typography.headline)
                            .foregroundStyle(Theme.Palette.cream)
                        Text("from @\(invite.fromUsername)")
                            .font(Theme.Typography.caption)
                            .foregroundStyle(Theme.Palette.creamDim)
                    }
                    Spacer()
                    Button("Join") { Task { message = await model.respond(to: invite, accept: true) } }
                        .buttonStyle(.pixel)
                    Button("No") { Task { message = await model.respond(to: invite, accept: false) } }
                        .buttonStyle(.pixelQuiet)
                }
            }
        }
        .pixelPanel(fill: Theme.Palette.forestRaised)
    }
}

private struct TeamDashboardView: View {
    @Environment(AppModel.self) private var model
    let dashboard: TeamDashboard
    @Binding var message: String?
    @State private var confirmingLeave = false

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.l) {
            header
            TeamMapCard(dashboard: dashboard)
            if let site = model.campsite { CampfireCard(campsite: site, teamName: dashboard.team.name) }
            TeamWorldsCard(dashboard: dashboard)
            ExpeditionCard(progress: dashboard.expeditions)
            membersCard
            standingsCard
            badgesCard
            inviteFriendsCard
            Button("Leave team", role: .destructive) { confirmingLeave = true }
                .buttonStyle(.pixelQuiet)
                .confirmationDialog("Leave \(dashboard.team.name)?", isPresented: $confirmingLeave, titleVisibility: .visible) {
                    Button("Leave", role: .destructive) { Task { message = await model.leaveTeam() } }
                } message: {
                    Text("Your walking stops counting toward this team's expeditions.")
                }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            HStack(spacing: Theme.Spacing.m) {
                ItemIcon(spriteID: "team-badge", pixel: 4)
                VStack(alignment: .leading, spacing: 2) {
                    Text(dashboard.team.name)
                        .font(Theme.Typography.title)
                        .foregroundStyle(Theme.Palette.cream)
                    Text("\(dashboard.team.memberCount) walkers · code \(dashboard.team.joinCode)")
                        .font(Theme.Typography.caption.monospaced())
                        .foregroundStyle(Theme.Palette.creamDim)
                }
                Spacer()
                ShareLink(item: InviteLink.url,
                          message: Text("Join my Walkscape team \"\(dashboard.team.name)\" with code \(dashboard.team.joinCode).")) {
                    Image(systemName: "square.and.arrow.up")
                }
                .buttonStyle(.pixelQuiet)
                .accessibilityLabel("Share team code")
            }
            HStack {
                StatBlock(value: DistanceFormatting.kilometres(dashboard.dayMeters), label: "together today")
                Spacer()
                StatBlock(value: DistanceFormatting.kilometres(dashboard.weekMeters), label: "this week", alignment: .center)
                Spacer()
                StatBlock(value: dashboard.myStanding.map { "#\($0.rank)" } ?? "–", label: "weekly rank", alignment: .trailing)
            }
        }
        .pixelPanel()
    }

    private var membersCard: some View {
        let dayTotal = max(1, dashboard.dayMeters)
        return VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            SectionHeader(title: "Today's walkers")
            ForEach(dashboard.membersByToday) { member in
                HStack(spacing: Theme.Spacing.m) {
                    AvatarPortrait(avatarID: member.avatarID, outfit: model.outfit(for: member.id), size: 36,
                                   ring: member.isCurrentUser ? Theme.Palette.gold : Theme.Palette.ink)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: Theme.Spacing.xs) {
                            Text(member.isCurrentUser ? "You" : "@\(member.username)")
                                .font(Theme.Typography.caption)
                                .foregroundStyle(Theme.Palette.cream)
                            if member.isOwner {
                                Image(systemName: "crown.fill").font(.caption2).foregroundStyle(Theme.Palette.gold)
                            }
                        }
                        if let title = model.titleName(for: member.isCurrentUser ? model.currentUserID : member.id) {
                            TitleLabel(title: title)
                        }
                        if let meters = member.dayMeters {
                            PixelProgressBar(fraction: Double(meters) / Double(dayTotal), segments: 10,
                                             fill: member.isCurrentUser ? Theme.Palette.gold : Theme.Palette.leaf, height: 8)
                        } else {
                            Text(member.isSharing ? "No walking synced today" : "Not sharing")
                                .font(Theme.Typography.micro)
                                .foregroundStyle(Theme.Palette.creamDim)
                        }
                    }
                    Spacer(minLength: Theme.Spacing.s)
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(member.dayMeters.map { DistanceFormatting.kilometres($0) } ?? "–")
                            .font(Theme.Typography.caption.monospacedDigit())
                            .foregroundStyle(Theme.Palette.cream)
                        Text(member.daySteps.map { "\($0.formatted()) steps" } ?? " ")
                            .font(Theme.Typography.micro)
                            .foregroundStyle(Theme.Palette.creamDim)
                        Text(member.weekMeters.map { "\(DistanceFormatting.kilometres($0)) week" } ?? " ")
                            .font(Theme.Typography.micro)
                            .foregroundStyle(Theme.Palette.creamDim)
                    }
                }
                .accessibilityElement(children: .combine)
            }
        }
        .pixelPanel()
    }

    private var standingsCard: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            SectionHeader(title: "This week's competition") {
                Text("from \(dashboard.weekStart.displayDate)")
                    .font(Theme.Typography.micro)
                    .foregroundStyle(Theme.Palette.creamDim)
            }
            ForEach(dashboard.standings) { standing in
                HStack {
                    Text("#\(standing.rank)")
                        .font(Theme.Typography.caption.monospacedDigit())
                        .foregroundStyle(standing.rank <= 3 ? Theme.Palette.gold : Theme.Palette.creamDim)
                        .frame(width: 36, alignment: .leading)
                    Text(standing.name)
                        .font(Theme.Typography.caption)
                        .foregroundStyle(standing.isMine ? Theme.Palette.gold : Theme.Palette.cream)
                        .lineLimit(1)
                    Spacer()
                    Text("\(standing.memberCount) · \(DistanceFormatting.kilometres(standing.weekMeters))")
                        .font(Theme.Typography.caption.monospacedDigit())
                        .foregroundStyle(Theme.Palette.creamDim)
                }
                .padding(.vertical, 2)
                .padding(.horizontal, Theme.Spacing.s)
                .background(RoundedRectangle(cornerRadius: Theme.Radius.s)
                    .fill(standing.isMine ? Theme.Palette.forestRaised : .clear))
            }
            Text("Weeks run Monday to Sunday. Ranked by combined distance of members who share.")
                .font(Theme.Typography.micro)
                .foregroundStyle(Theme.Palette.creamDim)
        }
        .pixelPanel()
    }

    private var badgesCard: some View {
        let badges = dashboard.badges
        return VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            SectionHeader(title: "Team badges")
            if badges.isEmpty {
                Text("Walk 25 km together in a week, or finish an expedition, to earn your first badge.")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Palette.creamDim)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), spacing: Theme.Spacing.m)], spacing: Theme.Spacing.m) {
                    ForEach(badges) { badge in
                        VStack(spacing: Theme.Spacing.xs) {
                            ItemIcon(spriteID: badge.spriteID, pixel: 3)
                            Text(badge.name)
                                .font(Theme.Typography.micro)
                                .foregroundStyle(Theme.Palette.gold)
                                .multilineTextAlignment(.center)
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityHint(badge.detail)
                    }
                }
            }
        }
        .pixelPanel()
    }

    @ViewBuilder
    private var inviteFriendsCard: some View {
        let memberIDs = Set(dashboard.members.map(\.id))
        let friends = model.friends.filter { !memberIDs.contains($0.userID) }
        if !friends.isEmpty {
            VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                SectionHeader(title: "Invite friends")
                ForEach(friends) { friend in
                    HStack(spacing: Theme.Spacing.m) {
                        AvatarPortrait(avatarID: friend.avatarID, size: 32)
                        Text("@\(friend.username)")
                            .font(Theme.Typography.caption)
                            .foregroundStyle(Theme.Palette.cream)
                        Spacer()
                        Button("Invite") {
                            Task { message = await model.inviteToTeam(friend.userID) ?? "Invite sent to @\(friend.username)." }
                        }
                        .buttonStyle(.pixelSecondary)
                    }
                }
            }
            .pixelPanel()
        }
    }
}

private struct ExpeditionCard: View {
    let progress: ExpeditionProgress

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            Eyebrow("Shared expedition", color: Theme.Palette.gold)
            if let current = progress.current {
                HStack(spacing: Theme.Spacing.m) {
                    ItemIcon(spriteID: current.spriteID, pixel: 4)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(current.name)
                            .font(Theme.Typography.headline)
                            .foregroundStyle(Theme.Palette.cream)
                        Text(current.detail)
                            .font(Theme.Typography.caption)
                            .foregroundStyle(Theme.Palette.creamDim)
                    }
                }
                PixelProgressBar(fraction: progress.fraction, segments: 20, fill: Theme.Palette.gold)
                Text("\(DistanceFormatting.kilometres(progress.metersIntoCurrent)) of \(DistanceFormatting.kilometres(current.goalMeters))")
                    .font(Theme.Typography.caption.monospacedDigit())
                    .foregroundStyle(Theme.Palette.creamDim)
            } else {
                Text("Every expedition complete. Legendary walking!")
                    .font(Theme.Typography.headline)
                    .foregroundStyle(Theme.Palette.gold)
            }
            if !progress.completed.isEmpty {
                HStack(spacing: Theme.Spacing.s) {
                    ForEach(progress.completed) { ItemIcon(spriteID: $0.spriteID, pixel: 2) }
                    Text("\(progress.completed.count) completed")
                        .font(Theme.Typography.micro)
                        .foregroundStyle(Theme.Palette.creamDim)
                }
            }
        }
        .pixelPanel(fill: Theme.Palette.forestRaised)
    }
}
