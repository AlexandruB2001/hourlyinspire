import SwiftUI
import WalkscapeDomain

extension GuideSection.ID: Identifiable {
    var id: String { rawValue }
}

/// The "?" button on the Journey scene.
struct GuideButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text("?")
                .font(.system(size: 17, weight: .heavy, design: .rounded))
                .foregroundStyle(Theme.Palette.ink)
                .frame(width: 32, height: 32)
                .background(RoundedRectangle(cornerRadius: Theme.Radius.s).fill(Theme.Palette.gold))
                .overlay(RoundedRectangle(cornerRadius: Theme.Radius.s).strokeBorder(Theme.Palette.ink, lineWidth: 2))
                .shadow(color: Theme.Palette.ink, radius: 0, x: 0, y: 2)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Walkscape Guide")
        .accessibilityHint("Explains how the game works")
    }
}

/// How Walkscape works, section by section. Opens at `start` when given.
struct GuideView: View {
    @Environment(\.dismiss) private var dismiss
    var start: GuideSection.ID = .journey
    private let sections = GuideContent.sections()

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                        Text("Everything you need to know to walk the world.")
                            .font(Theme.Typography.caption)
                            .foregroundStyle(Theme.Palette.creamDim)
                        topics(proxy)
                        ForEach(sections) { section in
                            GuideSectionCard(section: section).id(section.id)
                        }
                    }
                    .padding(Theme.Spacing.l)
                }
                .onAppear {
                    guard start != .journey else { return }
                    DispatchQueue.main.async { proxy.scrollTo(start, anchor: .top) }
                }
            }
            .background(Theme.Palette.night.ignoresSafeArea())
            .navigationTitle("Walkscape Guide")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Theme.Palette.night, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() }.foregroundStyle(Theme.Palette.gold) }
            }
        }
        .presentationDragIndicator(.visible)
    }

    /// Jump links to each section.
    private func topics(_ proxy: ScrollViewProxy) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: Theme.Spacing.s)], spacing: Theme.Spacing.s) {
            ForEach(sections) { section in
                Button {
                    withAnimation { proxy.scrollTo(section.id, anchor: .top) }
                } label: {
                    HStack(spacing: Theme.Spacing.s) {
                        ItemIcon(spriteID: section.spriteID, pixel: 2)
                        Text(section.title)
                            .font(Theme.Typography.caption)
                            .foregroundStyle(Theme.Palette.cream)
                            .multilineTextAlignment(.leading)
                        Spacer(minLength: 0)
                    }
                    .padding(Theme.Spacing.s)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: Theme.Radius.s).fill(Theme.Palette.forestRaised))
                    .overlay(RoundedRectangle(cornerRadius: Theme.Radius.s).strokeBorder(Theme.Palette.ink, lineWidth: 2))
                }
                .buttonStyle(.plain)
                .accessibilityHint("Jumps to this section")
            }
        }
    }
}

private struct GuideSectionCard: View {
    let section: GuideSection

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            HStack(spacing: Theme.Spacing.m) {
                ItemIcon(spriteID: section.spriteID, pixel: 4)
                Text(section.title)
                    .font(Theme.Typography.title)
                    .foregroundStyle(Theme.Palette.cream)
                    .accessibilityAddTraits(.isHeader)
            }
            ForEach(section.entries, id: \.title) { entry in
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    Eyebrow(entry.title, color: Theme.Palette.gold)
                    Text(entry.body)
                        .font(Theme.Typography.body)
                        .foregroundStyle(Theme.Palette.cream.opacity(0.9))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .pixelPanel()
    }
}
