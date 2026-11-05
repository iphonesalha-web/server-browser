import WebKit

/// يحفظ الكوكيز في ملف داخل التطبيق ويحوّل كوكيز الجلسة المؤقتة إلى دائمة،
/// حتى يبقى تسجيل الدخول بعد إغلاق التطبيق.
struct StoredCookie: Codable {
    var name: String
    var value: String
    var domain: String
    var path: String
    var expires: Date?
    var secure: Bool
    var httpOnly: Bool
    var sameSite: String?
}

final class CookieVault: NSObject, WKHTTPCookieStoreObserver {
    static let shared = CookieVault()

    private let lifetime: TimeInterval = 60 * 60 * 24 * 30   // 30 يوماً
    private var restored = false
    private var restoring = false
    private var waiting: [() -> Void] = []

    private var store: WKHTTPCookieStore { WKWebsiteDataStore.default().httpCookieStore }

    private var fileURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("cookies.json")
    }

    /// يعيد الكوكيز المحفوظة قبل أول تحميل، ثم ينفّذ `done`.
    func restore(_ done: @escaping () -> Void) {
        if restored { done(); return }
        waiting.append(done)
        if restoring { return }
        restoring = true
        store.add(self)

        let now = Date()
        let saved = load().filter { ($0.expires ?? .distantFuture) > now }
        let group = DispatchGroup()
        for c in saved {
            guard let cookie = makeCookie(c) else { continue }
            group.enter()
            store.setCookie(cookie) { group.leave() }
        }
        group.notify(queue: .main) {
            self.restored = true
            self.restoring = false
            let w = self.waiting
            self.waiting = []
            w.forEach { $0() }
        }
    }

    func cookiesDidChange(in cookieStore: WKHTTPCookieStore) {
        guard restored else { return }
        snapshot(cookieStore)
    }

    func snapshot(_ cookieStore: WKHTTPCookieStore? = nil) {
        let cs = cookieStore ?? store
        cs.getAllCookies { cookies in
            for c in cookies where c.expiresDate == nil {
                if let persistent = self.makeCookie(self.stored(c)) {
                    cs.setCookie(persistent)
                }
            }
            self.save(cookies.map { self.stored($0) })
        }
    }

    func clearAll() {
        try? FileManager.default.removeItem(at: fileURL)
        let types = WKWebsiteDataStore.allWebsiteDataTypes()
        WKWebsiteDataStore.default().removeData(ofTypes: types, modifiedSince: .distantPast) {}
    }

    // MARK: - Helpers

    private func stored(_ c: HTTPCookie) -> StoredCookie {
        StoredCookie(name: c.name, value: c.value, domain: c.domain, path: c.path,
                     expires: c.expiresDate ?? Date().addingTimeInterval(lifetime),
                     secure: c.isSecure, httpOnly: c.isHTTPOnly,
                     sameSite: c.sameSitePolicy?.rawValue)
    }

    private func makeCookie(_ c: StoredCookie) -> HTTPCookie? {
        var p: [HTTPCookiePropertyKey: Any] = [
            .name: c.name, .value: c.value, .domain: c.domain, .path: c.path,
            .expires: c.expires ?? Date().addingTimeInterval(lifetime)
        ]
        if c.secure { p[.secure] = "TRUE" }
        if c.httpOnly { p[HTTPCookiePropertyKey("HttpOnly")] = "TRUE" }
        if let s = c.sameSite { p[.sameSitePolicy] = s }
        return HTTPCookie(properties: p)
    }

    private func load() -> [StoredCookie] {
        guard let data = try? Data(contentsOf: fileURL),
              let list = try? JSONDecoder().decode([StoredCookie].self, from: data) else { return [] }
        return list
    }

    private func save(_ list: [StoredCookie]) {
        if let data = try? JSONEncoder().encode(list) {
            try? data.write(to: fileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        }
    }
}
