import Foundation
import OneSignalFramework

/// OneSignal push-subscription cache.
///
/// window.StoopSaveApp.getOneSignalPlayerId() must answer synchronously (like
/// Android's @JavascriptInterface), so the player ID is cached here and kept
/// fresh via the OneSignal subscription observer. SaveViewController re-pushes
/// it into the page (window.__ssPlayerId) on every page load; the bridge
/// itself reads this cache.
final class PushBridge: NSObject, OSPushSubscriptionObserver {
    static let shared = PushBridge()

    /// The OneSignal player (subscription) ID, "" until the SDK registers.
    private(set) var playerId: String = ""

    /// Fired whenever the player ID changes (e.g. first registration).
    var onPlayerId: ((String) -> Void)?

    private override init() {}

    func start() {
        if let id = OneSignal.User.pushSubscription.id, !id.isEmpty {
            playerId = id
        }
        OneSignal.User.pushSubscription.addObserver(self)
    }

    // MARK: - OSPushSubscriptionObserver

    func onPushSubscriptionDidChange(
        state: OSPushSubscriptionChangedState
    ) {
        if let id = state.current.id, !id.isEmpty, id != playerId {
            playerId = id
            onPlayerId?(id)
        }
    }
}
