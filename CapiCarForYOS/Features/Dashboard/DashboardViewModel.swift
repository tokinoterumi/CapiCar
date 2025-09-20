import Foundation
import Combine

@MainActor
class DashboardViewModel: ObservableObject {
    
    // MARK: - Published Properties
    
    @Published var groupedTasks: GroupedTasks?
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    
    // MARK: - Dependencies

    private let apiService: APIService

    // MARK: - Initialization

    init(apiService: APIService? = nil) {
        self.apiService = apiService ?? APIService.shared
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
            // 2. Await the result directly from APIService
            let fetchedGroupedTasks = try await apiService.fetchDashboardTasks()

            // 3. On success, update the published property.
            self.groupedTasks = fetchedGroupedTasks

        } catch {
            // 4. On failure, capture a user-friendly error message.
            self.errorMessage = "Failed to load tasks. Please check your connection and try again."
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
                    createdAt: Date().ISO8601Format(),
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
                    createdAt: Date().ISO8601Format(),
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
    var taskSections: [(displayStatus: DisplayStatus, tasks: [FulfillmentTask])] {
        guard let groupedTasks = groupedTasks else { return [] }

        // Define simplified section order for better UX
        var sections: [(displayStatus: DisplayStatus, tasks: [FulfillmentTask])] = []

        // Map simplified groups to representative display status (for display purposes)
        let sectionMappings: [(DisplayStatus, [FulfillmentTask])] = [
            (.pending, groupedTasks.pending),
            (.picking, groupedTasks.picking),       // Contains picking + picked tasks
            (.packed, groupedTasks.packed),
            (.inspecting, groupedTasks.inspecting), // Contains inspecting + correction tasks
            (.completed, groupedTasks.completed),
            (.paused, groupedTasks.paused),         // Special section for paused tasks
            (.cancelled, groupedTasks.cancelled)
        ]

        for (displayStatus, tasks) in sectionMappings {
            if !tasks.isEmpty {
                sections.append((displayStatus: displayStatus, tasks: tasks))
            }
        }

        return sections
    }
}

