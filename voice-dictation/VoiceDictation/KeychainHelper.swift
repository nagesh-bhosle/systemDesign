//
//  KeychainHelper.swift
//  VoiceDictation
//
//  Securely stores and retrieves the API key from macOS Keychain.
//

import Foundation
import Security
import os

// Issue #37: Proper error types
enum KeychainError: LocalizedError {
    case saveFailed(OSStatus)
    case loadFailed(OSStatus)
    case deleteFailed(OSStatus)
    case dataConversionFailed

    var errorDescription: String? {
        switch self {
        case .saveFailed(let status):
            return "Failed to save API key to Keychain (status: \(status))"
        case .loadFailed(let status):
            return "Failed to load API key from Keychain (status: \(status))"
        case .deleteFailed(let status):
            return "Failed to delete API key from Keychain (status: \(status))"
        case .dataConversionFailed:
            return "Failed to convert key data."
        }
    }
}

final class KeychainHelper {
    static let shared = KeychainHelper()
    private let logger = Logger(subsystem: "com.nagesh.voicedictation", category: "Keychain")
    private let service = "com.nagesh.voicedictation"

    // Issue #43: Parameterized account name for future multi-key support
    private let defaultAccount = "routellm-api-key"
    private let historyKeyAccount = "history-aes-key"

    private init() {}

    // Issue #11: Return Result instead of ignoring OSStatus
    // Issue #12: Explicitly set kSecAttrAccessibleWhenUnlocked
    func saveAPIKey(_ key: String, account: String? = nil) -> Result<Void, KeychainError> {
        let accountName = account ?? defaultAccount
        let data = Data(key.utf8)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: accountName
        ]

        // Delete existing
        SecItemDelete(query as CFDictionary)

        // Add new with explicit accessibility
        var addQuery = query
        addQuery[kSecValueData as String] = data
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlocked

        let status = SecItemAdd(addQuery as CFDictionary, nil)
        guard status == errSecSuccess else {
            logger.error("Keychain save failed: \(status)")
            return .failure(.saveFailed(status))
        }
        logger.info("API key saved to Keychain")
        return .success(())
    }

    func loadAPIKey(account: String? = nil) -> String? {
        let accountName = account ?? defaultAccount
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: accountName,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess, let data = result as? Data else {
            if status != errSecItemNotFound {
                logger.warning("Keychain load failed: \(status)")
            }
            return nil
        }

        return String(data: data, encoding: .utf8)
    }

    // Issue #11: Return Result instead of ignoring OSStatus
    func deleteAPIKey(account: String? = nil) -> Result<Void, KeychainError> {
        let accountName = account ?? defaultAccount
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: accountName
        ]
        let status = SecItemDelete(query as CFDictionary)
        // errSecItemNotFound is not an error when deleting
        guard status == errSecSuccess || status == errSecItemNotFound else {
            logger.error("Keychain delete failed: \(status)")
            return .failure(.deleteFailed(status))
        }
        logger.info("API key deleted from Keychain")
        return .success(())
    }

    // MARK: - History encryption key

    func loadOrCreateHistoryKey() -> Data? {
        if let existing = loadHistoryKey() {
            return existing
        }
        var key = Data(count: 32)
        let result = key.withUnsafeMutableBytes { buffer in
            guard let base = buffer.baseAddress else { return errSecParam }
            return SecRandomCopyBytes(kSecRandomDefault, 32, base)
        }
        guard result == errSecSuccess else {
            logger.error("Failed to generate history encryption key")
            return nil
        }
        switch saveHistoryKey(key) {
        case .success:
            return key
        case .failure:
            return nil
        }
    }

    func loadHistoryKey() -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: historyKeyAccount,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data, data.count == 32 else {
            return nil
        }
        return data
    }

    func saveHistoryKey(_ key: Data) -> Result<Void, KeychainError> {
        guard key.count == 32 else { return .failure(.dataConversionFailed) }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: historyKeyAccount
        ]
        SecItemDelete(query as CFDictionary)

        var addQuery = query
        addQuery[kSecValueData as String] = key
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlocked

        let status = SecItemAdd(addQuery as CFDictionary, nil)
        guard status == errSecSuccess else {
            return .failure(.saveFailed(status))
        }
        return .success(())
    }
}