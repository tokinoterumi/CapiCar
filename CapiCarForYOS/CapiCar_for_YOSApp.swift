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
    

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(authManager)
                .environmentObject(staffManager)
                .environmentObject(SyncManager.shared)
                .onAppear {
                    // Initialize DatabaseManager with the shared container
                    Task { @MainActor in
                        DatabaseManager.shared.initialize(with: sharedModelContainer)
                    }
                }
        }
        .modelContainer(sharedModelContainer)
    }
}

// MARK: - Root View with Authentication Flow

struct RootView: View {
    @EnvironmentObject private var authManager: AuthenticationManager
    @EnvironmentObject private var staffManager: StaffManager
    
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
    }
}

// MARK: - Main App View (Post-Authentication)

struct MainAppView: View {
    var body: some View {
        ContentView()
    }
}
