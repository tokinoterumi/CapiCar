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
    
    init(apiService: APIService = APIService()) {
        self.apiService = apiService
    }
    
    // MARK: - Public Methods
    
    /// Fetches all the necessary data for the dashboard from the backend API.
    func fetchDashboardData() async {
        // 1. Set initial state.
        self.isLoading = true
        self.errorMessage = nil
        
        do {
            // 2. Await the result directly. No need for an extra Task block.
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
    
    // MARK: - Computed Properties for the View
    
    /// Provides an ordered array of task sections for the View to iterate over.
    var taskSections: [(status: TaskStatus, tasks: [FulfillmentTask])] {
        guard let groupedTasks = groupedTasks else { return [] }
        
        // Define the order in which sections should appear on the dashboard.
        let sectionOrder: [TaskStatus] = [.picking, .pending, .packed, .inspecting, .paused, .completed, .cancelled]
        
        var sections: [(status: TaskStatus, tasks: [FulfillmentTask])] = []
        
        let tasksByStatus: [TaskStatus: [FulfillmentTask]] = [
            .pending: groupedTasks.pending,
            .picking: groupedTasks.picking,
            .packed: groupedTasks.packed,
            .inspecting: groupedTasks.inspecting,
            .completed: groupedTasks.completed,
            .cancelled: groupedTasks.cancelled,
            .paused: groupedTasks.paused
        ]
        
        for status in sectionOrder {
            if let tasks = tasksByStatus[status], !tasks.isEmpty {
                // Append the tuple with the correct `TaskStatus` type.
                sections.append((status: status, tasks: tasks))
            }
        }
        
        return sections
    }
}

