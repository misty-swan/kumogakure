import SwiftUI

/// Routes between S-01, S-03, S-04, and S-05 and bridges SwiftUI `scenePhase` to `DetoxSessionStore`.
struct RootView: View {
    @Bindable var store: DetoxSessionStore
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            switch store.state {
            case .idle, .preparingShare:
                HomeView(store: store)
            case .active, .gracePeriod:
                DetoxSessionView(store: store)
            case .completed(let summary):
                ReturnCompleteView(store: store, summary: summary)
            case .canceled(let summary), .interrupted(let summary):
                EarlyReturnView(store: store, summary: summary)
            }
        }
        .preferredColorScheme(.dark)
        .tint(KumogakureColors.shinonomeAccent)
        .onChange(of: scenePhase) { _, newPhase in
            store.handleScenePhaseChange(mappedPhase(newPhase))
        }
    }

    private func mappedPhase(_ phase: ScenePhase) -> AppScenePhase {
        switch phase {
        case .active:
            return .active
        case .inactive:
            return .inactive
        case .background:
            return .background
        @unknown default:
            return .inactive
        }
    }
}
