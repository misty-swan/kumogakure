import SwiftData
import SwiftUI

/// Entry point configuring SwiftData persistence, anonymous UUID, and task-kill recovery.
@main
struct KumogakureApp: App {
    private let modelContainer: ModelContainer

    init() {
        do {
            self.modelContainer = try ModelContainer(for: DetoxSessionRecord.self)
        } catch {
            fatalError("Failed to initialize SwiftData ModelContainer: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            AppRootShell(modelContainer: modelContainer)
        }
        .modelContainer(modelContainer)
    }
}

/// Initializes `@MainActor` session store safely from `modelContainer.mainContext`.
private struct AppRootShell: View {
    let modelContainer: ModelContainer
    @State private var sessionStore: DetoxSessionStore?

    var body: some View {
        Group {
            if let sessionStore {
                RootView(store: sessionStore)
            } else {
                KumogakureColors.sumiBg
                    .ignoresSafeArea()
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            guard sessionStore == nil else { return }
            let store = DetoxSessionStore(modelContext: modelContainer.mainContext)
            _ = store.anonymousUserUUID
            store.recoverInProgressSessionIfNeeded()
            sessionStore = store

            let isRunningTests = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
            if !isRunningTests {
                Task {
                    await store.onAppLaunch()
                }
            }
        }
    }
}
