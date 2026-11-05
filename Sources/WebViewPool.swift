import UIKit
import WebKit

/// يحتفظ بمتصفح مستقل لكل لوحة، فالتبديل بين اللوحات لا يعيد تحميلها.
final class WebViewPool: NSObject {
    static let shared = WebViewPool()

    private var views: [UUID: WKWebView] = [:]
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
        let url = panel.normalizedURL
        CookieVault.shared.restore {
            if let url = url { wv.load(URLRequest(url: url)) }
        }
        return wv
    }

    func reset(_ id: UUID) {
        views[id]?.removeFromSuperview()
        views[id] = nil
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
