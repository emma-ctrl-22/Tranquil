import SwiftUI

/// The design tokens. Every colour, radius and spacing value in the app comes from here
/// so light and dark stay consistent and nothing is tuned ad hoc in a view.
enum Theme {

    // MARK: - Colour

    /// Calm, desaturated surfaces. This app is opened when money is stressful;
    /// it should not add to that.
    enum Palette {
        static let accent = Color(hex: "#4F8A7B")        // sage
        static let accentSoft = Color(hex: "#4F8A7B").opacity(0.14)

        static let positive = Color(hex: "#4F8A7B")
        static let negative = Color(hex: "#B05C4F")
        static let caution = Color(hex: "#B08A4F")
        static let neutral = Color.secondary

        static func surface(_ scheme: ColorScheme) -> Color {
            scheme == .dark ? Color(hex: "#1C1F22") : Color(hex: "#FFFFFF")
        }
        static func canvas(_ scheme: ColorScheme) -> Color {
            scheme == .dark ? Color(hex: "#141618") : Color(hex: "#F4F5F3")
        }
        static func hairline(_ scheme: ColorScheme) -> Color {
            scheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.07)
        }
        static func raised(_ scheme: ColorScheme) -> Color {
            scheme == .dark ? Color.white.opacity(0.04) : Color.black.opacity(0.03)
        }

        /// Account colours come from the model as hex.
        static func account(_ hex: String) -> Color { Color(hex: hex) }
    }

    // MARK: - Metrics

    enum Radius {
        static let small: CGFloat = 6
        static let medium: CGFloat = 10
        static let large: CGFloat = 14
    }

    enum Space {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 14
        static let lg: CGFloat = 20
        static let xl: CGFloat = 28
    }

    // MARK: - Type

    enum Font {
        /// The one big number on a screen.
        static let hero = SwiftUI.Font.system(size: 40, weight: .light, design: .rounded)
            .monospacedDigit()
        static let figure = SwiftUI.Font.system(size: 22, weight: .regular, design: .rounded)
            .monospacedDigit()
        static let amount = SwiftUI.Font.system(size: 13, weight: .regular).monospacedDigit()
        static let title = SwiftUI.Font.system(size: 15, weight: .semibold)
        static let label = SwiftUI.Font.system(size: 11, weight: .medium)
        static let caption = SwiftUI.Font.system(size: 11)
    }
}

extension Color {
    /// `#RRGGBB`. Falls back to grey rather than crashing on bad input — a colour is
    /// never worth a `fatalError` on a path the user can reach.
    init(hex: String) {
        let cleaned = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        guard cleaned.count == 6, let value = UInt32(cleaned, radix: 16) else {
            self = .gray
            return
        }
        self.init(
            .sRGB,
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255,
            opacity: 1
        )
    }
}
