import SwiftUI
import SwiftData

@main
struct CapiCar_for_YOSApp: App {
    
    // MARK: - State Objects (Singletons)
    
    @StateObject private var authManager = AuthenticationManager()
    @StateObject private var staffManager = StaffManager()
    // MARK: - SwiftData Container
    
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            LocalTask.self,
            LocalChecklistItem.self
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            print("Could not create ModelContainer: \(error)")
            // Fallback to in-memory container
            let fallbackConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            do {
                return try ModelContainer(for: schema, configurations: [fallbackConfiguration])
            } catch {
                fatalError("Could not create fallback ModelContainer: \(error)")
            }
        }
    }()
    

    init() {
        // Initialize DatabaseManager immediately when app starts
        DatabaseManager.shared.initialize(with: sharedModelContainer)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(authManager)
                .environmentObject(staffManager)
                .environmentObject(SyncManager.shared)
        }
        .modelContainer(sharedModelContainer)
    }
}

// MARK: - Root View with Authentication Flow

struct RootView: View {
    @EnvironmentObject private var authManager: AuthenticationManager
    @EnvironmentObject private var staffManager: StaffManager
    @EnvironmentObject private var syncManager: SyncManager
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            if authManager.isAuthenticated {
                if staffManager.isOperatorCheckedIn {
                    // User is authenticated and has selected an operator
                    MainAppView()
                } else {
                    // User is authenticated but needs to select operator
                    StaffCheckInView()
                }
            } else {
                // User is not authenticated
                LoginView()
            }
        }
        .onAppear {
            // Trigger sync when app first launches
            Task {
                print("🚀 APP LAUNCH: Triggering proactive sync")
                await syncManager.triggerSync()
            }
        }
        .onChange(of: scenePhase) { oldPhase, newPhase in
            // Trigger sync when app becomes active from background
            if oldPhase == .background && newPhase == .active {
                Task {
                    print("🔄 APP ACTIVE: Triggering proactive sync from background")
                    await syncManager.triggerSync()
                }
            }
        }
    }
}

// MARK: - Main App View (Post-Authentication)

struct MainAppView: View {
    var body: some View {
        ContentView()
    }
}
