import SwiftUI
import Testing
@testable import Turnproof

struct ThemeContrastTests {
    @Test func conditionChipsMeetContrast() {
        for condition in Condition.allCases {
            let ratio = TPColor.tint(for: condition).contrastRatio(against: TPColor.soft(for: condition))
            #expect(ratio >= 4.5, "\(condition) chip reads at \(ratio)")
        }
    }

    @Test func bodyTextMeetsContrastOnPaper() {
        #expect(TPColor.ink.contrastRatio(against: TPColor.paper) >= 7)
        #expect(TPColor.inkSecondary.contrastRatio(against: TPColor.paper) >= 4.5)
        #expect(TPColor.inkTertiary.contrastRatio(against: TPColor.paper) >= 4.5)
    }

    @Test func statusChipsMeetContrast() {
        #expect(TPColor.good.contrastRatio(against: TPColor.goodSoft) >= 4.5)
        #expect(TPColor.damage.contrastRatio(against: TPColor.damageSoft) >= 4.5)
        #expect(TPColor.warning.contrastRatio(against: TPColor.warningSoft) >= 4.5)
        #expect(TPColor.inkSecondary.contrastRatio(against: TPColor.paper) >= 4.5)
    }

    @Test func primaryButtonIsReadable() {
        #expect(TPColor.paperRaised.contrastRatio(against: TPColor.ink) >= 7)
    }
}
