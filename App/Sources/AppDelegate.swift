import UIKit
import OneSignalFramework

/// StoopSave iOS shell — AppDelegate.
///
/// Thin app: OneSignal push init + window setup. The whole product is the
/// WKWebView in SaveViewController loading https://stoopsave.com/app,
/// mirroring Android's MainActivity (com.stoopsave.app).
@main
class AppDelegate: UIResponder, UIApplicationDelegate {

    /// Same OneSignal app as Android — one app, both platforms.
    static let oneSignalAppId = "3f1470be-8762-407d-a39a-5bd313e6cd34"

    var window: UIWindow?

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        // OneSignal push (v5 SDK via Swift Package Manager).
        OneSignal.initialize(AppDelegate.oneSignalAppId, withLaunchOptions: launchOptions)
        // Ask for notification permission at launch, like Android's
        // POST_NOTIFICATIONS request. No fallback-to-Settings redirect.
        OneSignal.Notifications.requestPermission({ _ in }, fallbackToSettings: false)
        // Tapping a push with a URL (e.g. the weekly digest deep link
        // https://stoopsave.com/app?digest=1) opens it in the WebView.
        OneSignal.Notifications.addClickListener(NotificationClickListener())
        PushBridge.shared.start()

        window = UIWindow(frame: UIScreen.main.bounds)
        window?.rootViewController = SaveViewController()
        window?.makeKeyAndVisible()
        return true
    }

    // MARK: - Universal Links (applinks:stoopsave.com, see
    // docs/apple-app-site-association.json). Lets notification taps and
    // shared links open inside the app instead of Safari.

    func application(
        _ application: UIApplication,
        continue userActivity: NSUserActivity,
        restorationHandler: @escaping ([UIUserActivityRestoring]?) -> Void
    ) -> Bool {
        guard userActivity.activityType == NSUserActivityTypeBrowsingWeb,
              let url = userActivity.webpageURL else { return false }
        NotificationCenter.default.post(name: .ssOpenURL, object: url.absoluteString)
        return true
    }

    // MARK: - OAuth deep link (stoopsave://auth?session=...)
    //
    // Mirrors Android's getPendingOAuthSession(): the session is stashed and
    // handed to the page once, on the next page load.

    func application(
        _ app: UIApplication,
        open url: URL,
        options: [UIApplication.OpenURLOptionsKey: Any] = [:]
    ) -> Bool {
        guard url.scheme == "stoopsave",
              url.host == "auth",
              let comps = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let session = comps.queryItems?.first(where: { $0.name == "session" })?.value,
              !session.isEmpty
        else { return false }
        UserDefaults.standard.set(session, forKey: "pending_oauth_session")
        return true
    }
}

extension Notification.Name {
    /// Object is the URL string to load in the WebView.
    static let ssOpenURL = Notification.Name("ssOpenURL")
}

/// OneSignal v5 notification click listener — opens push URLs in the WebView.
private class NotificationClickListener: NSObject, OSNotificationClickListener {
    func onClick(event: OSNotificationClickEvent) {
        if let url = event.notification.launchURL, !url.isEmpty {
            NotificationCenter.default.post(name: .ssOpenURL, object: url)
        }
    }
}
