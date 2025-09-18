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

    // Shared task selection handler
    private func selectTask(_ task: FulfillmentTask) {
        print("🔍 ContentView: Selected task \(task.orderName)")
        selectedTask = task
        showingTaskPreview = true
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
                    showingFullWorkflow: $showingFullWorkflow
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
        .fullScreenCover(isPresented: $showingFullWorkflow) {
            if let task = selectedTask {
                ZStack(alignment: .topLeading) {
                    NavigationView {
                        TaskDetailView(
                            task: task,
                            currentOperator: staffManager.currentOperator
                        )
                        .navigationBarHidden(true)
                    }

                    VStack {
                        HStack {
                            Button("Close") {
                                showingFullWorkflow = false
                            }
                            .padding()
                            .background(Color(.systemBackground))
                            .clipShape(Circle())
                            .shadow(radius: 2)

                            Spacer()
                        }
                        Spacer()
                    }
                    .padding()
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
