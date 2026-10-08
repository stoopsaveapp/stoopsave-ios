import UIKit
import WebKit
import AVFoundation
import CoreLocation

/// JS string escaping, mirroring Android's JSONObject.quote(): backslash- and
/// quote-escaped, wrapped in double quotes.
enum JSEscape {
    static func string(_ s: String) -> String {
        let escaped = s
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
        return "\"\(escaped)\""
    }
}

/// Synchronous JS -> native bridge.
///
/// Android exposes window.StoopSaveApp as @JavascriptInterface, whose calls are
/// synchronous. bridge.js (injected at document start) routes every call
/// through prompt('stoopsave://app/<method>?<args>'), which SaveViewController
/// intercepts in WKUIDelegate and sends here. JS stays blocked until the
/// completion handler runs, so return values are synchronous exactly like
/// Android's.
///
/// Args are a URL-encoded JSON array. Every method answers "" immediately;
/// inherently async work (scanner, share sheet) presents UI after the prompt
/// is released and delivers results later via evaluateJavaScript, exactly like
/// Android's window.onNativeScanResult / stoopsave:scan-result events.
final class BridgeDispatcher {
    static let shared = BridgeDispatcher()
    static let schemePrefix = "stoopsave://app/"

    private init() {}

    func dispatch(
        prompt: String,
        presenter: UIViewController,
        completion: @escaping (String?) -> Void
    ) {
        let result = route(prompt: prompt, presenter: presenter)
        completion(result)
    }

    private func route(prompt: String, presenter: UIViewController) -> String {
        guard prompt.hasPrefix(Self.schemePrefix) else { return "" }
        // "scanDocument?%5B%5D" -> method "scanDocument", args []
        let rest = String(prompt.dropFirst(Self.schemePrefix.count))
        let halves = rest.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false)
        let method = String(halves[0])

        var args: [Any] = []
        if halves.count > 1,
           let decoded = String(halves[1]).removingPercentEncoding,
           let data = decoded.data(using: .utf8),
           let arr = try? JSONSerialization.jsonObject(with: data, options: []) as? [Any] {
            args = arr
        }
        func strArg(_ i: Int) -> String {
            (i < args.count ? args[i] as? String : nil) ?? ""
        }

        switch method {
        case "getFcmToken":
            // iOS has no FCM in this app; OneSignal's player ID is the push
            // identifier. The page already falls back to it when this is empty.
            return ""
        case "getFcmDebug":
            return "ios:onesignal-only"
        case "performHaptic":
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            return ""
        case "getOneSignalPlayerId":
            return PushBridge.shared.playerId
        case "getPendingOAuthSession":
            // One-shot read, mirrors Android: return the stashed session and
            // clear it. (SaveViewController also injects it as
            // window.__ssPendingOAuth on page load; this is the backup path.)
            let key = "pending_oauth_session"
            let s = UserDefaults.standard.string(forKey: key) ?? ""
            if !s.isEmpty { UserDefaults.standard.removeObject(forKey: key) }
            return s
        case "getVersion":
            // Parity with Android's bridge version string.
            return "1.00"
        case "ensureCameraPermission":
            PermissionHelper.ensureCameraPermission()
            return ""
        case "cameraState":
            return PermissionHelper.cameraState()
        case "ensureLocationPermission":
            PermissionHelper.ensureLocationPermission()
            return ""
        case "locationState":
            return PermissionHelper.locationState()
        case "shareOffer":
            // Native share sheet (WKWebView has no navigator.share) —
            // mirrors Android's ACTION_SEND chooser.
            let title = strArg(0), text = strArg(1), url = strArg(2)
            DispatchQueue.main.async {
                var items: [Any] = []
                if !title.isEmpty { items.append(title) }
                let body = [text, url].filter { !$0.isEmpty }.joined(separator: "\n")
                if !body.isEmpty { items.append(body) }
                guard !items.isEmpty else { return }
                let vc = UIActivityViewController(activityItems: items, applicationActivities: nil)
                if let pop = vc.popoverPresentationController {
                    pop.sourceView = presenter.view
                    pop.sourceRect = CGRect(
                        x: presenter.view.bounds.midX, y: presenter.view.bounds.midY,
                        width: 0, height: 0)
                    pop.permittedArrowDirections = []
                }
                presenter.present(vc, animated: true)
            }
            return ""
        case "scanDocument":
            // Async by nature: the prompt is released now; the scanned JPEG
            // arrives later via window.onNativeScanResult (or the
            // stoopsave:scan-result CustomEvent), exactly like Android.
            DispatchQueue.main.async {
                ScanBridge.shared.scan(presenter: presenter)
            }
            return ""
        default:
            return ""
        }
    }
}

/// Camera / location permission helpers, mirroring Android's settled-first
/// pattern: the page calls ensure*Permission() before using the capability,
/// then polls *State() — "granted" | "denied" (can still ask) | "blocked".
enum PermissionHelper {
    // MARK: Camera

    static func cameraState() -> String {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            return "granted"
        case .notDetermined:
            return "denied"
        case .denied, .restricted:
            return UserDefaults.standard.bool(forKey: "cameraRequestedBefore")
                ? "blocked" : "denied"
        @unknown default:
            return "denied"
        }
    }

    static func ensureCameraPermission() {
        UserDefaults.standard.set(true, forKey: "cameraRequestedBefore")
        AVCaptureDevice.requestAccess(for: .video) { _ in }
    }

    // MARK: Location

    static func locationState() -> String {
        switch LocationManager.shared.authorization {
        case .authorizedAlways, .authorizedWhenInUse:
            return "granted"
        case .notDetermined:
            return "denied"
        case .denied, .restricted:
            return UserDefaults.standard.bool(forKey: "locationRequestedBefore")
                ? "blocked" : "denied"
        @unknown default:
            return "denied"
        }
    }

    static func ensureLocationPermission() {
        UserDefaults.standard.set(true, forKey: "locationRequestedBefore")
        LocationManager.shared.request()
    }
}

/// Single shared CLLocationManager (iOS requires a persistent delegate for
/// authorization callbacks; WKWebView's own geolocation prompts then work
/// against the settled permission, same as Android's settled-first pattern).
final class LocationManager: NSObject, CLLocationManagerDelegate {
    static let shared = LocationManager()
    private let manager = CLLocationManager()

    private override init() {
        super.init()
        manager.delegate = self
    }

    var authorization: CLAuthorizationStatus {
        manager.authorizationStatus
    }

    func request() {
        DispatchQueue.main.async {
            self.manager.requestWhenInUseAuthorization()
        }
    }
}
