import SwiftUI
import Security

struct Panel: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var url: String
    var username: String

    /// بدون http/https: نستخدم http إذا كان في الرابط منفذ غير 443 (مثل :2082)، وإلا https
    var normalizedURL: URL? {
        var s = url.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = s.lowercased()
        if !lower.hasPrefix("http://") && !lower.hasPrefix("https://") {
            let hostPart = s.split(separator: "/", maxSplits: 1).first.map(String.init) ?? s
            let port = hostPart.split(separator: ":").dropFirst().first.map(String.init)
            let plain = port != nil && port != "443" && port != "2083" && port != "8443"
            s = (plain ? "http://" : "https://") + s
        }
        return URL(string: s)
    }

    var hasExplicitScheme: Bool {
        let lower = url.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return lower.hasPrefix("http://") || lower.hasPrefix("https://")
    }

    var host: String { normalizedURL?.host ?? url }
}

final class PanelStore: ObservableObject {
    @Published var panels: [Panel] = [] {
        didSet { save() }
    }
    private let key = "panels.v1"

    init() {
        if let data = UserDefaults.standard.data(forKey: key),
           let list = try? JSONDecoder().decode([Panel].self, from: data) {
            panels = list
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(panels) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    func panel(_ id: UUID?) -> Panel? {
        guard let id = id else { return nil }
        return panels.first { $0.id == id }
    }

    func upsert(_ panel: Panel, password: String) {
        Keychain.set(password, for: panel.id.uuidString)
        if let i = panels.firstIndex(where: { $0.id == panel.id }) {
            panels[i] = panel
        } else {
            panels.append(panel)
        }
        WebViewPool.shared.reset(panel.id)
    }

    func delete(_ panel: Panel) {
        Keychain.set("", for: panel.id.uuidString)
        WebViewPool.shared.reset(panel.id)
        panels.removeAll { $0.id == panel.id }
    }

    func move(from source: IndexSet, to destination: Int) {
        panels.move(fromOffsets: source, toOffset: destination)
    }
}

enum Keychain {
    private static let service = "com.salha.serverbrowser"

    private static func query(_ key: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: key]
    }

    static func set(_ value: String, for key: String) {
        SecItemDelete(query(key) as CFDictionary)
        guard !value.isEmpty else { return }
        var add = query(key)
        add[kSecValueData as String] = Data(value.utf8)
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(add as CFDictionary, nil)
    }

    static func get(_ key: String) -> String {
        var q = query(key)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess,
              let data = out as? Data,
              let s = String(data: data, encoding: .utf8) else { return "" }
        return s
    }
}
