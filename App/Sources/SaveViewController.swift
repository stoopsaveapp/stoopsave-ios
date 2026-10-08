import UIKit
import WebKit

/// Hosts https://stoopsave.com/app in a WKWebView.
///
/// This is the iOS twin of Android's MainActivity: same web app, same
/// window.StoopSaveApp bridge contract. The bridge is injected by bridge.js
/// at document start and intercepted below via prompt() (see BridgeDispatcher),
/// so every method is synchronous exactly like Android's @JavascriptInterface.
final class SaveViewController: UIViewController, WKUIDelegate, WKNavigationDelegate {

    private var webView: WKWebView!
    private let homeURL = URL(string: "https://stoopsave.com/app")!

    override func viewDidLoad() {
        super.viewDidLoad()
        // StoopSave navy — matches the Android splash / launch screen.
        view.backgroundColor = UIColor(red: 0x0A / 255.0, green: 0x25 / 255.0,
                                       blue: 0x40 / 255.0, alpha: 1.0)

        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        // Android: setDomStorageEnabled(true) — the default data store persists
        // localStorage/cookies across launches, same as the Android WebView.
        config.websiteDataStore = .default()

        // Synchronous native bridge (see BridgeDispatcher). Injected before any
        // page script runs, in every frame.
        if let bridgeURL = Bundle.main.url(forResource: "bridge", withExtension: "js"),
           let bridgeSource = try? String(contentsOf: bridgeURL, encoding: .utf8) {
            config.userContentController.addUserScript(
                WKUserScript(source: bridgeSource,
                             injectionTime: .atDocumentStart,
                             forMainFrameOnly: false)
            )
        }

        webView = WKWebView(frame: .zero, configuration: config)
        webView.uiDelegate = self
        webView.navigationDelegate = self
        webView.translatesAutoresizingMaskIntoConstraints = false
        webView.scrollView.bounces = false
        webView.allowsBackForwardNavigationGestures = true
        view.addSubview(webView)
        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: view.topAnchor),
            webView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])

        // Native -> JS callbacks.
        ScanBridge.shared.jsCallback = { [weak self] js in
            self?.webView.evaluateJavaScript(js, completionHandler: nil)
        }
        PushBridge.shared.onPlayerId = { [weak self] _ in
            self?.pushBridgeState()
        }
        NotificationCenter.default.addObserver(
            self, selector: #selector(openURL(_:)),
            name: .ssOpenURL, object: nil
        )

        webView.load(URLRequest(url: homeURL))
    }

    // MARK: - prompt() interception (the synchronous bridge)

    func webView(
        _ webView: WKWebView,
        runJavaScriptTextInputPanelWithPrompt prompt: String,
        defaultText: String?,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping (String?) -> Void
    ) {
        if prompt.hasPrefix(BridgeDispatcher.schemePrefix) {
            BridgeDispatcher.shared.dispatch(
                prompt: prompt, presenter: self, completion: completionHandler)
        } else {
            // The app never uses prompt() for real user input.
            completionHandler(nil)
        }
    }

    // MARK: - Navigation

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        pushBridgeState()
        // One-shot OAuth session handoff (mirrors Android's
        // getPendingOAuthSession): stash -> page reads it once via the bridge.
        if let s = UserDefaults.standard.string(forKey: "pending_oauth_session"),
           !s.isEmpty {
            UserDefaults.standard.removeObject(forKey: "pending_oauth_session")
            webView.evaluateJavaScript(
                "window.__ssPendingOAuth=\(JSEscape.string(s));",
                completionHandler: nil)
        }
    }

    /// Re-push native-held bridge state after every page load (a fresh JS
    /// context wipes the injected vars).
    private func pushBridgeState() {
        webView.evaluateJavaScript(
            "window.__ssPlayerId=\(JSEscape.string(PushBridge.shared.playerId));",
            completionHandler: nil)
    }

    @objc private func openURL(_ note: Notification) {
        guard let s = note.object as? String,
              let url = URL(string: s) else { return }
        webView.load(URLRequest(url: url))
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}
