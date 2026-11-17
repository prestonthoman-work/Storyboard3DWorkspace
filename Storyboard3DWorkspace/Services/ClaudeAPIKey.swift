//
//  ClaudeAPIKey.swift
//  Storyboard3DWorkspace
//

import Foundation
import Security

/// The Anthropic API key used to generate objects with Claude, kept in the Keychain on this
/// device. When running from Xcode, an `ANTHROPIC_API_KEY` environment variable in the
/// scheme is used if no key has been saved.
enum ClaudeAPIKey {
    private static let service = "Storyboard3DWorkspace.ClaudeAPIKey"
    private static let account = "anthropic"

    /// The saved key, or the scheme's environment variable, or nil.
    static var current: String? {
        if let saved = saved { return saved }
        let environment = ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return environment?.isEmpty == false ? environment : nil
    }

    static var saved: String? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data, let key = String(data: data, encoding: .utf8), !key.isEmpty
        else { return nil }
        return key
    }

    /// Saves the key, replacing any saved one. Returns false if the Keychain refused it.
    @discardableResult
    static func save(_ key: String) -> Bool {
        let key = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return false }
        remove()
        var item = baseQuery
        item[kSecValueData as String] = Data(key.utf8)
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        return SecItemAdd(item as CFDictionary, nil) == errSecSuccess
    }

    static func remove() {
        SecItemDelete(baseQuery as CFDictionary)
    }

    private static var baseQuery: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }
}
