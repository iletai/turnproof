import SwiftUI

/// Ledger Ink roles (docs/brand/DESIGN.md §2). System colors first; asset colors only where the system has no accessible role.
enum TPColor {
    static let background = Color(uiColor: .systemGroupedBackground)
    static let surface = Color(uiColor: .secondarySystemGroupedBackground)
    static let plainBackground = Color(uiColor: .systemBackground)
    static let textPrimary = Color(uiColor: .label)
    /// System `secondaryLabel` fails 4.5:1, so secondary text uses this asset color.
    static let textSecondary = Color("TextSecondary")
    static let separator = Color(uiColor: .separator)
    static let tint = Color("AccentColor")
    static let onTint = Color("OnTint")
    static let good = Color("StatusGood")
    static let fair = Color("StatusFair")
    static let damage = Color(uiColor: .systemRed)

    /// Glyph color only; status text stays in textPrimary/textSecondary.
    static func tint(for condition: Condition) -> Color {
        switch condition {
        case .good: good
        case .fair: fair
        case .damaged: damage
        }
    }
}

extension Condition {
    var title: String {
        switch self {
        case .good: String(localized: "Good")
        case .fair: String(localized: "Fair")
        case .damaged: String(localized: "Damaged")
        }
    }

    /// Shape carries the meaning so condition is never color alone.
    var symbol: String {
        switch self {
        case .good: "checkmark.circle"
        case .fair: "minus.circle"
        case .damaged: "xmark.octagon"
        }
    }
}

extension View {
    /// The one primary action of a screen: full-width capsule, Ink tint, glass on iOS 26+.
    @ViewBuilder func primaryActionStyle() -> some View {
        if #available(iOS 26, *) {
            buttonStyle(.glassProminent).buttonSizing(.flexible).controlSize(.extraLarge)
                .buttonBorderShape(.capsule).fontWeight(.semibold)
        } else {
            buttonStyle(PrimaryCapsuleStyle())
        }
    }

    /// Pins the primary action at the bottom; content scrolls under the glass bar on iOS 26+.
    @ViewBuilder func bottomActionBar<Bar: View>(@ViewBuilder _ bar: () -> Bar) -> some View {
        let content = bar().padding(.horizontal, 16).padding(.vertical, 8)
        if #available(iOS 26, *) {
            safeAreaBar(edge: .bottom) { content }
        } else {
            safeAreaInset(edge: .bottom) { content.background(.bar) }
        }
    }
}

/// Pre-iOS 26 fallback: `.borderedProminent` cannot stretch to full width from outside the label.
private struct PrimaryCapsuleStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(isEnabled ? TPColor.onTint : TPColor.textSecondary)
            .frame(maxWidth: .infinity, minHeight: 50)
            .background(Capsule().fill(isEnabled ? TPColor.tint : TPColor.separator))
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}

extension Color {
    func contrastRatio(against other: Color) -> Double {
        let l1 = Self.relativeLuminance(self)
        let l2 = Self.relativeLuminance(other)
        let lighter = max(l1, l2)
        let darker = min(l1, l2)
        return (lighter + 0.05) / (darker + 0.05)
    }

    private static func relativeLuminance(_ color: Color) -> Double {
        let ui = UIColor(color)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        ui.getRed(&r, green: &g, blue: &b, alpha: &a)
        func channel(_ value: CGFloat) -> Double {
            let v = Double(value)
            return v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(r) + 0.7152 * channel(g) + 0.0722 * channel(b)
    }
}

extension View {
    /// Liquid Glass for floating controls on iOS 26+, material before that. Never for content rows.
    @ViewBuilder func floatingControl<S: Shape>(in shape: S) -> some View {
        if #available(iOS 26, *) {
            glassEffect(.regular, in: shape)
        } else {
            background(.ultraThinMaterial, in: shape)
        }
    }
}

extension View {
    /// Section footers: system footers cap Dynamic Type and use secondaryLabel (3.4:1), so set both explicitly.
    func sectionFooterStyle() -> some View {
        font(.footnote).foregroundStyle(TPColor.textSecondary)
    }
}
