import Foundation
import Testing
@testable import Turnproof

final class FakeKeychain: KeychainStoring, @unchecked Sendable {
    private var storage: [String: Data] = [:]

    func read(_ key: String) -> Data? { storage[key] }
    func write(_ data: Data?, _ key: String) {
        if let data { storage[key] = data } else { storage.removeValue(forKey: key) }
    }
}

struct FreeReportCounterTests {
    @Test func freshInstallAllowsOneExport() {
        let counter = FreeReportCounter(keychain: FakeKeychain())
        #expect(counter.count() == 0)
        #expect(ExportGate.allowsExport(isPro: false, counter: counter))
    }

    @Test func secondExportIsDeniedWithoutPro() {
        let counter = FreeReportCounter(keychain: FakeKeychain())
        ExportGate.recordExport(counter: counter)
        #expect(counter.count() == 1)
        #expect(!ExportGate.allowsExport(isPro: false, counter: counter))
    }

    @Test func proUserIsAlwaysAllowed() {
        let counter = FreeReportCounter(keychain: FakeKeychain())
        for _ in 0..<5 { counter.increment() }
        #expect(ExportGate.allowsExport(isPro: true, counter: counter))
    }

    @Test func proExportDoesNotConsumeTheFreeSlot() {
        let counter = FreeReportCounter(keychain: FakeKeychain())
        ExportGate.recordExport(counter: counter, isPro: true)
        #expect(counter.count() == 0)
        #expect(ExportGate.allowsExport(isPro: false, counter: counter))
    }

    @Test func reinstallKeepsTheSpentSlot() {
        let keychain = FakeKeychain()
        let first = FreeReportCounter(keychain: keychain)
        ExportGate.recordExport(counter: first)

        let afterReinstall = FreeReportCounter(keychain: keychain)
        #expect(afterReinstall.count() == 1)
        #expect(!ExportGate.allowsExport(isPro: false, counter: afterReinstall))
    }

    @Test func corruptStoredValueCountsAsNoExports() {
        let keychain = FakeKeychain()
        keychain.write(Data("not-a-number".utf8), FreeReportCounter.key)
        let counter = FreeReportCounter(keychain: keychain)
        #expect(counter.count() == 0)
    }
}
