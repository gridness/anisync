import Foundation
import Security

final class AniSyncStateStore: @unchecked Sendable {
    private let lock = NSLock()
    private let defaults: UserDefaults
    private let key = "anisync.state.v1"
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(defaults: UserDefaults? = UserDefaults(suiteName: AniSyncConstants.appGroup)) {
        self.defaults = defaults ?? .standard
        encoder = JSONEncoder()
        decoder = JSONDecoder()
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    func read() -> StoredState {
        lock.withLock {
            defaults.synchronize()
            guard let data = defaults.data(forKey: key),
                  var state = try? decoder.decode(StoredState.self, from: data) else {
                return .empty
            }
            state.removeExpiredActivity()
            return state
        }
    }

    func write(_ state: StoredState) {
        lock.withLock {
            var state = state
            state.removeExpiredActivity()
            guard let data = try? encoder.encode(state) else { return }
            defaults.set(data, forKey: key)
            defaults.synchronize()
        }
    }

    @discardableResult
    func update<T>(_ body: (inout StoredState) throws -> T) rethrows -> T {
        try lock.withLock {
            defaults.synchronize()
            var state: StoredState
            if let data = defaults.data(forKey: key), let decoded = try? decoder.decode(StoredState.self, from: data) {
                state = decoded
            } else {
                state = .empty
            }
            state.removeExpiredActivity()
            let value = try body(&state)
            if let data = try? encoder.encode(state) {
                defaults.set(data, forKey: key)
                defaults.synchronize()
            }
            return value
        }
    }
}

protocol AniListTokenStoring: Sendable {
    func read() -> String?
    func save(_ token: String) throws
    func delete()
}

final class AniListTokenStore: AniListTokenStoring, @unchecked Sendable {
    private let lock = NSLock()

    func read() -> String? {
        lock.withLock {
            var query = baseQuery
            query[kSecReturnData as String] = true
            query[kSecMatchLimit as String] = kSecMatchLimitOne
            var result: CFTypeRef?
            var status = SecItemCopyMatching(query as CFDictionary, &result)

            if status == errSecMissingEntitlement {
                query.removeValue(forKey: kSecAttrAccessGroup as String)
                status = SecItemCopyMatching(query as CFDictionary, &result)
            }

            guard status == errSecSuccess,
                  let data = result as? Data else { return nil }
            return String(data: data, encoding: .utf8)
        }
    }

    func save(_ token: String) throws {
        try lock.withLock {
            guard let data = token.data(using: .utf8) else {
                throw AniSyncError.api("The authorization token could not be stored.")
            }
            var query = baseQuery
            let attributes: [String: Any] = [kSecValueData as String: data]
            var status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
            if status == errSecItemNotFound {
                query[kSecValueData as String] = data
                status = SecItemAdd(query as CFDictionary, nil)
            }
            if status == errSecMissingEntitlement {
                query.removeValue(forKey: kSecAttrAccessGroup as String)
                SecItemDelete(query as CFDictionary)
                query[kSecValueData as String] = data
                status = SecItemAdd(query as CFDictionary, nil)
            }
            guard status == errSecSuccess else {
                throw AniSyncError.api("Keychain returned error \(status).")
            }
        }
    }

    func delete() {
        lock.withLock {
            var query = baseQuery
            let status = SecItemDelete(query as CFDictionary)
            if status == errSecMissingEntitlement {
                query.removeValue(forKey: kSecAttrAccessGroup as String)
                SecItemDelete(query as CFDictionary)
            }
        }
    }

    private var baseQuery: [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: AniSyncConstants.keychainService,
            kSecAttrAccount as String: AniSyncConstants.keychainAccount
        ]
        if let accessGroup = Bundle.main.object(forInfoDictionaryKey: "AniSyncKeychainAccessGroup") as? String,
           !accessGroup.isEmpty,
           !accessGroup.contains("$(") {
            query[kSecAttrAccessGroup as String] = accessGroup
        }
        return query
    }
}

enum NativeMessageCodec {
    static func dictionary<T: Encodable>(_ value: T) -> [String: Any] {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(value),
              let object = try? JSONSerialization.jsonObject(with: data),
              let dictionary = object as? [String: Any] else { return [:] }
        return dictionary
    }
}
