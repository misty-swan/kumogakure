import SwiftUI
#if canImport(SafariServices)
import SafariServices
#endif
#if canImport(UIKit)
import UIKit
#endif

/// In-app browser sheet for legal documents and Google support form (`ux-and-screens.md` S-07 / S-08).
struct SafariWebView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        let controller = SFSafariViewController(url: url)
        #if canImport(UIKit)
        controller.preferredBarTintColor = UIColor(KumogakureColors.sumiBg)
        controller.preferredControlTintColor = UIColor(KumogakureColors.shinonomeAccent)
        #endif
        return controller
    }

    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {}
}
