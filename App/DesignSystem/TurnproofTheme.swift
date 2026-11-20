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

    // v1 aliases, removed once every screen is on the v2 roles.
    static let paper = background
    static let paperRaised = surface
    static let ink = textPrimary
    static let inkSecondary = textSecondary
    static let inkTertiary = textSecondary
    static let hairline = separator
    static let brass = tint
    static let brassSoft = tint.opacity(0.12)
    static let warning = fair
    static let goodSoft = good.opacity(0.12)
    static let damageSoft = damage.opacity(0.12)
    static let warningSoft = fair.opacity(0.12)
    static func soft(for condition: Condition) -> Color { tint(for: condition).opacity(0.12) }
}

extension Condition {
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
        let base = frame(maxWidth: .infinity, minHeight: 34).fontWeight(.semibold)
        if #available(iOS 26, *) {
            base.buttonStyle(.glassProminent).controlSize(.large).buttonBorderShape(.capsule)
        } else {
            base.buttonStyle(.borderedProminent).controlSize(.large).buttonBorderShape(.capsule)
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

/// Point sizes pick the nearest text style so every font scales with Dynamic Type.
enum TPType {
    private static func style(_ size: CGFloat) -> Font.TextStyle {
        switch size {
        case ...11: .caption2
        case ...12: .caption
        case ...13: .footnote
        case ...15: .subheadline
        case ...17: .body
        case ...20: .title3
        case ...24: .title2
        case ...28: .title
        default: .largeTitle
        }
    }

    static func display(_ size: CGFloat = 34) -> Font { .system(style(size), design: .serif, weight: .medium) }
    static func title(_ size: CGFloat = 28) -> Font { .system(style(size), design: .serif, weight: .medium) }
    static func heading(_ size: CGFloat = 18) -> Font { .system(style(size), design: .serif, weight: .medium) }
    static func body(_ size: CGFloat = 16) -> Font { .system(style(size)) }
    static func bodyStrong(_ size: CGFloat = 16) -> Font { .system(style(size), weight: .semibold) }
    static func small(_ size: CGFloat = 14) -> Font { .system(style(size)) }
    static func caption(_ size: CGFloat = 12) -> Font { .system(style(size)) }
    static func eyebrow() -> Font { Font.caption.monospaced() }
    static func mono(_ size: CGFloat = 12) -> Font { Font.system(style(size)).monospaced() }
}

enum TPSpacing {
    static let unit: CGFloat = 4
    static let gutter: CGFloat = 20
    static let section: CGFloat = 32
    static let card: CGFloat = 16
}

struct TPCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(TPSpacing.card)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(TPColor.paperRaised)
            .overlay(Rectangle().stroke(TPColor.hairline, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 4))
    }
}

struct TPPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(TPType.bodyStrong())
            .foregroundStyle(TPColor.paperRaised)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(isEnabled ? TPColor.ink : TPColor.inkTertiary.opacity(0.4))
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .opacity(configuration.isPressed ? 0.82 : 1)
    }
}

struct TPSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(TPType.bodyStrong())
            .foregroundStyle(TPColor.ink)
            .frame(maxWidth: .infinity, minHeight: 52)
            .overlay(Rectangle().stroke(TPColor.ink, lineWidth: 1))
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

struct Eyebrow: View {
    let text: String

    var body: some View {
        Text(text.uppercased())
            .font(TPType.eyebrow())
            .tracking(1.6)
            .foregroundStyle(TPColor.inkTertiary)
    }
}

struct StatusChip: View {
    let text: String
    let color: Color
    let background: Color

    var body: some View {
        Text(text.uppercased())
            .font(TPType.eyebrow())
            .tracking(0.8)
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(background)
            .overlay(Rectangle().stroke(color.opacity(0.25), lineWidth: 1))
    }
}

struct ConditionChip: View {
    let condition: Condition
    var isSelected = false

    var body: some View {
        Text(condition.rawValue.capitalized)
            .font(TPType.eyebrow())
            .tracking(0.8)
            .foregroundStyle(isSelected ? TPColor.tint(for: condition) : TPColor.inkSecondary)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(isSelected ? TPColor.soft(for: condition) : TPColor.paperRaised)
            .accessibilityIdentifier("capture.condition.\(condition.rawValue)")
            .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

struct Hairline: View {
    var body: some View { Rectangle().fill(TPColor.hairline).frame(height: 1) }
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
