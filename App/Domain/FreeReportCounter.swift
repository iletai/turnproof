import Foundation
import Security

protocol KeychainStoring: Sendable {
    func read(_ key: String) -> Data?
    func write(_ data: Data?, _ key: String)
}

struct KeychainStore: KeychainStoring {
    let service: String

    func read(_ key: String) -> Data? {
        var query = baseQuery(key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess else { return nil }
        return result as? Data
    }

    func write(_ data: Data?, _ key: String) {
        let query = baseQuery(key)
        if let data {
            let attributes: [String: Any] = [kSecValueData as String: data]
            if SecItemUpdate(query as CFDictionary, attributes as CFDictionary) == errSecItemNotFound {
                var insert = query
                insert[kSecValueData as String] = data
                insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
                SecItemAdd(insert as CFDictionary, nil)
            }
        } else {
            SecItemDelete(query as CFDictionary)
        }
    }

    private func baseQuery(_ key: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
    }
}

/// The single free report allowance. Keychain, not UserDefaults: deleting the app must not reset it.
struct FreeReportCounter: Sendable {
    static let key = "turnproof.free_reports.v1"
    static let freeAllowance = 1

    let keychain: KeychainStoring

    init(keychain: KeychainStoring = KeychainStore(service: "com.iletai.turnproof.allowance")) {
        self.keychain = keychain
    }

    func count() -> Int {
        guard let data = keychain.read(Self.key), let string = String(data: data, encoding: .utf8) else { return 0 }
        return Int(string) ?? 0
    }

    func increment() {
        let next = count() + 1
        keychain.write(Data(String(next).utf8), Self.key)
    }

    func reset() {
        keychain.write(nil, Self.key)
    }
}

enum ExportGate {
    static func allowsExport(isPro: Bool, counter: FreeReportCounter) -> Bool {
        isPro || counter.count() < FreeReportCounter.freeAllowance
    }

    static func recordExport(counter: FreeReportCounter, isPro: Bool = false) {
        // Only a free slot is consumed; a subscriber's downgrade must not find the slot spent.
        guard !isPro else { return }
        counter.increment()
    }
}
