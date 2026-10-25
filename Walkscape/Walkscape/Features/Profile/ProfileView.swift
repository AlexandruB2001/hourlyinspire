import SwiftUI
import WalkscapeDomain

struct ProfileView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                    ProfileHeader()
                    AchievementsSection()
                    CollectionSection()
                    HealthSection()
                    SettingsSection()
                    AccountSection()
                }
                .padding(Theme.Spacing.l)
            }
            .background(Theme.Palette.night.ignoresSafeArea())
            .navigationTitle("Profile")
            .toolbarBackground(Theme.Palette.night, for: .navigationBar)
        }
    }
}

private struct ProfileHeader: View {
    @Environment(AppModel.self) private var model
    @State private var editingName = false
    @State private var draftName = ""
    @State private var nameError: String?

    var body: some View {
        @Bindable var model = model
        VStack(spacing: Theme.Spacing.l) {
            HStack(spacing: Theme.Spacing.l) {
                ZStack {
                    RoundedRectangle(cornerRadius: Theme.Radius.m).fill(Theme.Palette.skyMuted)
                    WalkingCharacter(avatarID: model.settings.avatarID, walking: true, pixel: 4)
                }
                .frame(width: 92, height: 100)
                .overlay(RoundedRectangle(cornerRadius: Theme.Radius.m).strokeBorder(Theme.Palette.ink, lineWidth: 2))

                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    Button {
                        draftName = model.settings.username
                        editingName = true
                    } label: {
                        HStack(spacing: Theme.Spacing.xs) {
                            Text((model.isSignedIn ? "@" : "") + model.settings.username)
                                .font(Theme.Typography.title)
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                            Image(systemName: "pencil").font(.caption)
                        }
                        .foregroundStyle(Theme.Palette.cream)
                    }
                    .accessibilityLabel("Username \(model.settings.username). Edit")
                    StatBlock(value: DistanceFormatting.kilometres(model.progression.lifetimeMeters), label: "walked in total")
                    Text("\(model.progression.activeDays()) active days · best \(DistanceFormatting.kilometres(model.progression.bestDayMeters))")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Palette.creamDim)
                }
                Spacer(minLength: 0)
            }

            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                Eyebrow("Choose your walker")
                HStack(spacing: Theme.Spacing.s) {
                    ForEach(AvatarCatalog.starters) { avatar in
                        Button { model.setAvatar(avatar.id) } label: {
                            AvatarPortrait(avatarID: avatar.id, size: 44,
                                           ring: model.settings.avatarID == avatar.id ? Theme.Palette.gold : Theme.Palette.ink)
                        }
                        .accessibilityLabel(avatar.name)
                        .accessibilityAddTraits(model.settings.avatarID == avatar.id ? .isSelected : [])
                    }
                }
            }
        }
        .pixelPanel()
        .alert("Username", isPresented: $editingName) {
            TextField("Username", text: $draftName)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            Button("Save") {
                let name = draftName
                Task { nameError = await model.updateUsername(name) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            if model.isSignedIn {
                Text("Friends find you by this name. 3–20 lowercase letters, numbers or underscores.")
            }
        }
        .alert("Username not saved", isPresented: Binding(get: { nameError != nil }, set: { if !$0 { nameError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(nameError ?? "")
        }
    }
}

private struct AchievementsSection: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let achievements = AchievementCatalog.standard
        let unlocked = achievements.filter { $0.isUnlocked(by: model.progression) }.count
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            SectionHeader(title: "Achievements") {
                Text("\(unlocked)/\(achievements.count)").font(Theme.Typography.caption).foregroundStyle(Theme.Palette.creamDim)
            }
            ForEach(achievements) { achievement in
                let progress = achievement.progress(for: model.progression)
                let done = progress >= 1
                HStack(spacing: Theme.Spacing.m) {
                    ItemIcon(spriteID: achievement.spriteID, pixel: 3, locked: !done)
                    VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                        Text(achievement.name)
                            .font(Theme.Typography.headline)
                            .foregroundStyle(done ? Theme.Palette.gold : Theme.Palette.cream)
                        Text(achievement.detail)
                            .font(Theme.Typography.caption)
                            .foregroundStyle(Theme.Palette.creamDim)
                        if !done {
                            PixelProgressBar(fraction: progress, segments: 10, fill: Theme.Palette.leaf, height: 10)
                        }
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(achievement.name), \(done ? "unlocked" : "\(Int(progress * 100)) percent"). \(achievement.detail)")
            }
        }
        .pixelPanel()
    }
}

private struct CollectionSection: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let items = model.engine.catalog.allCollectibles
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            SectionHeader(title: "Collection") {
                Text("\(model.progression.collectedItemIDs.count)/\(items.count)")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Palette.creamDim)
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: Theme.Spacing.s), count: 5),
                      spacing: Theme.Spacing.s) {
                ForEach(items) { item in
                    let found = model.progression.collectedItemIDs.contains(item.id)
                    ItemIcon(spriteID: item.spriteID, pixel: 3, locked: !found)
                        .frame(maxWidth: .infinity, minHeight: 50)
                        .background(RoundedRectangle(cornerRadius: Theme.Radius.s).fill(Theme.Palette.forestRaised))
                        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.s).strokeBorder(Theme.Palette.ink, lineWidth: 2))
                        .accessibilityElement()
                        .accessibilityLabel(found ? item.name : "Undiscovered item")
                }
            }
        }
        .pixelPanel()
    }
}

private struct HealthSection: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            SectionHeader(title: "Walking data")
            Picker("Source", selection: Binding(get: { model.dataSource }, set: { model.switchDataSource(to: $0) })) {
                Text("Apple Health").tag(WalkingDataSourceKind.appleHealth)
                Text("Demo data").tag(WalkingDataSourceKind.demo)
            }
            .pickerStyle(.segmented)

            row("Status", statusText)
            row("Last update", model.sync.lastSuccessfulRefresh.map { RelativeTime.short(since: $0, now: model.now) } ?? "Never")
            row("Reads", "Steps, walking + running distance")

            if !model.isDemo && model.authorization != .requested && model.authorization != .unavailable {
                Button("Connect Apple Health") { Task { await model.connectAppleHealth() } }.buttonStyle(.pixel)
            }
            Text("To change permissions, open Settings › Health › Data Access & Devices › Walkscape. Apple doesn't tell apps whether read access was denied, so missing permission looks the same as no walking yet.")
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Palette.creamDim)
                .fixedSize(horizontal: false, vertical: true)
        }
        .pixelPanel()
    }

    private var statusText: String {
        if model.isDemo { return "Demo data (not real)" }
        switch model.authorization {
        case .unavailable: return "Not available on this device"
        case .notDetermined: return "Not connected"
        case .requested:
            switch model.sync.phase {
            case .failed: return "Error reading data"
            case .noData: return "Connected · no data today"
            case .loading: return "Syncing…"
            default: return "Connected"
            }
        }
    }

    private func row(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title).foregroundStyle(Theme.Palette.creamDim)
            Spacer()
            Text(value).foregroundStyle(Theme.Palette.cream).multilineTextAlignment(.trailing)
        }
        .font(Theme.Typography.caption)
    }
}

private struct SettingsSection: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            SectionHeader(title: "Notifications & privacy")
            Toggle("Daily walk reminder", isOn: $model.settings.dailyReminderEnabled)
            Text("Reminders are saved now and will be delivered once notifications are added.")
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Palette.creamDim)
            Toggle("Share daily totals with friends",
                   isOn: Binding(get: { model.settings.shareProgressWithFriends }, set: { model.setShareProgress($0) }))
            Text("Only today's step count and distance are shared, never raw Health data or location.")
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Palette.creamDim)
        }
        .tint(Theme.Palette.leaf)
        .font(Theme.Typography.body)
        .foregroundStyle(Theme.Palette.cream)
        .pixelPanel()
    }
}

private struct AccountSection: View {
    @Environment(AppModel.self) private var model
    @State private var confirmingDelete = false
    @State private var isDeleting = false
    @State private var deleteError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            SectionHeader(title: "Account")
            switch model.account {
            case .localOnly:
                Label("Friend sync isn't configured in this build, so your progress stays on this device.",
                      systemImage: "iphone")
            case .signedOut:
                Text("Sign in to sync your daily totals with friends. Your walking history stays on this device either way.")
                WalkscapeSignInButton()
            case .signedIn(let profile):
                Label("Signed in as @\(profile.username)", systemImage: "person.crop.circle.badge.checkmark")
                    .foregroundStyle(Theme.Palette.cream)
                HStack(spacing: Theme.Spacing.m) {
                    Button("Sign out") { Task { await model.signOut() } }
                        .buttonStyle(.pixelQuiet)
                    Button("Delete account", role: .destructive) { confirmingDelete = true }
                        .buttonStyle(.pixelQuiet)
                        .disabled(isDeleting)
                }
            }
            Label("Walkscape Plus — optional cosmetics, coming later. Walking, zones and friends stay free.",
                  systemImage: "crown")
        }
        .font(Theme.Typography.caption)
        .foregroundStyle(Theme.Palette.creamDim)
        .pixelPanel()
        .confirmationDialog("Delete your Walkscape account?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Delete account permanently", role: .destructive) {
                isDeleting = true
                Task {
                    deleteError = await model.deleteAccount()
                    isDeleting = false
                }
            }
        } message: {
            Text("This removes your profile, friends and shared daily totals from our server. It can't be undone. Walking history on this device is kept.")
        }
        .alert("Account not deleted", isPresented: Binding(get: { deleteError != nil }, set: { if !$0 { deleteError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(deleteError ?? "")
        }
    }
}
