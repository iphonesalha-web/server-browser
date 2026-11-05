import UIKit
import WebKit

/// يحتفظ بمتصفح مستقل لكل لوحة، فالتبديل بين اللوحات لا يعيد تحميلها.
final class WebViewPool: NSObject {
    static let shared = WebViewPool()

    private var views: [UUID: WKWebView] = [:]
    private var panels: [ObjectIdentifier: Panel] = [:]
    private var triedHTTP: Set<UUID> = []
    private let processPool = WKProcessPool()

    func webView(for panel: Panel) -> WKWebView {
        if let existing = views[panel.id] { return existing }

        let config = WKWebViewConfiguration()
        config.processPool = processPool
        config.websiteDataStore = .default()
        config.allowsInlineMediaPlayback = true

        let content = WKUserContentController()
        let js = Autofill.script(username: panel.username,
                                 password: Keychain.get(panel.id.uuidString))
        if !js.isEmpty {
            content.addUserScript(WKUserScript(source: js, injectionTime: .atDocumentEnd, forMainFrameOnly: true))
        }
        config.userContentController = content

        let wv = WKWebView(frame: .zero, configuration: config)
        wv.allowsBackForwardNavigationGestures = true
        wv.navigationDelegate = self
        wv.uiDelegate = self

        let refresh = UIRefreshControl()
        refresh.addTarget(self, action: #selector(pulled(_:)), for: .valueChanged)
        wv.scrollView.refreshControl = refresh

        views[panel.id] = wv
        panels[ObjectIdentifier(wv)] = panel
        let url = panel.normalizedURL
        CookieVault.shared.restore {
            if let url = url { wv.load(URLRequest(url: url)) }
        }
        return wv
    }

    func reset(_ id: UUID) {
        if let wv = views[id] { panels[ObjectIdentifier(wv)] = nil; wv.removeFromSuperview() }
        views[id] = nil
        triedHTTP.remove(id)
    }

    func goBack(_ id: UUID) { views[id]?.goBack() }
    func reload(_ id: UUID) { views[id]?.reload() }

    func goHome(_ panel: Panel) {
        if let url = panel.normalizedURL { views[panel.id]?.load(URLRequest(url: url)) }
    }

    @objc private func pulled(_ control: UIRefreshControl) {
        (control.superview?.superview as? WKWebView)?.reload()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { control.endRefreshing() }
    }

    fileprivate func present(_ vc: UIViewController) -> Bool {
        let window = UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.keyWindow }
            .first
        guard var top = window?.rootViewController else { return false }
        while let next = top.presentedViewController { top = next }
        top.present(vc, animated: true)
        return true
    }
}

extension WebViewPool: WKNavigationDelegate, WKUIDelegate {
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        CookieVault.shared.snapshot()
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        handleLoadError(webView, error)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        handleLoadError(webView, error)
    }

    private func handleLoadError(_ webView: WKWebView, _ error: Error) {
        let ns = error as NSError
        if ns.domain == NSURLErrorDomain && ns.code == NSURLErrorCancelled { return }
        if ns.domain == "WebKitErrorDomain" && ns.code == 102 { return } // تنزيل ملف / إطار أُوقف

        let failed = (ns.userInfo[NSURLErrorFailingURLErrorKey] as? URL)
            ?? (ns.userInfo["NSErrorFailingURLKey"] as? URL)
            ?? webView.url

        // رابط بدون http/https فشل على https → نجرّب http مرة واحدة
        if let panel = panels[ObjectIdentifier(webView)], !panel.hasExplicitScheme,
           !triedHTTP.contains(panel.id), let f = failed, f.scheme == "https",
           var c = URLComponents(url: f, resolvingAgainstBaseURL: false) {
            triedHTTP.insert(panel.id)
            c.scheme = "http"
            if let u = c.url { webView.load(URLRequest(url: u)); return }
        }
        showError(webView, error: ns, url: failed)
    }

    private func showError(_ webView: WKWebView, error: NSError, url: URL?) {
        let reason: String
        switch error.code {
        case NSURLErrorNotConnectedToInternet: reason = "لا يوجد اتصال بالإنترنت."
        case NSURLErrorTimedOut: reason = "السيرفر لم يرد في الوقت المحدد."
        case NSURLErrorCannotFindHost, NSURLErrorDNSLookupFailed: reason = "لم يتم العثور على عنوان السيرفر. تأكد من الرابط."
        case NSURLErrorCannotConnectToHost: reason = "السيرفر رفض الاتصال. ربما المنفذ (البورت) خطأ أو السيرفر متوقف."
        case NSURLErrorSecureConnectionFailed, NSURLErrorServerCertificateUntrusted,
             NSURLErrorServerCertificateHasBadDate, NSURLErrorServerCertificateHasUnknownRoot,
             NSURLErrorServerCertificateNotYetValid:
            reason = "مشكلة في الاتصال الآمن (https). جرّب كتابة الرابط بـ http:// بدل https://"
        case NSURLErrorAppTransportSecurityRequiresSecureConnection: reason = "الاتصال غير الآمن ممنوع."
        default: reason = "تعذّر فتح الصفحة."
        }
        func esc(_ s: String) -> String {
            s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
             .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
        }
        let link = url?.absoluteString ?? ""
        let html = """
        <!doctype html><html dir="rtl"><head><meta charset="utf-8">
        <meta name="viewport" content="width=device-width,initial-scale=1">
        <style>
        body{font-family:-apple-system,system-ui;margin:0;padding:40px 22px;color:#1c1c1e;background:#f2f2f7;text-align:center}
        @media (prefers-color-scheme:dark){body{color:#f2f2f7;background:#000}.box{background:#1c1c1e!important}}
        .box{background:#fff;border-radius:16px;padding:24px 18px;max-width:420px;margin:0 auto}
        h2{margin:0 0 10px;font-size:20px}p{line-height:1.6;margin:8px 0}
        code{direction:ltr;display:block;font-size:12px;color:#8e8e93;word-break:break-all;margin-top:14px}
        a{display:inline-block;margin-top:18px;background:#ff9500;color:#fff;text-decoration:none;padding:12px 22px;border-radius:12px;font-weight:600}
        </style></head><body><div class="box">
        <h2>تعذّر فتح اللوحة</h2><p>\(esc(reason))</p>
        <code>\(esc(link))<br>\(esc(error.localizedDescription)) (\(error.code))</code>
        <a href="\(esc(link))">إعادة المحاولة</a>
        </div></body></html>
        """
        webView.loadHTMLString(html, baseURL: nil)
    }

    // نافذة دخول يطلبها السيرفر نفسه (Basic / Digest) وشهادات https الذاتية
    func webView(_ webView: WKWebView, didReceive challenge: URLAuthenticationChallenge,
                 completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        let method = challenge.protectionSpace.authenticationMethod
        let panel = panels[ObjectIdentifier(webView)]

        if method == NSURLAuthenticationMethodServerTrust {
            // لوحاتك أنت أضفتها: نقبل شهادتها حتى لو كانت ذاتية التوقيع
            if let trust = challenge.protectionSpace.serverTrust,
               let host = panel?.normalizedURL?.host,
               challenge.protectionSpace.host.lowercased() == host.lowercased() {
                completionHandler(.useCredential, URLCredential(trust: trust))
            } else {
                completionHandler(.performDefaultHandling, nil)
            }
            return
        }

        guard method == NSURLAuthenticationMethodHTTPBasic || method == NSURLAuthenticationMethodHTTPDigest
                || method == NSURLAuthenticationMethodDefault else {
            completionHandler(.performDefaultHandling, nil); return
        }

        if challenge.previousFailureCount == 0, let p = panel, !p.username.isEmpty {
            let pass = Keychain.get(p.id.uuidString)
            completionHandler(.useCredential, URLCredential(user: p.username, password: pass, persistence: .forSession))
            return
        }

        let a = UIAlertController(title: "تسجيل الدخول",
                                  message: challenge.protectionSpace.host, preferredStyle: .alert)
        a.addTextField { $0.placeholder = "اسم المستخدم"; $0.text = panel?.username; $0.autocapitalizationType = .none }
        a.addTextField { $0.placeholder = "كلمة المرور"; $0.isSecureTextEntry = true }
        a.addAction(UIAlertAction(title: "إلغاء", style: .cancel) { _ in
            completionHandler(.cancelAuthenticationChallenge, nil)
        })
        a.addAction(UIAlertAction(title: "دخول", style: .default) { _ in
            let u = a.textFields?[0].text ?? "", pw = a.textFields?[1].text ?? ""
            completionHandler(.useCredential, URLCredential(user: u, password: pw, persistence: .forSession))
        })
        if !present(a) { completionHandler(.performDefaultHandling, nil) }
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        webView.reload()
    }

    // روابط "تفتح في نافذة جديدة" تفتح في نفس الصفحة
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if navigationAction.targetFrame == nil { webView.load(navigationAction.request) }
        return nil
    }

    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
        let a = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        a.addAction(UIAlertAction(title: "حسناً", style: .default) { _ in completionHandler() })
        if !present(a) { completionHandler() }
    }

    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
        let a = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        a.addAction(UIAlertAction(title: "إلغاء", style: .cancel) { _ in completionHandler(false) })
        a.addAction(UIAlertAction(title: "موافق", style: .default) { _ in completionHandler(true) })
        if !present(a) { completionHandler(false) }
    }

    func webView(_ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String,
                 defaultText: String?, initiatedByFrame frame: WKFrameInfo,
                 completionHandler: @escaping (String?) -> Void) {
        let a = UIAlertController(title: nil, message: prompt, preferredStyle: .alert)
        a.addTextField { $0.text = defaultText }
        a.addAction(UIAlertAction(title: "إلغاء", style: .cancel) { _ in completionHandler(nil) })
        a.addAction(UIAlertAction(title: "موافق", style: .default) { _ in completionHandler(a.textFields?.first?.text) })
        if !present(a) { completionHandler(nil) }
    }
}
