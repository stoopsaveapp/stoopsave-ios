/* StoopSave iOS native bridge (bridge.js).
 *
 * Injected by SaveViewController at document start, before any page script runs.
 *
 * Android exposes window.StoopSaveApp as a @JavascriptInterface object whose
 * calls are SYNCHRONOUS. WKScriptMessageHandler is async-only, so every method
 * here is routed through prompt('stoopsave://app/<method>?<urlencoded JSON args>'),
 * which the native side intercepts in WKUIDelegate (see BridgeDispatcher.swift).
 * JS blocks until the native side answers, so return values are synchronous
 * exactly like Android's — the page's existing contracts
 * (getOneSignalPlayerId() -> string, cameraState() -> 'granted'|'denied'|'blocked',
 * scanDocument() -> void with window.onNativeScanResult delivery, …) work unchanged.
 *
 * The app never uses prompt() for real user input, so there is no conflict.
 */
(function () {
  if (window.__ssIOSBridgeInstalled) return;
  window.__ssIOSBridgeInstalled = true;

  function ssCall(method, args) {
    try {
      var payload = encodeURIComponent(JSON.stringify(args || []));
      var res = window.prompt('stoopsave://app/' + method + '?' + payload);
      return (res === null || res === undefined) ? '' : String(res);
    } catch (e) {
      return '';
    }
  }

  window.StoopSaveApp = {
    getFcmToken: function () { return ssCall('getFcmToken'); },
    getFcmDebug: function () { return ssCall('getFcmDebug'); },
    performHaptic: function () { ssCall('performHaptic'); },
    getOneSignalPlayerId: function () { return ssCall('getOneSignalPlayerId'); },
    getPendingOAuthSession: function () { return ssCall('getPendingOAuthSession'); },
    getVersion: function () { return ssCall('getVersion'); },
    ensureCameraPermission: function () { ssCall('ensureCameraPermission'); },
    cameraState: function () { return ssCall('cameraState'); },
    ensureLocationPermission: function () { ssCall('ensureLocationPermission'); },
    locationState: function () { return ssCall('locationState'); },
    shareOffer: function (title, text, url) { ssCall('shareOffer', [title, text, url]); },
    scanDocument: function () { ssCall('scanDocument'); }
  };
})();
