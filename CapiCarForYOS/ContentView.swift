import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var authManager: AuthenticationManager
    @EnvironmentObject private var staffManager: StaffManager
    @State private var selectedTab: Tab = .dashboard
    @StateObject private var dashboardViewModel = DashboardViewModel()

    // Centralized sheet presentation state
    @State private var selectedTask: FulfillmentTask?
    @State private var showingTaskPreview = false
    @State private var showingFullWorkflow = false
    @State private var showingInspectionView = false

    // Shared task selection handler
    private func selectTask(_ task: FulfillmentTask) {
        print("🔍 ContentView: Selected task \(task.orderName)")

        // Always fetch fresh task data to avoid stale status
        if let freshTask = findFreshTask(taskId: task.id) {
            selectedTask = freshTask
            print("🔍 ContentView: Using fresh task data with status \(freshTask.status)")
        } else {
            selectedTask = task
            print("🔍 ContentView: Using passed task data with status \(task.status)")
        }

        showingTaskPreview = true
    }

    // Helper to find fresh task data from the dashboard
    private func findFreshTask(taskId: String) -> FulfillmentTask? {
        guard let groupedTasks = dashboardViewModel.groupedTasks else {
            return nil
        }

        let allTasks = [
            groupedTasks.pending,
            groupedTasks.picking,        // contains picking + picked
            groupedTasks.packed,
            groupedTasks.inspecting,     // contains inspecting + correctionNeeded + correcting
            groupedTasks.completed,
            groupedTasks.paused,
            groupedTasks.cancelled
        ].flatMap { $0 }

        return allTasks.first { $0.id == taskId }
    }
    
    enum Tab: String, CaseIterable {
        case dashboard = "Dashboard"
        case staff = "Staff"

        var iconName: String {
            switch self {
            case .dashboard: return "chart.bar.fill"
            case .staff: return "person.2.fill"
            }
        }
    }
    
    var body: some View {
        TabView(selection: $selectedTab) {
            // Dashboard Tab
            NavigationStack {
                DashboardView(onTaskSelected: selectTask)
                    .environmentObject(dashboardViewModel)
            }
            .tabItem {
                Image(systemName: Tab.dashboard.iconName)
                Text(Tab.dashboard.rawValue)
            }
            .tag(Tab.dashboard)

            // Staff Tab - Staff management and check-in
            NavigationStack {
                StaffManagementView()
            }
            .tabItem {
                Image(systemName: Tab.staff.iconName)
                Text(Tab.staff.rawValue)
            }
            .tag(Tab.staff)
        }
        .accentColor(.blue)
        // Centralized sheet presentations
        .sheet(isPresented: $showingTaskPreview) {
            if let task = selectedTask {
                TaskPreviewSheet(
                    task: task,
                    showingFullWorkflow: $showingFullWorkflow,
                    showingInspectionView: $showingInspectionView
                )
                .environmentObject(staffManager)
                .onAppear {
                    print("🔍 TaskPreviewSheet: onAppear called for \(task.orderName)")
                }
                .onDisappear {
                    print("🔍 TaskPreviewSheet: onDisappear called")
                }
            } else {
                Text("No task selected")
                    .onAppear {
                        print("🔍 ContentView: selectedTask is nil in sheet!")
                    }
            }
        }
        .fullScreenCover(isPresented: $showingFullWorkflow, onDismiss: {
            // Refresh dashboard data when TaskDetailView is dismissed
            Task {
                await dashboardViewModel.fetchDashboardData()
            }
            // Also dismiss the preview sheet since task status has likely changed
            showingTaskPreview = false
        }) {
            if let task = selectedTask {
                NavigationStack {
                    TaskDetailView(
                        task: task,
                        currentOperator: staffManager.currentOperator
                    )
                }
            }
        }
        // InspectionView sheet presentation
        .sheet(isPresented: $showingInspectionView) {
            if let task = selectedTask {
                InspectionView(
                    task: task,
                    currentOperator: staffManager.currentOperator
                )
                .onDisappear {
                    // Refresh dashboard data when InspectionView is dismissed
                    Task {
                        await dashboardViewModel.fetchDashboardData()
                    }
                    // Clear selected task to prevent stale data in TaskPreviewSheet
                    selectedTask = nil
                }
            }
        }
    }
}

// MARK: - Staff Management View

struct StaffManagementView: View {
    var body: some View {
        List {
            Section("Staff Check-In") {
                StaffCheckInView()
            }
            .listRowInsets(EdgeInsets())

            Section("Network Settings") {
                NetworkSettingsView()
            }
            .listRowInsets(EdgeInsets())
        }
        .navigationTitle("Staff & Settings")
    }
}

// MARK: - Preview
#Preview {
    let mockAuthManager = AuthenticationManager()
    let mockStaffManager = StaffManager()
    let mockSyncManager = SyncManager()
    
    return ContentView()
        .environmentObject(mockAuthManager)
        .environmentObject(mockStaffManager)
        .environmentObject(mockSyncManager)
}
