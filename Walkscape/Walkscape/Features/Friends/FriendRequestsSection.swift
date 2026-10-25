import SwiftUI
import WalkscapeDomain

struct FriendRequestsSection: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let requests = model.friendRequests
        if !requests.incoming.isEmpty || !requests.outgoing.isEmpty {
            VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                SectionHeader(title: "Requests")
                ForEach(requests.incoming) { request in
                    HStack(spacing: Theme.Spacing.m) {
                        AvatarPortrait(avatarID: request.avatarID, size: 36)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(request.username).font(Theme.Typography.headline).foregroundStyle(Theme.Palette.cream)
                            Text("Wants to walk with you").font(Theme.Typography.caption).foregroundStyle(Theme.Palette.creamDim)
                        }
                        Spacer()
                        Button("Accept") { Task { await model.accept(request) } }.buttonStyle(.pixel)
                        Button {
                            Task { await model.decline(request) }
                        } label: {
                            Image(systemName: "xmark")
                        }
                        .buttonStyle(.pixelQuiet)
                        .accessibilityLabel("Decline \(request.username)")
                    }
                }
                ForEach(requests.outgoing) { request in
                    HStack(spacing: Theme.Spacing.m) {
                        AvatarPortrait(avatarID: request.avatarID, size: 36)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(request.username).font(Theme.Typography.headline).foregroundStyle(Theme.Palette.cream)
                            Text("Request sent · waiting").font(Theme.Typography.caption).foregroundStyle(Theme.Palette.creamDim)
                        }
                        Spacer()
                        Button("Cancel") { Task { await model.decline(request) } }.buttonStyle(.pixelQuiet)
                    }
                }
            }
            .pixelPanel()
        }
    }
}

struct AddFriendSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var username = ""
    @State private var message: String?
    @State private var isSending = false

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                Text("Friends see your daily distance and steps on a shared track. Requests must be accepted before anyone sees anything.")
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.Palette.creamDim)
                if model.isSignedIn {
                    Text("Your username is @\(model.settings.username)")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Palette.gold)
                }
                TextField("Friend's username", text: $username)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .padding(Theme.Spacing.m)
                    .background(RoundedRectangle(cornerRadius: Theme.Radius.s).fill(Theme.Palette.forestRaised))
                    .overlay(RoundedRectangle(cornerRadius: Theme.Radius.s).strokeBorder(Theme.Palette.ink, lineWidth: 2))
                    .submitLabel(.send)
                    .onSubmit(send)
                if let message {
                    Text(message).font(Theme.Typography.caption).foregroundStyle(Theme.Palette.ember)
                }
                Button(action: send) {
                    Text(isSending ? "Sending…" : "Send request").frame(maxWidth: .infinity)
                }
                .buttonStyle(.pixel)
                .disabled(username.trimmingCharacters(in: .whitespaces).isEmpty || isSending)

                ShareLink(item: "Walk with me in Walkscape! My username is \(model.settings.username).") {
                    Label("Share your username", systemImage: "square.and.arrow.up").frame(maxWidth: .infinity)
                }
                .buttonStyle(.pixelQuiet)

                if model.usesSampleFriends {
                    Text("This build has no friend server configured, so requests go to sample walkers.")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Palette.creamDim)
                }
                Spacer()
            }
            .padding(Theme.Spacing.l)
            .background(Theme.Palette.night.ignoresSafeArea())
            .navigationTitle("Add a friend")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func send() {
        let name = username
        isSending = true
        Task {
            message = await model.sendFriendRequest(to: name)
            isSending = false
            if message == nil { dismiss() }
        }
    }
}
