import Foundation

@MainActor
class OfflineAPIService {
    static let shared = OfflineAPIService()
    
    private let apiService = APIService.shared
    private lazy var databaseManager = DatabaseManager.shared
    private let syncManager = SyncManager.shared
    private var suppressBackgroundSync = false

    init() {}

    func setSyncManager(_ manager: SyncManager) {
        // Deprecated: OfflineAPIService now uses SyncManager.shared directly
    }

    func suppressBackgroundSyncTemporarily() {
        suppressBackgroundSync = true
        // Auto-reset after 5 seconds to prevent permanent suppression
        Task {
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            suppressBackgroundSync = false
        }
    }
    
    // MARK: - Dashboard API (Offline-First)
    
    func fetchDashboardData() async throws -> DashboardData {
        // Always fetch fresh data when online to avoid stale cache issues
        print("🔥 CONNECTIVITY: syncManager.isOnline = \(syncManager.isOnline)")
        if syncManager.isOnline {
            do {
                let freshData = try await apiService.fetchDashboardData()
                print("🔥 DASHBOARD: Successfully fetched fresh data from API")
                print("🔥 DASHBOARD: Pending tasks: \(freshData.tasks.pending.count)")
                print("🔥 DASHBOARD: Paused tasks: \(freshData.tasks.paused.count)")
                print("🔥 DASHBOARD: Total tasks in response: \(freshData.stats.total)")

                // Save fresh tasks to local database for future offline access
                let allTasks = [
                    freshData.tasks.pending,
                    freshData.tasks.picking,
                    freshData.tasks.packed,
                    freshData.tasks.inspecting,
                    freshData.tasks.completed,
                    freshData.tasks.paused,
                    freshData.tasks.cancelled
                ].flatMap { $0 }

                print("🔥 DASHBOARD: Total tasks to save to local DB: \(allTasks.count)")
                try databaseManager.saveTasks(allTasks)
                print("🔥 DASHBOARD: Successfully saved tasks to local database")

                return freshData
            } catch {
                print("Failed to fetch fresh data, falling back to local cache: \(error)")
                // Fall through to use local cache if API fails
            }
        }

        // Use local cache only when offline or when API fails
        let localTasks = try databaseManager.fetchAllTasks()
        print("🔥 DASHBOARD: Using local cache - found \(localTasks.count) local tasks")

        // Convert local tasks to simplified grouped format (matching backend transformation)
        let pendingTasks = localTasks.filter { $0.status == TaskStatus.pending && $0.isPaused != true }
        let pickingTasks = localTasks.filter { ($0.status == TaskStatus.picking || $0.status == TaskStatus.picked) && $0.isPaused != true }
        let packedTasks = localTasks.filter { $0.status == TaskStatus.packed && $0.isPaused != true }
        let inspectingTasks = localTasks.filter {
            ($0.status == TaskStatus.inspecting || $0.status == TaskStatus.correctionNeeded || $0.status == TaskStatus.correcting) && $0.isPaused != true
        }
        let completedTasks = localTasks.filter { $0.status == TaskStatus.completed }
        let pausedTasks = localTasks.filter { $0.isPaused == true }
        let cancelledTasks = localTasks.filter { $0.status == TaskStatus.cancelled }

        print("🔥 DASHBOARD: Local task breakdown:")
        print("🔥 DASHBOARD: - Pending: \(pendingTasks.count)")
        print("🔥 DASHBOARD: - Picking: \(pickingTasks.count)")
        print("🔥 DASHBOARD: - Packed: \(packedTasks.count)")
        print("🔥 DASHBOARD: - Inspecting: \(inspectingTasks.count)")
        print("🔥 DASHBOARD: - Completed: \(completedTasks.count)")
        print("🔥 DASHBOARD: - Paused: \(pausedTasks.count)")
        print("🔥 DASHBOARD: - Cancelled: \(cancelledTasks.count)")

        let groupedTasks = GroupedTasks(
            pending: pendingTasks,
            picking: pickingTasks,
            packed: packedTasks,
            inspecting: inspectingTasks,
            completed: completedTasks,
            paused: pausedTasks,
            cancelled: cancelledTasks
        )

        // Create stats from simplified groups
        let stats = DashboardStats(
            pending: pendingTasks.count,
            picking: pickingTasks.count,
            packed: packedTasks.count,
            inspecting: inspectingTasks.count,
            completed: completedTasks.count,
            paused: pausedTasks.count,
            cancelled: cancelledTasks.count,
            total: localTasks.count
        )

        let dashboardData = DashboardData(
            tasks: groupedTasks,
            stats: stats,
            lastUpdated: syncManager.lastSyncDate?.ISO8601Format() ?? "Never"
        )

        // Dashboard fetch should not trigger background sync to prevent loops

        return dashboardData
    }
    
    func fetchDashboardTasks() async throws -> GroupedTasks {
        let dashboardData = try await fetchDashboardData()
        return dashboardData.tasks
    }
    
    // MARK: - Task API (Offline-First)
    
    func fetchTask(id: String) async throws -> FulfillmentTask {
        // If online, always fetch fresh data first
        if syncManager.isOnline {
            do {
                print("🔍 OfflineAPIService: Fetching fresh task from API for \(id)")
                let freshTask = try await apiService.fetchTask(id: id)
                try databaseManager.updateTask(freshTask)
                print("🔍 OfflineAPIService: Fresh task fetched and saved - status: \(freshTask.status)")
                return freshTask
            } catch {
                print("🔍 OfflineAPIService: API fetch failed, falling back to local: \(error)")
                // Fall back to local data if API fails
            }
        }

        // Use local data as fallback
        if let localTask = try databaseManager.fetchLocalTask(id: id) {
            print("🔍 OfflineAPIService: Using local task data - status: \(localTask.asFulfillmentTask.status)")
            return localTask.asFulfillmentTask
        }

        throw APIError.serverError(message: "Task not found locally and device is offline")
    }
    
    func performTaskAction(
        taskId: String,
        action: TaskAction,
        operatorId: String,
        payload: [String: String]? = nil
    ) async throws -> FulfillmentTask {
        
        if syncManager.isOnline {
            // Online: perform action and update local database
            do {
                let updatedTask = try await apiService.performTaskAction(
                    taskId: taskId,
                    action: action,
                    operatorId: operatorId,
                    payload: payload
                )
                
                try databaseManager.updateTask(updatedTask)
                return updatedTask
                
            } catch {
                // If online action fails, fall back to offline mode
                print("Online action failed, falling back to offline: \(error)")
                return try await performOfflineTaskAction(
                    taskId: taskId,
                    action: action,
                    operatorId: operatorId,
                    payload: payload
                )
            }
        } else {
            // Offline: queue action and return optimistic update
            return try await performOfflineTaskAction(
                taskId: taskId,
                action: action,
                operatorId: operatorId,
                payload: payload
            )
        }
    }
    
    private func performOfflineTaskAction(
        taskId: String,
        action: TaskAction,
        operatorId: String,
        payload: [String: String]? = nil
    ) async throws -> FulfillmentTask {
        
        // Get current task
        guard let localTask = try databaseManager.fetchLocalTask(id: taskId) else {
            throw APIError.serverError(message: "Task not found locally")
        }
        
        var task = localTask.asFulfillmentTask
        
        // Apply optimistic updates based on action
        switch action {
        case .startPicking:
            task.status = TaskStatus.picking

        case .completePicking:
            task.status = TaskStatus.picked

        case .startPacking:
            task.status = TaskStatus.packed

        case .startInspection:
            task.status = TaskStatus.inspecting

        case .completeInspection:
            task.status = TaskStatus.completed

        case .enterCorrection:
            task.status = TaskStatus.correctionNeeded

        case .startCorrection:
            task.status = TaskStatus.correcting

        case .resolveCorrection:
            task.status = TaskStatus.completed // Complete the task directly - no need for further inspection

        case .reportException:
            task.status = TaskStatus.cancelled

        case .pauseTask:
            task.isPaused = true
            task.currentOperator = nil

        case .resumeTask:
            task.isPaused = false
            // Assign resuming operator
            if let staffMember = try? databaseManager.fetchLocalStaff(id: operatorId) {
                task.currentOperator = staffMember.asStaffMember
            }

        case .cancelTask:
            task.status = TaskStatus.cancelled
        }
        
        // Update current operator
        if let staffMember = try? databaseManager.fetchLocalStaff(id: operatorId) {
            task.currentOperator = staffMember.asStaffMember
        }
        
        // Save optimistic update
        try databaseManager.updateTask(task)
        
        // Queue the action for sync
        try await syncManager.performTaskActionOffline(
            taskId: taskId,
            action: action.rawValue,
            operatorId: operatorId,
            payload: payload
        )
        
        return task
    }
    
    func updateTaskChecklist(
        taskId: String,
        checklist: [ChecklistItem],
        operatorId: String
    ) async throws -> FulfillmentTask {
        
        // Always update local database first
        try databaseManager.saveChecklistItems(checklist, forTaskId: taskId)
        
        if syncManager.isOnline {
            // Try to sync to server
            do {
                let updatedTask = try await apiService.updateTaskChecklist(
                    taskId: taskId,
                    checklist: checklist,
                    operatorId: operatorId
                )
                
                try databaseManager.updateTask(updatedTask)
                return updatedTask
                
            } catch {
                print("Checklist sync failed, will retry later: \(error)")
                // Mark for later sync
                try await syncManager.saveChecklistOffline(checklist, forTaskId: taskId)
            }
        } else {
            // Queue for sync when online
            try await syncManager.saveChecklistOffline(checklist, forTaskId: taskId)
        }
        
        // Return current task state
        guard let localTask = try databaseManager.fetchLocalTask(id: taskId) else {
            throw APIError.serverError(message: "Task not found locally")
        }
        
        return localTask.asFulfillmentTask
    }
    
    // MARK: - Staff API (Offline-First)
    
    func fetchAllStaff() async throws -> [StaffMember] {
        // For now, always try API first since we don't have local staff storage implemented
        do {
            let freshStaff = try await apiService.fetchAllStaff()
            print("✅ Successfully fetched \(freshStaff.count) staff members from API")

            // Try to save to local storage (currently a no-op)
            try databaseManager.saveStaff(freshStaff)
            return freshStaff
        } catch {
            print("❌ Failed to fetch staff data from API: \(error)")

            // Return local data as fallback (currently empty, but could have saved data)
            let localStaff = try databaseManager.fetchAllStaff()
            if localStaff.isEmpty {
                // If no local data and API failed, throw the original error
                throw error
            }
            return localStaff
        }
    }
    
    func checkInStaff(staffId: String, action: CheckInAction) async throws -> CheckInResult {
        
        if syncManager.isOnline {
            // Try online check-in
            do {
                let result = try await apiService.checkInStaff(staffId: staffId, action: action)
                
                // Update local database
                try databaseManager.updateStaffCheckInStatus(
                    staffId: staffId,
                    isCheckedIn: action == .checkIn
                )
                
                return result
                
            } catch {
                print("Online check-in failed: \(error)")
                // Fall through to offline handling
            }
        }
        
        // Offline check-in
        try databaseManager.updateStaffCheckInStatus(
            staffId: staffId,
            isCheckedIn: action == .checkIn
        )
        
        // Create optimistic result
        guard let localStaff = try databaseManager.fetchLocalStaff(id: staffId) else {
            throw APIError.serverError(message: "Staff member not found")
        }
        
        let result = CheckInResult(
            staff: localStaff.asStaffMember,
            action: action.rawValue,
            timestamp: Date().ISO8601Format(),
            message: "Checked \(action == .checkIn ? "in" : "out") offline"
        )
        
        // The sync manager will handle syncing this when online
        
        return result
    }

    func fetchTaskWorkHistory(taskId: String) async throws -> [WorkHistoryEntry] {
        // Try API first if online, fallback to empty for now
        // In a full implementation, we'd store audit logs locally too
        if syncManager.isOnline {
            do {
                return try await apiService.fetchTaskWorkHistory(taskId: taskId)
            } catch {
                print("Failed to fetch work history from API: \(error)")
                // Return empty array for offline mode
                return []
            }
        }

        // For offline mode, we don't have audit logs stored locally yet
        return []
    }

    // MARK: - Sync Status

    var isOnline: Bool {
        syncManager.isOnline
    }

    var isSyncing: Bool {
        syncManager.isSyncing
    }

    var pendingChangesCount: Int {
        syncManager.pendingChangesCount
    }

    var lastSyncDate: Date? {
        syncManager.lastSyncDate
    }

    var syncError: String? {
        syncManager.syncError
    }
    
    func forceSyncNow() async {
        await syncManager.forceSyncNow()
    }

    // MARK: - Cache Management

    func clearAllLocalData() throws {
        try databaseManager.clearAllData()
        print("✅ Cleared all local cache data")
    }

    // MARK: - Phase 2: Task Claiming (Online Transaction → Offline Ownership)

    /// Claims a pending task for the current operator and transfers ownership to the device
    /// This implements Phase 2 of the offline-sync strategy
    /// - Parameters:
    ///   - taskId: The ID of the pending task to claim
    ///   - operatorId: The ID of the operator claiming the task
    /// - Returns: The claimed task with full details for offline execution
    func claimTask(taskId: String, operatorId: String) async throws -> FulfillmentTask {
        // Must be online for task claiming (Phase 2 requirement)
        guard syncManager.isOnline else {
            throw APIError.serverError(message: "Must be online to claim tasks")
        }

        do {
            // 1. Atomic operation: claim task on server
            let claimedTask = try await apiService.performTaskAction(
                taskId: taskId,
                action: .startPicking,
                operatorId: operatorId,
                payload: nil
            )

            // 2. Transfer ownership to device: save to local database
            guard let staffMember = try? await getOperator(operatorId: operatorId) else {
                throw APIError.serverError(message: "Operator not found")
            }

            let localTask = LocalTask.fromFulfillmentTask(claimedTask, assignedTo: staffMember)
            try databaseManager.saveLocalTask(localTask)

            print("✅ Task \(taskId) claimed and transferred to device ownership")
            return claimedTask

        } catch {
            print("❌ Task claiming failed: \(error)")
            throw error
        }
    }

    /// Get operator details for task claiming
    private func getOperator(operatorId: String) async throws -> StaffMember {
        let allStaff = try await fetchAllStaff()
        guard let staffOperator = allStaff.first(where: { $0.id == operatorId }) else {
            throw APIError.serverError(message: "Operator \(operatorId) not found")
        }
        return staffOperator
    }

    // MARK: - Phase 3: Task Execution (Offline-First Operations)

    /// Pause task and queue for ownership transfer back to server
    /// This implements the Task Pausing Flow from the design principles
    func pauseTaskOffline(taskId: String) async throws {
        // Update local task to pausedPendingSync state
        try databaseManager.updateTaskSyncStatus(taskId: taskId, syncStatus: .pausedPendingSync)

        // Queue for sync when online (ownership transfer back to server)
        await syncManager.triggerSync()

        print("✅ Task \(taskId) paused offline - queued for ownership transfer back to server")
    }
}