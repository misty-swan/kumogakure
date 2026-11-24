import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// Presents the system `UIActivityViewController` and notifies reliably when dismissed.
struct ActivityViewControllerWrapper: UIViewControllerRepresentable {
    let activityItems: [Any]
    var applicationActivities: [UIActivity]? = nil
    let onComplete: @MainActor (Bool) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onComplete: onComplete)
    }

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(
            activityItems: activityItems,
            applicationActivities: applicationActivities
        )
        controller.completionWithItemsHandler = { [weak coordinator = context.coordinator] _, completed, _, _ in
            Task { @MainActor in
                coordinator?.notifyIfNeeded(completed: completed)
            }
        }
        return controller
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}

    @MainActor
    final class Coordinator {
        private let onComplete: @MainActor (Bool) -> Void
        private var didNotifyCompletion = false

        init(onComplete: @escaping @MainActor (Bool) -> Void) {
            self.onComplete = onComplete
        }

        @MainActor
        func notifyIfNeeded(completed: Bool) {
            guard !didNotifyCompletion else { return }
            didNotifyCompletion = true
            onComplete(completed)
        }
    }
}
