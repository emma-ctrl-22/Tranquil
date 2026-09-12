import SwiftUI

/// One glanceable figure per module.
///
/// CLAUDE.md says the dashboard answers one question — *am I okay?* — and shows one
/// recommended action, never a to-do list. So every module appears here, but as a single
/// figure with a status colour. Only genuine problems escalate into a notice above.
struct ModuleStrip: View {
    struct Item: Identifiable {
        let id: String
        let screen: AppModel.Screen
        let label: String
        let value: String
        let detail: String
        let tone: StatTile.Tone
        let accessibleValue: String
    }

    let items: [Item]
    let onOpen: (AppModel.Screen) -> Void

    var body: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 176), spacing: Theme.Space.md)],
            spacing: Theme.Space.md
        ) {
            ForEach(items) { item in
                ModuleTile(item: item) { onOpen(item.screen) }
            }
        }
    }
}

private struct ModuleTile: View {
    @Environment(\.colorScheme) private var scheme
    let item: ModuleStrip.Item
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: Theme.Space.xs) {
                HStack(spacing: 5) {
                    Image(systemName: item.screen.icon)
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                    SectionLabel(text: item.label)
                    Spacer(minLength: 0)
                }
                Text(item.value)
                    .font(.system(size: 18, weight: .regular, design: .rounded).monospacedDigit())
                    .foregroundStyle(item.tone.color)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text(item.detail)
                    .font(Theme.Font.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Theme.Space.md)
            .background(Theme.Palette.surface(scheme))
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.large, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.large, style: .continuous)
                    .stroke(isHovering ? Theme.Palette.accent.opacity(0.5)
                                       : Theme.Palette.hairline(scheme), lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(item.label)
        .accessibilityValue("\(item.accessibleValue), \(item.detail)")
        .accessibilityAddTraits(.isButton)
    }
}
