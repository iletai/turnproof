import SwiftUI
import Testing
@testable import Turnproof

struct ThemeContrastTests {
    private func resolved(_ color: Color, _ style: UIUserInterfaceStyle) -> Color {
        Color(uiColor: UIColor(color).resolvedColor(with: UITraitCollection(userInterfaceStyle: style)))
    }

    @Test(arguments: [UIUserInterfaceStyle.light, .dark])
    func secondaryTextMeetsContrastOnSurface(style: UIUserInterfaceStyle) {
        let ratio = resolved(TPColor.textSecondary, style).contrastRatio(against: resolved(TPColor.surface, style))
        #expect(ratio >= 4.5, "\(style.rawValue) reads at \(ratio)")
    }

    @Test(arguments: [UIUserInterfaceStyle.light, .dark])
    func inkTintMeetsContrastOnSurface(style: UIUserInterfaceStyle) {
        let ratio = resolved(TPColor.tint, style).contrastRatio(against: resolved(TPColor.surface, style))
        #expect(ratio >= 7, "\(style.rawValue) reads at \(ratio)")
    }

    @Test(arguments: [UIUserInterfaceStyle.light, .dark])
    func primaryButtonLabelIsReadable(style: UIUserInterfaceStyle) {
        let ratio = resolved(TPColor.onTint, style).contrastRatio(against: resolved(TPColor.tint, style))
        #expect(ratio >= 7, "\(style.rawValue) reads at \(ratio)")
    }

    @Test(arguments: Condition.allCases)
    func conditionGlyphsMeetNonTextContrast(condition: Condition) {
        #expect(resolved(TPColor.tint(for: condition), .light).contrastRatio(against: .white) >= 3)
    }
}
