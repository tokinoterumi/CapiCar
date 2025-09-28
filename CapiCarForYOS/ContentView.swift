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
    @State private var showingCorrectionFlow = false
    @State private var hasPerformedInitialLoad = false

    // Shared task selection handler
    private func selectTask(_ task: FulfillmentTask) {
        print("🔍 ContentView: Selected task \(task.orderName)")

        // Use the passed task directly to avoid timing issues with dashboard updates
        // The TaskPreviewSheet will fetch fresh data internally
        selectedTask = task
        print("🔍 ContentView: selectedTask set to: \(task.orderName)")

        // Use DispatchQueue to ensure state updates don't conflict
        DispatchQueue.main.async {
            self.showingTaskPreview = true
            print("🔍 ContentView: showingTaskPreview set to true")
        }
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
        VStack(spacing: 0) {
            // Staff selector at the top of all screens
            StaffSelector()
                .environmentObject(staffManager)
                .environmentObject(dashboardViewModel)

            // Tab content below
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

                // Staff Tab - Staff management
                NavigationStack {
                    StaffManagementView()
                }
                .tabItem {
                    Image(systemName: Tab.staff.iconName)
                    Text(Tab.staff.rawValue)
                }
                .tag(Tab.staff)
            }
        }
        .accentColor(.blue)
        .onAppear {
            // Only perform initial load once when ContentView first appears
            if !hasPerformedInitialLoad {
                hasPerformedInitialLoad = true
                Task {
                    // Load both staff and dashboard data on first app launch concurrently
                    await withTaskGroup(of: Void.self) { group in
                        group.addTask { await staffManager.fetchAvailableStaffIfNeeded() }
                        group.addTask { await dashboardViewModel.fetchDashboardDataIfNeeded() }
                    }
                }
            }
        }
        .onChange(of: selectedTask) { oldValue, newValue in
            print("🔍 ContentView: selectedTask changed from \(oldValue?.orderName ?? "nil") to \(newValue?.orderName ?? "nil")")
        }
        // Centralized sheet presentations
        .sheet(isPresented: $showingTaskPreview) {
            if let task = selectedTask {
                TaskPreviewSheet(
                    task: task,
                    showingFullWorkflow: $showingFullWorkflow,
                    showingInspectionView: $showingInspectionView,
                    showingCorrectionFlow: $showingCorrectionFlow
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
                        print("🔍 ContentView: showingTaskPreview = \(showingTaskPreview)")
                        print("🔍 ContentView: Dashboard groupedTasks available: \(dashboardViewModel.groupedTasks != nil)")
                    }
            }
        }
        .fullScreenCover(isPresented: $showingFullWorkflow, onDismiss: {
            // The notification system already handles the refresh, just clean up UI state
            // Clear selected task to force fresh data when TaskPreviewSheet is opened again
            selectedTask = nil
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
        // CorrectionFlowView sheet presentation
        .sheet(isPresented: $showingCorrectionFlow, onDismiss: {
            // Mark that data changes might be pending after correction flow
            dashboardViewModel.markDataChangesPending()
            // Clear selected task to prevent stale data in TaskPreviewSheet
            selectedTask = nil
        }) {
            if let task = selectedTask {
                CorrectionFlowView(
                    task: task,
                    currentOperator: staffManager.currentOperator
                )
                .onDisappear {
                    // Mark that data changes might be pending after correction
                    dashboardViewModel.markDataChangesPending()
                    // Clear selected task to prevent stale data in TaskPreviewSheet
                    selectedTask = nil
                }
            }
        }
        // InspectionView sheet presentation
        .fullScreenCover(isPresented: $showingInspectionView) {
            if let task = selectedTask {
                NavigationStack {
                    InspectionView(
                        task: task,
                        currentOperator: staffManager.currentOperator
                    )
                }
                .onDisappear {
                    // Mark that data changes might be pending after inspection
                    dashboardViewModel.markDataChangesPending()
                    // Clear selected task to prevent stale data in TaskPreviewSheet
                    selectedTask = nil
                }
            }
        }
    }
}

// MARK: - Preview
#Preview {
    let mockAuthManager = AuthenticationManager()
    let mockStaffManager = StaffManager()

    ContentView()
        .environmentObject(mockAuthManager)
        .environmentObject(mockStaffManager)
        .environmentObject(SyncManager.shared)
}
