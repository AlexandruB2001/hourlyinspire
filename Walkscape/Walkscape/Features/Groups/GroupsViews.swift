import CoreImage.CIFilterBuiltins
import SwiftUI
import VisionKit
import WalkscapeDomain

// MARK: - Groups list (the "Groups" option of the Social dropdown)

/// Community groups: everyone walks for themselves and compares on a shared
/// leaderboard. Nothing is pooled, unlike a team.
struct GroupsSection: View {
    @Environment(AppModel.self) private var model
    @State private var creating = false
    @State private var joining: JoinRequest?
    @State private var opened: CommunityGroup?

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.l) {
            if model.usesSampleFriends {
                ContentUnavailableView {
                    Label("Groups need an account", systemImage: "person.3.fill")
                } description: {
                    Text("This preview build has no server, so there are no real groups to join.")
                }
                .foregroundStyle(Theme.Palette.cream)
            } else if !model.isSignedIn {
                SignInCard()
                Text("Groups are communities of real walkers on the Walkscape server. Sign in with Apple to create or join one.")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Palette.creamDim)
            } else {
                if model.groups.isEmpty {
                    emptyState
                } else {
                    SectionHeader(title: "Your groups") {
                        Text("\(model.groups.count)/\(GroupRules.maxGroups)")
                            .font(Theme.Typography.caption.monospacedDigit())
                            .foregroundStyle(Theme.Palette.creamDim)
                    }
                    ForEach(model.groups) { group in
                        Button { opened = group } label: { GroupRow(group: group) }
                            .buttonStyle(.plain)
                    }
                }
                actions
                if let error = model.groupsError {
                    Label(error, systemImage: "wifi.exclamationmark")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Palette.ember)
                }
                Text("Members see your username, walker and daily and weekly totals while sharing is on (Profile). Only members can see a group's leaderboard.")
                    .font(Theme.Typography.micro)
                    .foregroundStyle(Theme.Palette.creamDim.opacity(0.85))
            }
        }
        .task { if model.isSignedIn && !model.hasLoadedGroups { await model.refreshGroups() } }
        .sheet(isPresented: $creating) { CreateGroupSheet() }
        .sheet(item: $joining) { JoinGroupSheet(start: $0) }
        .sheet(item: $opened) { group in GroupDashboardView(groupID: group.id) }
    }

    private var emptyState: some View {
        VStack(spacing: Theme.Spacing.m) {
            HStack(spacing: Theme.Spacing.s) {
                ForEach(["flag", "team-badge", "medal"], id: \.self) { ItemIcon(spriteID: $0, pixel: 3) }
            }
            Text("No groups yet")
                .font(Theme.Typography.title)
                .foregroundStyle(Theme.Palette.cream)
            Text("Groups are walking communities: your gym, your workplace, your class or your family. Everyone walks on their own and races up the daily and weekly leaderboards.")
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Palette.creamDim)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .pixelPanel(fill: Theme.Palette.forestRaised)
    }

    private var actions: some View {
        let full = model.groups.count >= GroupRules.maxGroups
        return VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            HStack(spacing: Theme.Spacing.m) {
                Button { creating = true } label: {
                    CoinPriceLabel(text: "Create a group", price: CreationCosts.group)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.pixel)
                .disabled(full)
                Button { joining = JoinRequest(code: "") } label: {
                    Label("Join", systemImage: "qrcode.viewfinder").frame(maxWidth: .infinity)
                }
                .buttonStyle(.pixelSecondary)
                .disabled(full)
            }
            Text(full ? GroupError.limitReached.message : "Joining a group is free. You can be in up to \(GroupRules.maxGroups).")
                .font(Theme.Typography.micro)
                .foregroundStyle(full ? Theme.Palette.ember : Theme.Palette.creamDim)
        }
    }
}

struct JoinRequest: Identifiable {
    let id = UUID()
    let code: String
}

private struct GroupRow: View {
    let group: CommunityGroup

    var body: some View {
        HStack(spacing: Theme.Spacing.m) {
            GroupEmblem(spriteID: group.emblem, size: 48)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: Theme.Spacing.xs) {
                    Text(group.name)
                        .font(Theme.Typography.headline)
                        .foregroundStyle(Theme.Palette.cream)
                        .lineLimit(1)
                    if group.isOwner {
                        Image(systemName: "crown.fill").font(.caption2).foregroundStyle(Theme.Palette.gold)
                    }
                }
                Text(group.memberCount == 1 ? "1 member" : "\(group.memberCount) members")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Palette.creamDim)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").foregroundStyle(Theme.Palette.creamDim)
        }
        .pixelPanel()
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens the group's leaderboards")
    }
}

/// A group's emblem on a small pixel shield.
struct GroupEmblem: View {
    let spriteID: String
    var size: CGFloat = 44

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: Theme.Radius.s).fill(Theme.Palette.skyMuted)
            ItemIcon(spriteID: spriteID, pixel: size / 14)
        }
        .frame(width: size, height: size)
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.s).strokeBorder(Theme.Palette.gold, lineWidth: 2))
        .accessibilityHidden(true)
    }
}

// MARK: - Costs

/// "◉ 500" next to a label, for things that cost coins.
struct CoinPriceLabel: View {
    let text: String
    let price: Int

    var body: some View {
        HStack(spacing: Theme.Spacing.xs) {
            Text(text)
            ItemIcon(spriteID: "coin", pixel: 1.4)
            Text("\(price)").monospacedDigit()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(text), \(price) coins")
    }
}

/// The cost and your balance, before you confirm.
struct CreationCostRow: View {
    let cost: Int
    let balance: Int

    var body: some View {
        let short = max(0, cost - balance)
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: Theme.Spacing.s) {
                Text("Costs")
                ItemIcon(spriteID: "coin", pixel: 1.4)
                Text("\(cost)").monospacedDigit()
                Text("·  You have")
                ItemIcon(spriteID: "coin", pixel: 1.4)
                Text("\(balance)").monospacedDigit()
            }
            .font(Theme.Typography.caption)
            .foregroundStyle(Theme.Palette.gold)
            if short > 0 {
                Text("You need \(short) more coins. Walk, open chests and finish quests to earn them.")
                    .font(Theme.Typography.micro)
                    .foregroundStyle(Theme.Palette.ember)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(short > 0 ? "Costs \(cost) coins. You have \(balance), \(short) short."
                                      : "Costs \(cost) coins. You have \(balance).")
    }
}

// MARK: - Creating

private struct CreateGroupSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var description = ""
    @State private var emblem = GroupRules.emblems[0]
    @State private var isWorking = false
    @State private var error: String?
    @State private var confirming = false
    @State private var created: CommunityGroup?
    /// Kept across retries of one attempt, so the group is made and paid for once.
    @State private var requestID = UUID()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                    if let created {
                        Text("\(created.name) is ready!")
                            .font(Theme.Typography.title)
                            .foregroundStyle(Theme.Palette.cream)
                        Text("Share the code or QR code so others can join for free.")
                            .font(Theme.Typography.caption)
                            .foregroundStyle(Theme.Palette.creamDim)
                        GroupInviteCard(group: created)
                    } else {
                        form
                    }
                }
                .padding(Theme.Spacing.l)
            }
            .background(Theme.Palette.night.ignoresSafeArea())
            .navigationTitle(created == nil ? "New group" : "Group created")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Theme.Palette.night, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(created == nil ? "Cancel" : "Done") { dismiss() }.foregroundStyle(Theme.Palette.gold)
                }
            }
            .confirmationDialog("Create \(GroupRules.cleanName(name) ?? name) for \(CreationCosts.group) coins?",
                                isPresented: $confirming, titleVisibility: .visible) {
                Button("Create for \(CreationCosts.group) coins") { create() }
            } message: {
                Text("\(CreationCosts.group) coins will be taken from your \(model.spendableCoins). Joining is free for everyone else.")
            }
        }
        .interactiveDismissDisabled(isWorking)
    }

    private var form: some View {
        let cleanName = GroupRules.cleanName(name)
        let affordable = model.spendableCoins >= CreationCosts.group
        let valid = cleanName != nil && GroupRules.isValidDescription(description)
        return VStack(alignment: .leading, spacing: Theme.Spacing.l) {
            GroupFields(name: $name, description: $description, emblem: $emblem)
            CreationCostRow(cost: CreationCosts.group, balance: model.spendableCoins)
            if let error {
                Text(error)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Palette.ember)
            }
            Button { confirming = true } label: {
                Group {
                    if isWorking { ProgressView().tint(Theme.Palette.ink) } else {
                        CoinPriceLabel(text: "Create group", price: CreationCosts.group)
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.pixel)
            .disabled(!valid || !affordable || isWorking)
            .opacity(valid && affordable ? 1 : 0.5)
        }
    }

    private func create() {
        guard let cleanName = GroupRules.cleanName(name) else { return }
        isWorking = true
        error = nil
        Task {
            let result = await model.createGroup(requestID: requestID, name: cleanName, description: description, emblem: emblem)
            isWorking = false
            switch result {
            case .success(let id):
                requestID = UUID()
                created = model.groups.first { $0.id == id }
                if created == nil { dismiss() }
            case .failure(let failure):
                error = failure.message
            }
        }
    }
}

/// Name, description and emblem, for creating and editing.
struct GroupFields: View {
    @Binding var name: String
    @Binding var description: String
    @Binding var emblem: String

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            Eyebrow("Name")
            TextField("e.g. Fit4Less Windsor", text: $name)
                .textInputAutocapitalization(.words)
                .modifier(PixelFieldStyle())
            Text("\(GroupRules.nameLength.lowerBound)–\(GroupRules.nameLength.upperBound) letters, numbers, spaces and & . , ' ! ( ) -")
                .font(Theme.Typography.micro)
                .foregroundStyle(GroupRules.cleanName(name) == nil && !name.isEmpty ? Theme.Palette.ember : Theme.Palette.creamDim)
            Eyebrow("Description (optional)")
            TextField("What brings you together?", text: $description, axis: .vertical)
                .lineLimit(2...4)
                .modifier(PixelFieldStyle())
            Text("\(description.count)/\(GroupRules.descriptionLimit)")
                .font(Theme.Typography.micro.monospacedDigit())
                .foregroundStyle(GroupRules.isValidDescription(description) ? Theme.Palette.creamDim : Theme.Palette.ember)
            Eyebrow("Emblem")
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 52), spacing: Theme.Spacing.s)], spacing: Theme.Spacing.s) {
                ForEach(GroupRules.emblems, id: \.self) { sprite in
                    Button { emblem = sprite } label: {
                        ItemIcon(spriteID: sprite, pixel: 3.2)
                            .frame(width: 48, height: 48)
                            .background(RoundedRectangle(cornerRadius: Theme.Radius.s).fill(Theme.Palette.forestRaised))
                            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.s)
                                .strokeBorder(emblem == sprite ? Theme.Palette.gold : Theme.Palette.ink, lineWidth: emblem == sprite ? 3 : 2))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(sprite.replacingOccurrences(of: "-", with: " "))
                    .accessibilityAddTraits(emblem == sprite ? .isSelected : [])
                }
            }
        }
    }
}

struct PixelFieldStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(Theme.Typography.body)
            .padding(Theme.Spacing.s)
            .background(RoundedRectangle(cornerRadius: Theme.Radius.s).fill(Theme.Palette.forestRaised))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.s).strokeBorder(Theme.Palette.ink, lineWidth: 2))
            .foregroundStyle(Theme.Palette.cream)
    }
}

// MARK: - Inviting

/// The joining code, copy and share buttons, and a QR code.
struct GroupInviteCard: View {
    let group: CommunityGroup
    @State private var copied = false

    var body: some View {
        VStack(spacing: Theme.Spacing.m) {
            Eyebrow("Joining code", color: Theme.Palette.gold)
            Text(group.joinCode)
                .font(.system(size: 34, weight: .heavy, design: .monospaced))
                .tracking(6)
                .foregroundStyle(Theme.Palette.cream)
                .textSelection(.enabled)
                .accessibilityLabel("Joining code \(group.joinCode.map(String.init).joined(separator: " "))")
            if let qr = QRCode.image(for: GroupRules.qrPayload(code: group.joinCode)) {
                Image(decorative: qr, scale: 1)
                    .interpolation(.none)
                    .resizable()
                    .frame(width: 168, height: 168)
                    .padding(Theme.Spacing.s)
                    .background(RoundedRectangle(cornerRadius: Theme.Radius.s).fill(Color.white))
                    .accessibilityLabel("QR code to join \(group.name). Scan it from Social › Groups › Join.")
            }
            HStack(spacing: Theme.Spacing.m) {
                Button {
                    UIPasteboard.general.string = group.joinCode
                    copied = true
                } label: {
                    Label(copied ? "Copied" : "Copy code", systemImage: copied ? "checkmark" : "doc.on.doc")
                }
                .buttonStyle(.pixelSecondary)
                ShareLink(item: "Join my Walkscape group \u{201C}\(group.name)\u{201D}! In Walkscape, go to Social › Groups › Join and enter \(group.joinCode).") {
                    Label("Share", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.pixel)
            }
        }
        .frame(maxWidth: .infinity)
        .pixelPanel(fill: Theme.Palette.forestRaised)
        .sensoryFeedback(.success, trigger: copied)
    }
}

enum QRCode {
    /// A crisp, unscaled QR code (scale it up with interpolation off).
    static func image(for text: String) -> CGImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }
        return CIContext().createCGImage(output, from: output.extent)
    }
}

// MARK: - Joining

private struct JoinGroupSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let start: JoinRequest
    @State private var code = ""
    @State private var preview: GroupPreview?
    @State private var error: String?
    @State private var isWorking = false
    @State private var scanning = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                    Text("Enter the six-character code from a group member, or scan their QR code.")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Palette.creamDim)
                    HStack(spacing: Theme.Spacing.s) {
                        TextField("ABC123", text: $code)
                            .textInputAutocapitalization(.characters)
                            .autocorrectionDisabled()
                            .font(.system(size: 22, weight: .heavy, design: .monospaced))
                            .modifier(PixelFieldStyle())
                            .onChange(of: code) { preview = nil; error = nil }
                        Button { scanning = true } label: { Image(systemName: "qrcode.viewfinder").font(.title2) }
                            .buttonStyle(.pixelSecondary)
                            .accessibilityLabel("Scan a QR code")
                    }
                    Button("Find group") { lookUp() }
                        .buttonStyle(.pixel)
                        .disabled(GroupRules.code(from: code) == nil || isWorking)
                    if let preview { previewCard(preview) }
                    if let error {
                        Text(error)
                            .font(Theme.Typography.caption)
                            .foregroundStyle(Theme.Palette.ember)
                    }
                }
                .padding(Theme.Spacing.l)
            }
            .background(Theme.Palette.night.ignoresSafeArea())
            .navigationTitle("Join a group")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Theme.Palette.night, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("Cancel") { dismiss() }.foregroundStyle(Theme.Palette.gold) }
            }
            .sheet(isPresented: $scanning) {
                QRScannerSheet { scanned in
                    scanning = false
                    if let found = GroupRules.code(from: scanned) {
                        code = found
                        lookUp()
                    } else {
                        error = "That QR code isn't a Walkscape group code."
                    }
                }
            }
            .onAppear { if code.isEmpty { code = start.code } }
        }
    }

    private func previewCard(_ preview: GroupPreview) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            HStack(spacing: Theme.Spacing.m) {
                GroupEmblem(spriteID: preview.emblem, size: 56)
                VStack(alignment: .leading, spacing: 2) {
                    Text(preview.name)
                        .font(Theme.Typography.title)
                        .foregroundStyle(Theme.Palette.cream)
                    Text(preview.memberCount == 1 ? "1 member" : "\(preview.memberCount) members")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Palette.creamDim)
                }
            }
            if !preview.description.isEmpty {
                Text(preview.description)
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Palette.cream.opacity(0.9))
            }
            if preview.isMember {
                Label("You're already a member", systemImage: "checkmark.seal.fill")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Palette.gold)
            } else {
                Text("Members will see your username, walker and daily and weekly totals. Joining is free.")
                    .font(Theme.Typography.micro)
                    .foregroundStyle(Theme.Palette.creamDim)
                Button {
                    isWorking = true
                    Task {
                        let result = await model.joinGroup(code: preview.code)
                        isWorking = false
                        switch result {
                        case .success: dismiss()
                        case .failure(let failure): error = failure.message
                        }
                    }
                } label: {
                    Group { if isWorking { ProgressView().tint(Theme.Palette.ink) } else { Text("Join \(preview.name)") } }
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.pixel)
                .disabled(isWorking)
            }
        }
        .pixelPanel(fill: Theme.Palette.forestRaised)
    }

    private func lookUp() {
        guard let valid = GroupRules.code(from: code) else {
            error = "Codes are six letters and numbers."
            return
        }
        isWorking = true
        error = nil
        Task {
            let result = await model.previewGroup(code: valid)
            isWorking = false
            switch result {
            case .success(let found?): preview = found
            case .success(nil): error = GroupError.notFound.message
            case .failure(let failure): error = failure.message
            }
        }
    }
}

/// The camera, looking for a QR code.
private struct QRScannerSheet: View {
    @Environment(\.dismiss) private var dismiss
    let found: (String) -> Void

    var body: some View {
        NavigationStack {
            Group {
                if DataScannerViewController.isSupported && DataScannerViewController.isAvailable {
                    QRScanner(found: found).ignoresSafeArea()
                } else {
                    ContentUnavailableView("Camera unavailable", systemImage: "camera.fill",
                                           description: Text("Allow camera access for Walkscape in Settings, or type the code instead."))
                }
            }
            .navigationTitle("Scan a group code")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("Cancel") { dismiss() } }
            }
        }
    }
}

private struct QRScanner: UIViewControllerRepresentable {
    let found: (String) -> Void

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(recognizedDataTypes: [.barcode(symbologies: [.qr])],
                                                qualityLevel: .balanced, isHighlightingEnabled: true)
        scanner.delegate = context.coordinator
        try? scanner.startScanning()
        return scanner
    }

    func updateUIViewController(_ controller: DataScannerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(found: found) }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let found: (String) -> Void
        private var done = false

        init(found: @escaping (String) -> Void) {
            self.found = found
        }

        func dataScanner(_ scanner: DataScannerViewController, didAdd items: [RecognizedItem], allItems: [RecognizedItem]) {
            guard !done else { return }
            for case .barcode(let barcode) in items {
                if let text = barcode.payloadStringValue {
                    done = true
                    scanner.stopScanning()
                    found(text)
                    return
                }
            }
        }
    }
}
