import Foundation
import Combine

@MainActor
class DashboardViewModel: ObservableObject {
    
    // MARK: - Published Properties
    
    @Published var groupedTasks: GroupedTasks?
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    
    // MARK: - Dependencies
    
    private let offlineAPIService: OfflineAPIService
    
    // MARK: - Initialization
    
    init(offlineAPIService: OfflineAPIService? = nil) {
        self.offlineAPIService = offlineAPIService ?? OfflineAPIService.shared
    }
    
    // MARK: - Public Methods
    
    /// Fetches all the necessary data for the dashboard from the backend API.
    func fetchDashboardData() async {
        // Skip API call in preview/debug context
        #if DEBUG
        if ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1" {
            // Provide mock data for previews
            await loadMockData()
            return
        }
        #endif
        
        // 1. Set initial state.
        self.isLoading = true
        self.errorMessage = nil
        
        do {
            // 2. Await the result directly using offline-first service
            let fetchedGroupedTasks = try await offlineAPIService.fetchDashboardTasks()
            
            // 3. On success, update the published property.
            self.groupedTasks = fetchedGroupedTasks
            
        } catch {
            // 4. On failure, capture a user-friendly error message.
            let isOnline = offlineAPIService.isOnline
            self.errorMessage = isOnline 
                ? "Failed to load tasks. Please check your connection and try again."
                : "Working offline. Some data may be outdated."
            print("Error fetching dashboard data: \(error)")
        }
        
        // 5. Ensure isLoading is set to false once the operation completes.
        self.isLoading = false
    }
    
    #if DEBUG
    private func loadMockData() async {
        self.isLoading = true
        self.errorMessage = nil
        
        // Simulate network delay
        try? await Task.sleep(for: .milliseconds(500))
        
        // Mock grouped tasks (simplified structure)
        self.groupedTasks = GroupedTasks(
            pending: [
                FulfillmentTask(
                    id: "mock1",
                    orderName: "#1001",
                    status: .pending,
                    shippingName: "John Doe",
                    createdAt: Date(),
                    checklistJson: "[]",
                    currentOperator: nil
                )
            ],
            picking: [
                FulfillmentTask(
                    id: "mock2",
                    orderName: "#1002",
                    status: .picking,
                    shippingName: "Jane Smith",
                    createdAt: Date(),
                    checklistJson: "[]",
                    currentOperator: StaffMember(id: "s1", name: "Mike")
                )
            ],
            packed: [],
            inspecting: [],
            completed: [],
            paused: [],
            cancelled: []
        )
        
        self.isLoading = false
    }
    #endif
    
    // MARK: - Computed Properties for the View
    
    /// Provides an ordered array of simplified task sections for the View to iterate over.
    /// Maps simplified groups to display-friendly status labels.
    var taskSections: [(status: TaskStatus, tasks: [FulfillmentTask])] {
        guard let groupedTasks = groupedTasks else { return [] }
        
        // Define simplified section order for better UX
        var sections: [(status: TaskStatus, tasks: [FulfillmentTask])] = []
        
        // Map simplified groups to representative status (for display purposes)
        let sectionMappings: [(TaskStatus, [FulfillmentTask])] = [
            (.pending, groupedTasks.pending),
            (.picking, groupedTasks.picking),       // Contains picking + picked tasks
            (.packed, groupedTasks.packed),
            (.inspecting, groupedTasks.inspecting), // Contains inspecting + correction tasks
            (.completed, groupedTasks.completed),
            (.paused, groupedTasks.paused),
            (.cancelled, groupedTasks.cancelled)
        ]
        
        for (status, tasks) in sectionMappings {
            if !tasks.isEmpty {
                sections.append((status: status, tasks: tasks))
            }
        }
        
        return sections
    }
}

