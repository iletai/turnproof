import SwiftUI

enum TPColor {
    static let paper = Color(hex: 0xF6F2EA)
    static let paperRaised = Color(hex: 0xFFFDF8)
    static let ink = Color(hex: 0x10233B)
    static let inkSecondary = Color(hex: 0x4A5A6A)
    static let inkTertiary = Color(hex: 0x5F6E7C)
    static let hairline = Color(hex: 0xDED7C9)
    static let brass = Color(hex: 0xB08A4F)
    static let brassSoft = Color(hex: 0xEFE3CF)
    static let good = Color(hex: 0x1F6F4A)
    static let goodSoft = Color(hex: 0xE4EFE8)
    static let damage = Color(hex: 0xB42318)
    static let damageSoft = Color(hex: 0xF7E7E4)
    static let warning = Color(hex: 0x9C4A06)
    static let warningSoft = Color(hex: 0xFBEFDD)

    static func tint(for condition: Condition) -> Color {
        switch condition {
        case .good: good
        case .fair: warning
        case .damaged: damage
        }
    }

    static func soft(for condition: Condition) -> Color {
        switch condition {
        case .good: goodSoft
        case .fair: warningSoft
        case .damaged: damageSoft
        }
    }
}

enum TPType {
    static func display(_ size: CGFloat = 34) -> Font { .system(size: size, weight: .medium, design: .serif) }
    static func title(_ size: CGFloat = 28) -> Font { .system(size: size, weight: .medium, design: .serif) }
    static func heading(_ size: CGFloat = 18) -> Font { .system(size: size, weight: .medium, design: .serif) }
    static func body(_ size: CGFloat = 16) -> Font { .system(size: size) }
    static func bodyStrong(_ size: CGFloat = 16) -> Font { .system(size: size, weight: .semibold) }
    static func small(_ size: CGFloat = 14) -> Font { .system(size: size) }
    static func caption(_ size: CGFloat = 12) -> Font { .system(size: size) }
    static func eyebrow() -> Font { .system(size: 11, weight: .regular, design: .monospaced) }
    static func mono(_ size: CGFloat = 12) -> Font { .system(size: size, design: .monospaced) }
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
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: 1
        )
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
