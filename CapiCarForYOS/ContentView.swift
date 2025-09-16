import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var authManager: AuthenticationManager
    @EnvironmentObject private var staffManager: StaffManager
    @State private var selectedTab: Tab = .dashboard
    
    enum Tab: String, CaseIterable {
        case dashboard = "Dashboard"
        case tasks = "Tasks"
        case staff = "Staff"
        
        var iconName: String {
            switch self {
            case .dashboard: return "chart.bar.fill"
            case .tasks: return "list.clipboard.fill"
            case .staff: return "person.2.fill"
            }
        }
    }
    
    var body: some View {
        TabView(selection: $selectedTab) {
            // Dashboard Tab
            NavigationStack {
                DashboardView()
            }
            .tabItem {
                Image(systemName: Tab.dashboard.iconName)
                Text(Tab.dashboard.rawValue)
            }
            .tag(Tab.dashboard)
            
            // Tasks Tab - Individual task management
            NavigationStack {
                TasksListView()
            }
            .tabItem {
                Image(systemName: Tab.tasks.iconName)
                Text(Tab.tasks.rawValue)
            }
            .tag(Tab.tasks)
            
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
    }
}

// MARK: - Placeholder Views (to be implemented)

struct TasksListView: View {
    @StateObject private var viewModel = DashboardViewModel()
    @EnvironmentObject private var staffManager: StaffManager
    
    var body: some View {
        List {
            if viewModel.isLoading {
                HStack {
                    ProgressView()
                        .progressViewStyle(.circular)
                    Text("Loading tasks...")
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .listRowBackground(Color.clear)
            } else if let errorMessage = viewModel.errorMessage {
                VStack(spacing: 16) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.largeTitle)
                        .foregroundColor(.red)
                    Text("Error loading tasks")
                        .font(.headline)
                    Text(errorMessage)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                    
                    PrimaryButton(title: "Retry") {
                        Task {
                            await viewModel.fetchDashboardData()
                        }
                    }
                }
                .listRowBackground(Color.clear)
            } else {
                ForEach(allTasks, id: \.id) { task in
                    NavigationLink(destination: TaskDetailView(task: task, currentOperator: staffManager.currentOperator)) {
                        TaskRowView(task: task)
                    }
                }
            }
        }
        .navigationTitle("All Tasks")
        .refreshable {
            await viewModel.fetchDashboardData()
        }
        .onAppear {
            Task {
                await viewModel.fetchDashboardData()
            }
        }
    }
    
    private var allTasks: [FulfillmentTask] {
        viewModel.taskSections.flatMap { $0.tasks }
    }
}

struct TaskRowView: View {
    let task: FulfillmentTask
    
    var body: some View {
        HStack(spacing: 12) {
            // Status indicator
            Circle()
                .fill(statusColor)
                .frame(width: 12, height: 12)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(task.orderName)
                    .font(.headline)
                    .foregroundColor(.primary)
                
                Text(task.shippingName)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                HStack {
                    Text(task.status.rawValue)
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(statusColor)
                    
                    if let currentOperator = task.currentOperator {
                        Text("• \(currentOperator.name)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            Spacer()
            
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
    }
    
    private var statusColor: Color {
        switch task.status {
        case .pending: return .orange
        case .picking: return .blue
        case .picked: return .cyan
        case .packed: return .purple
        case .inspecting: return .yellow
        case .correctionNeeded: return .red
        case .correcting: return .pink
        case .completed: return .green
        case .paused: return .gray
        case .cancelled: return .red
        }
    }
}

struct StaffManagementView: View {
    var body: some View {
        StaffCheckInView()
            .navigationTitle("Staff")
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
