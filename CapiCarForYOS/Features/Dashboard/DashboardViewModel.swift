import Foundation
import Combine

@MainActor
class DashboardViewModel: ObservableObject {
    
    // MARK: - Published Properties
    
    @Published var groupedTasks: GroupedTasks?
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    
    // MARK: - Dependencies

    private let offlineAPIService = OfflineAPIService.shared

    // MARK: - Initialization

    init(apiService: APIService? = nil) {
        // Keep parameter for compatibility, but use OfflineAPIService
    }
    
    // MARK: - Public Methods
    
    /// Fetches all the necessary data for the dashboard from the backend API.
    func fetchDashboardData() async {


        // 1. Set initial state.
        self.isLoading = true
        self.errorMessage = nil
        
        do {
            // 2. Await the result from OfflineAPIService
            let fetchedGroupedTasks = try await offlineAPIService.fetchDashboardTasks()
            print("🔥 VIEWMODEL: Successfully received grouped tasks from OfflineAPIService")
            print("🔥 VIEWMODEL: - Pending: \(fetchedGroupedTasks.pending.count)")
            print("🔥 VIEWMODEL: - Picking: \(fetchedGroupedTasks.picking.count)")
            print("🔥 VIEWMODEL: - Packed: \(fetchedGroupedTasks.packed.count)")
            print("🔥 VIEWMODEL: - Inspecting: \(fetchedGroupedTasks.inspecting.count)")
            print("🔥 VIEWMODEL: - Completed: \(fetchedGroupedTasks.completed.count)")
            print("🔥 VIEWMODEL: - Paused: \(fetchedGroupedTasks.paused.count)")
            print("🔥 VIEWMODEL: - Cancelled: \(fetchedGroupedTasks.cancelled.count)")

            // 3. On success, update the published property.
            self.groupedTasks = fetchedGroupedTasks
            print("🔥 VIEWMODEL: Updated groupedTasks property")

        } catch {
            // 4. On failure, capture a user-friendly error message.
            self.errorMessage = "Failed to load tasks. Please check your connection and try again."
            print("Error fetching dashboard data: \(error)")
        }
        
        // 5. Ensure isLoading is set to false once the operation completes.
        self.isLoading = false
    }
    
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

