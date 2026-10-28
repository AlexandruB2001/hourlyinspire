import SwiftUI
import WalkscapeDomain

/// Where people are sent to install the game. TestFlight while in beta;
/// switch to the App Store link at launch.
enum InviteLink {
    static let url = URL(string: "https://testflight.apple.com/join/A2HmzFYV")!
}

/// Your invite code, the people you invited, and a place to enter a friend's code.
struct ReferralSection: View {
    @Environment(AppModel.self) private var model
    @State private var code = ""
    @State private var message: String?
    @State private var isRedeeming = false

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            SectionHeader(title: "Invite friends") {
                ItemIcon(spriteID: "referral-chest", pixel: 2)
            }
            Text(ReferralRules.summary)
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Palette.creamDim)

            if model.usesSampleFriends {
                Text("Invites need the online version of Walkscape.")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Palette.ember)
            } else if !model.isSignedIn {
                Text("Sign in with Apple (Friends tab) to get your invite code.")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Palette.cream)
                if let pending = model.pendingReferralCode {
                    Text("Code \(pending) will be used when you sign in.")
                        .font(Theme.Typography.micro)
                        .foregroundStyle(Theme.Palette.gold)
                }
            } else if let referral = model.referral {
                yourCode(referral.code)
                invitees(referral.invitees)
                if referral.canRedeemCode && !referral.hasRedeemedCode { redeemField }
            } else if let error = model.referralError {
                Label(error, systemImage: "wifi.exclamationmark")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Palette.ember)
            } else {
                ProgressView().tint(Theme.Palette.gold)
            }

            Text("Rewards are checked on the Walkscape server using the daily totals your friend shares, so they need to be signed in with sharing on. Each friend can be counted once.")
                .font(Theme.Typography.micro)
                .foregroundStyle(Theme.Palette.creamDim.opacity(0.85))
        }
        .pixelPanel()
    }

    private func yourCode(_ code: String) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Eyebrow("Your invite code")
                Text(code)
                    .font(.system(.title, design: .monospaced).weight(.heavy))
                    .foregroundStyle(Theme.Palette.gold)
                    .textSelection(.enabled)
            }
            Spacer()
            ShareLink(item: InviteLink.url,
                      subject: Text("Walk with me in Walkscape"),
                      message: Text("Join me on Walkscape: Journey, a cozy walking game. Enter my invite code \(code) when you start.")) {
                Label("Invite", systemImage: "square.and.arrow.up")
            }
            .buttonStyle(.pixel)
        }
    }

    @ViewBuilder
    private func invitees(_ invitees: [ReferralInvitee]) -> some View {
        if invitees.isEmpty {
            Text("Nobody has used your code yet.")
                .font(Theme.Typography.caption)
                .foregroundStyle(Theme.Palette.creamDim)
        } else {
            ForEach(invitees) { invitee in
                HStack(spacing: Theme.Spacing.m) {
                    Text("@\(invitee.username)")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Palette.cream)
                    Spacer()
                    if invitee.qualified {
                        Label("Chest earned", systemImage: "gift.fill")
                            .font(Theme.Typography.micro)
                            .foregroundStyle(Theme.Palette.gold)
                    } else {
                        PixelProgressBar(fraction: invitee.progress, segments: 8, fill: Theme.Palette.leaf, height: 10)
                            .frame(width: 96)
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityValue(invitee.qualified ? "Chest earned" : "\(Int(invitee.progress * 100)) percent")
            }
        }
    }

    private var redeemField: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            Eyebrow("Got a code from a friend?")
            HStack {
                TextField("Invite code", text: $code)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .font(Theme.Typography.headline.monospaced())
                    .padding(Theme.Spacing.s)
                    .background(RoundedRectangle(cornerRadius: Theme.Radius.s).fill(Theme.Palette.forestRaised))
                    .foregroundStyle(Theme.Palette.cream)
                Button("Use") {
                    isRedeeming = true
                    Task {
                        message = await model.redeemReferral(code: code) ?? "Code accepted. Your friend will get a chest once you've walked a little."
                        isRedeeming = false
                        code = ""
                    }
                }
                .buttonStyle(.pixelSecondary)
                .disabled(code.isEmpty || isRedeeming)
            }
            if let message {
                Text(message)
                    .font(Theme.Typography.micro)
                    .foregroundStyle(Theme.Palette.gold)
            }
        }
    }
}
