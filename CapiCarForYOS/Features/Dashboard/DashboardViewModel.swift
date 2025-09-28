import Foundation
import Combine

@MainActor
class DashboardViewModel: ObservableObject {

    // MARK: - Published Properties

    @Published var groupedTasks: GroupedTasks?
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?

    // MARK: - Smart Loading State Management

    @Published private(set) var hasLoadedInitialData: Bool = false
    @Published private(set) var lastRefreshTime: Date?
    @Published private(set) var dataChangesPending: Bool = false

    // MARK: - Dependencies

    private let offlineAPIService = OfflineAPIService.shared

    // MARK: - Request Deduplication & Smart Refresh

    private var currentFetchTask: Task<Void, Never>?
    private var lastFetchTime: Date = .distantPast
    private let throttleInterval: TimeInterval = 2.0 // Minimum 2 seconds between requests
    private let staleDataThreshold: TimeInterval = 30.0 // Data considered stale after 30 seconds

    // MARK: - Initialization

    init(apiService: APIService? = nil) {
        // Keep parameter for compatibility, but use OfflineAPIService

        // Listen for task data changes from OfflineAPIService
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("TaskDataChanged"),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor in
                self?.markDataChangesPending()
                // Force refresh dashboard data after task changes
                await self?.forceFetchDashboardData()
            }
        }

        // Listen for network connectivity changes to refresh data
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("NetworkStatusChanged"),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor in
                print("🔗 DASHBOARD: Network status changed, refreshing dashboard data")
                await self?.forceFetchDashboardData()
            }
        }
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    // MARK: - Public Methods
    
    /// Fetches all the necessary data for the dashboard from the backend API.
    func fetchDashboardData() async {
        // Throttle requests - prevent too frequent API calls
        let now = Date()
        let timeSinceLastFetch = now.timeIntervalSince(lastFetchTime)

        if timeSinceLastFetch < throttleInterval {
            print("🚦 THROTTLE: Dashboard fetch throttled (last fetch \(String(format: "%.1f", timeSinceLastFetch))s ago)")
            return
        }

        // Cancel any existing fetch task to prevent multiple simultaneous requests
        currentFetchTask?.cancel()

        currentFetchTask = Task {
            // Update last fetch time
            self.lastFetchTime = Date()
            // 1. Set initial state.
            self.isLoading = true
            self.errorMessage = nil

            do {
                // 2. Await the result from OfflineAPIService
                let fetchedGroupedTasks = try await offlineAPIService.fetchDashboardTasks()

                // Check if task was cancelled
                if Task.isCancelled { return }

                print("🔥 VIEWMODEL: Successfully received grouped tasks from OfflineAPIService")
                print("🔥 VIEWMODEL: - Pending: \(fetchedGroupedTasks.pending.count)")
                print("🔥 VIEWMODEL: - Picking: \(fetchedGroupedTasks.picking.count)")
                print("🔥 VIEWMODEL: - Packed: \(fetchedGroupedTasks.packed.count)")
                print("🔥 VIEWMODEL: - Inspecting: \(fetchedGroupedTasks.inspecting.count)")
                print("🔥 VIEWMODEL: - Completed: \(fetchedGroupedTasks.completed.count)")
                print("🔥 VIEWMODEL: - Paused: \(fetchedGroupedTasks.paused.count)")
                print("🔥 VIEWMODEL: - Cancelled: \(fetchedGroupedTasks.cancelled.count)")

                // 3. On success, update the published property and smart loading states.
                self.groupedTasks = fetchedGroupedTasks
                self.hasLoadedInitialData = true
                self.lastRefreshTime = Date()
                self.clearDataChangesPending()
                print("🔥 VIEWMODEL: Updated groupedTasks property and smart loading states")

            } catch {
                // Check if task was cancelled
                if Task.isCancelled { return }

                // 4. On failure, capture a user-friendly error message.
                self.errorMessage = "Failed to load tasks. Please check your connection and try again."
                print("Error fetching dashboard data: \(error)")
            }

            // 5. Ensure isLoading is set to false once the operation completes.
            self.isLoading = false
        }

        await currentFetchTask?.value
    }

    /// Force refresh dashboard data, bypassing throttling (for explicit user actions)
    func forceFetchDashboardData() async {
        // Test connectivity first to ensure SyncStatusWidget shows correct status
        await SyncManager.shared.testConnectivity()

        lastFetchTime = .distantPast // Reset throttle
        await fetchDashboardData()
    }

    /// Smart refresh that only fetches when actually needed
    func fetchDashboardDataIfNeeded(force: Bool = false) async {
        // Determine if we need to fetch
        let shouldFetch = force || shouldRefreshData()

        if shouldFetch {
            await fetchDashboardData()
        }
    }

    /// Check if data should be refreshed based on various conditions
    private func shouldRefreshData() -> Bool {
        // Always refresh if we've never loaded data
        guard hasLoadedInitialData else {
            print("📋 REFRESH CHECK: Initial load needed")
            return true
        }

        // Check if data is stale
        if let lastRefresh = lastRefreshTime {
            let timeSinceRefresh = Date().timeIntervalSince(lastRefresh)
            if timeSinceRefresh > staleDataThreshold {
                print("📋 REFRESH CHECK: Data is stale (\(String(format: "%.1f", timeSinceRefresh))s old)")
                return true
            }
        }

        // Check if there are pending changes that might affect display
        if dataChangesPending {
            print("📋 REFRESH CHECK: Data changes pending")
            return true
        }

        // Don't refresh if data is fresh
        return false
    }

    /// Mark that data changes are pending (e.g., after task updates)
    func markDataChangesPending() {
        dataChangesPending = true
        print("📋 DATA CHANGES: Marked as pending")
    }

    /// Clear pending changes flag (called after successful refresh)
    private func clearDataChangesPending() {
        dataChangesPending = false
        print("📋 DATA CHANGES: Cleared pending flag")
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

    // MARK: - Debug Methods (Development Only)

    /// Clear all local data and refresh dashboard - USE WITH CAUTION!
    func clearAllLocalData() async {
        do {
            print("🧹 DASHBOARD: Clearing all local data...")
            try DatabaseManager.shared.clearAllLocalData()
            print("🧹 DASHBOARD: Successfully cleared local data, refreshing...")

            // Clear current dashboard data
            groupedTasks = nil
            hasLoadedInitialData = false

            // Force refresh from server
            await forceFetchDashboardData()
        } catch {
            print("❌ DASHBOARD: Failed to clear local data: \(error)")
            errorMessage = "Failed to clear local data: \(error.localizedDescription)"
        }
    }
}

