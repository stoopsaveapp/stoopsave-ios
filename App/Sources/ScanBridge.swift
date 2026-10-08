import UIKit
import VisionKit

/// Document scanner bridge (window.StoopSaveApp.scanDocument()).
///
/// Uses Apple's VisionKit VNDocumentCameraViewController — the iOS equivalent
/// of the ML Kit document scanner on Android: on-device auto edge detection,
/// perspective correction, and capture UI. (Google's ML Kit also ships an iOS
/// DocumentScanner module; VisionKit was chosen because it is part of the iOS
/// SDK — zero dependency risk — and its UX is identical. Swapping to ML Kit
/// later only touches scan(presenter:); the bridge contract is unchanged.)
///
/// Result delivery mirrors Android exactly: the scanned JPEG is base64-encoded
/// and handed to the page as a data URL via window.onNativeScanResult(url),
/// with the stoopsave:scan-result CustomEvent as fallback. Cancellation calls
/// window.onNativeScanCancelled(); failures call window.onNativeScanError(code).
final class ScanBridge: NSObject, VNDocumentCameraViewControllerDelegate {
    static let shared = ScanBridge()

    /// Set by SaveViewController: (js) -> Void runs it in the WebView.
    var jsCallback: ((String) -> Void)?

    private override init() {}

    func scan(presenter: UIViewController) {
        guard VNDocumentCameraViewController.isSupported else {
            notifyError("unsupported")
            return
        }
        let vc = VNDocumentCameraViewController()
        vc.delegate = self
        presenter.present(vc, animated: true)
    }

    // MARK: - VNDocumentCameraViewControllerDelegate

    func documentCameraViewController(
        _ controller: VNDocumentCameraViewController,
        didFinishWith scan: VNDocumentCameraScan
    ) {
        controller.dismiss(animated: true) {
            guard scan.pageCount > 0 else {
                self.notifyError("no-pages")
                return
            }
            let image = scan.imageOfPage(at: 0)
            // Cap the payload: shrink JPEG quality until the data URL stays
            // reasonable for a single evaluateJavaScript call.
            var quality: CGFloat = 0.9
            var data = image.jpegData(compressionQuality: quality) ?? Data()
            while data.count > 6 * 1024 * 1024 && quality > 0.4 {
                quality -= 0.15
                if let d = image.jpegData(compressionQuality: quality) { data = d }
                else { break }
            }
            guard !data.isEmpty else {
                self.notifyError("encode-failed")
                return
            }
            self.deliver(data)
        }
    }

    func documentCameraViewControllerDidCancel(
        _ controller: VNDocumentCameraViewController
    ) {
        controller.dismiss(animated: true) {
            self.jsCallback?(
                "if(window.onNativeScanCancelled){window.onNativeScanCancelled();}"
                    + "else{window.dispatchEvent(new CustomEvent('stoopsave:scan-cancelled'));} "
            )
        }
    }

    func documentCameraViewController(
        _ controller: VNDocumentCameraViewController,
        didFailWithError error: Error
    ) {
        controller.dismiss(animated: true) {
            self.notifyError("failed")
        }
    }

    // MARK: - Delivery

    private func notifyError(_ code: String) {
        jsCallback?(
            "(function(){var c=\(JSEscape.string(code));"
                + "if(window.onNativeScanError){window.onNativeScanError(c);}"
                + "else{window.dispatchEvent(new CustomEvent('stoopsave:scan-error',"
                + "{detail:{code:c}}));}})();"
        )
    }

    private func deliver(_ jpegData: Data) {
        // base64 has no quotes/backslashes/newlines, so it is safe to inline.
        let b64 = jpegData.base64EncodedString()
        jsCallback?(
            "(function(){try{"
                + "var url='data:image/jpeg;base64," + b64 + "';"
                + "if(window.onNativeScanResult){window.onNativeScanResult(url);}"
                + "else{window.dispatchEvent(new CustomEvent('stoopsave:scan-result',"
                + "{detail:{dataUrl:url}}));}"
                + "}catch(e){}})();"
        )
    }
}
