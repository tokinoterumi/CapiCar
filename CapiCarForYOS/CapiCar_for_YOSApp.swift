//
//  CapiCar_for_YOSApp.swift
//  CapiCar for YOS
//
//  Created by Terumi on 9/2/07.
//

import SwiftUI
import SwiftData

@main
struct CapiCar_for_YOSApp: App {
    
    // MARK: - State Objects (Singletons)
    
    @StateObject private var authManager = AuthenticationManager()
    @StateObject private var staffManager = StaffManager()
    @StateObject private var syncManager: SyncManager
    
    // MARK: - SwiftData Container
    
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Item.self,
            LocalFulfillmentTask.self,
            LocalStaffMember.self,
            LocalChecklistItem.self,
            LocalAuditLog.self,
            LocalSyncState.self
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
    
    // Initialize SyncManager after other components
    init() {
        // Initialize SyncManager last to avoid circular dependencies
        let manager = SyncManager()
        self._syncManager = StateObject(wrappedValue: manager)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(authManager)
                .environmentObject(staffManager)
                .environmentObject(syncManager)
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
