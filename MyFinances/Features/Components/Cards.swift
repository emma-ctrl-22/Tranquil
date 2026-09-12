import SwiftUI

/// A raised surface. The one container used across every screen.
struct Card<Content: View>: View {
    @Environment(\.colorScheme) private var scheme
    var padding: CGFloat = Theme.Space.md
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.Palette.surface(scheme))
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.large, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.large, style: .continuous)
                    .stroke(Theme.Palette.hairline(scheme), lineWidth: 1)
            )
    }
}

/// A small all-caps section label.
struct SectionLabel: View {
    let text: String

    var body: some View {
        Text(text.uppercased())
            .font(Theme.Font.label)
            .tracking(0.6)
            .foregroundStyle(.secondary)
    }
}

/// One figure with its name. The building block of the dashboard.
struct StatTile: View {
    let label: String
    let value: String
    var detail: String?
    var tone: Tone = .neutral
    var accessibilityValue: String?

    enum Tone {
        case neutral, positive, negative, caution

        var color: Color {
            switch self {
            case .neutral: .primary
            case .positive: Theme.Palette.positive
            case .negative: Theme.Palette.negative
            case .caution: Theme.Palette.caution
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            SectionLabel(text: label)
            Text(value)
                .font(Theme.Font.figure)
                .foregroundStyle(tone.color)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            if let detail {
                Text(detail)
                    .font(Theme.Font.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue((accessibilityValue ?? value) + (detail.map { ", \($0)" } ?? ""))
    }
}

/// A compact status chip.
struct Pill: View {
    let text: String
    var tone: StatTile.Tone = .neutral
    var icon: String?

    var body: some View {
        HStack(spacing: 4) {
            if let icon { Image(systemName: icon).font(.system(size: 9, weight: .semibold)) }
            Text(text).font(Theme.Font.label)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .foregroundStyle(tone.color)
        .background(tone.color.opacity(0.12))
        .clipShape(Capsule())
    }
}

/// A horizontal progress track. Used for envelopes, goals and funds.
struct MeterBar: View {
    @Environment(\.colorScheme) private var scheme
    /// 0...1 of the track filled.
    let fraction: Double
    /// Optional marker showing where the pace *should* be.
    var expected: Double?
    var tone: StatTile.Tone = .neutral
    var height: CGFloat = 6

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.Palette.raised(scheme))
                Capsule()
                    .fill(tone.color)
                    .frame(width: geometry.size.width * fraction.clamped(to: 0...1))
                if let expected {
                    Rectangle()
                        .fill(Color.primary.opacity(0.35))
                        .frame(width: 1.5)
                        .offset(x: geometry.size.width * expected.clamped(to: 0...1))
                }
            }
        }
        .frame(height: height)
    }
}

/// An empty state that says what to do, not just that there is nothing here.
struct EmptyStateView: View {
    let icon: String
    let title: String
    let message: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: Theme.Space.sm) {
            Image(systemName: icon)
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(.tertiary)
            Text(title).font(Theme.Font.title)
            Text(message)
                .font(Theme.Font.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .padding(.top, Theme.Space.xs)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Theme.Space.xl)
    }
}

extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}
