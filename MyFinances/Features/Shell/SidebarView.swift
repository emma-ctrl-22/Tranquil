import SwiftUI

struct SidebarView: View {
    @Environment(\.colorScheme) private var scheme
    @Binding var model: AppModel
    let formatter: MoneyFormatter
    let totals: BalanceEngine.Totals

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().opacity(0.5)
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.lg) {
                    group("Daily", [.dashboard, .ledger, .accounts])
                    group("Forward", [.plan, .debt, .goals])
                    group("Standing back", [.ladder, .review, .income, .advisor, .insights])
                }
                .padding(.vertical, Theme.Space.md)
            }
            Spacer(minLength: 0)
        }
        .background(.ultraThinMaterial)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Available")
                .font(Theme.Font.label)
                .tracking(0.6)
                .foregroundStyle(.secondary)
            Text(formatter.string(totals.liquidAvailable))
                .font(Theme.Font.figure)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            if !totals.earmarkedTotal.isZero {
                Text("\(formatter.string(totals.earmarkedTotal)) earmarked")
                    .font(Theme.Font.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.Space.md)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Available to spend")
        .accessibilityValue(formatter.accessibleString(totals.liquidAvailable))
    }

    private func group(_ title: String, _ screens: [AppModel.Screen]) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            SectionLabel(text: title)
                .padding(.horizontal, Theme.Space.md)
                .padding(.bottom, Theme.Space.xs)
            ForEach(screens) { screen in
                SidebarRow(
                    screen: screen,
                    isSelected: model.screen == screen,
                    action: { model.open(screen) }
                )
            }
        }
    }
}

private struct SidebarRow: View {
    @Environment(\.colorScheme) private var scheme
    let screen: AppModel.Screen
    let isSelected: Bool
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: Theme.Space.sm) {
                Image(systemName: screen.icon)
                    .font(.system(size: 12))
                    .frame(width: 16)
                Text(screen.title).font(.system(size: 12.5))
                Spacer(minLength: 0)
                if !screen.isAvailable {
                    Text("soon")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.tertiary)
                }
            }
            .foregroundStyle(foreground)
            .padding(.horizontal, Theme.Space.sm)
            .padding(.vertical, 5)
            .background(background)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, Theme.Space.sm)
        .onHover { isHovering = $0 }
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
    }

    private var foreground: Color {
        if isSelected { return Theme.Palette.accent }
        return screen.isAvailable ? .primary : .secondary
    }

    private var background: Color {
        if isSelected { return Theme.Palette.accentSoft }
        return isHovering && screen.isAvailable ? Theme.Palette.raised(scheme) : .clear
    }
}
