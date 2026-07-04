// AIKeychain.swift
// ----------------
// LƯU API KEY của trợ lý AI trong macOS Keychain — KHÔNG để trong settings.json.
//
// Vì sao Keychain, không phải settings.json? File cài đặt được app export/backup
// và nằm dạng plaintext trong Application Support; nhét API key vào đó là rò rỉ
// khoá bí mật. Keychain mã hoá theo phiên đăng nhập, đúng chuẩn lưu secret.
//
// Mỗi hãng một key riêng (account = provider.rawValue), cùng một service.
// Giao diện gọn: read / write / delete. Đọc/ghi từ Keychain đồng bộ, nhanh.

import Foundation
import Security
import VietEngine

enum AIKeychain {

    /// Service dùng chung cho mọi key AI của app.
    private static let service = "com.bowgo.ai"

    /// Đọc API key của một hãng. Trả nil nếu chưa lưu.
    static func read(_ provider: AIProvider) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: provider.rawValue,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess,
              let data = result as? Data,
              let key = String(data: data, encoding: .utf8) else {
            return nil
        }
        return key
    }

    /// Ghi (hoặc cập nhật) API key cho một hãng. Chuỗi rỗng -> xoá key.
    @discardableResult
    static func write(_ key: String, for provider: AIProvider) -> Bool {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return delete(provider) }
        guard let data = trimmed.data(using: .utf8) else { return false }

        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: provider.rawValue,
        ]

        // Đã có -> cập nhật; chưa có -> thêm mới.
        let update: [String: Any] = [kSecValueData as String: data]
        let status = SecItemUpdate(base as CFDictionary, update as CFDictionary)
        if status == errSecSuccess { return true }
        if status == errSecItemNotFound {
            var add = base
            add[kSecValueData as String] = data
            // Chỉ mở khoá được sau lần đăng nhập đầu (an toàn, dùng nền được).
            add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            return SecItemAdd(add as CFDictionary, nil) == errSecSuccess
        }
        return false
    }

    /// Xoá API key của một hãng.
    @discardableResult
    static func delete(_ provider: AIProvider) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: provider.rawValue,
        ]
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }

    /// Có key nào cho hãng này chưa (để UI/menu biết đã cấu hình chưa).
    static func hasKey(_ provider: AIProvider) -> Bool {
        guard let k = read(provider) else { return false }
        return !k.isEmpty
    }
}
