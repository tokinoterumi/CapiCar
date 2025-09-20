import Foundation

@MainActor
class OfflineAPIService {
    static let shared = OfflineAPIService()
    
    private let apiService = APIService.shared
    private lazy var databaseManager = DatabaseManager.shared
    private var syncManager: SyncManager?
    
    init() {}
    
    func setSyncManager(_ manager: SyncManager) {
        self.syncManager = manager
    }
    
    // MARK: - Dashboard API (Offline-First)
    
    func fetchDashboardData() async throws -> DashboardData {
        // Try local first
        let localTasks = try databaseManager.fetchAllTasks()

        // If no local data and we're online, fetch from API
        if localTasks.isEmpty && syncManager?.isOnline == true {
            print("📡 No local tasks found, fetching from API...")
            let freshData = try await apiService.fetchDashboardData()

            // Save tasks to local database for future offline access
            let allTasks = [
                freshData.tasks.pending,
                freshData.tasks.picking,
                freshData.tasks.packed,
                freshData.tasks.inspecting,
                freshData.tasks.completed,
                freshData.tasks.paused,
                freshData.tasks.cancelled
            ].flatMap { $0 }

            try databaseManager.saveTasks(allTasks)

            return freshData
        }

        // Convert local tasks to simplified grouped format (matching backend transformation)
        let pendingTasks = localTasks.filter { $0.status == .pending && $0.isPaused != true }
        let pickingTasks = localTasks.filter { ($0.status == .picking || $0.status == .picked) && $0.isPaused != true }
        let packedTasks = localTasks.filter { $0.status == .packed && $0.isPaused != true }
        let inspectingTasks = localTasks.filter {
            ($0.status == .inspecting || $0.status == .correctionNeeded || $0.status == .correcting) && $0.isPaused != true
        }
        let completedTasks = localTasks.filter { $0.status == .completed }
        let pausedTasks = localTasks.filter { $0.isPaused == true }
        let cancelledTasks = localTasks.filter { $0.status == .cancelled }

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
            lastUpdated: syncManager?.lastSyncDate?.ISO8601Format() ?? "Never"
        )

        // Trigger background sync if online
        if let syncManager = syncManager, syncManager.isOnline && !syncManager.isSyncing {
            Task {
                await syncManager.performFullSync()
            }
        }

        return dashboardData
    }
    
    func fetchDashboardTasks() async throws -> GroupedTasks {
        let dashboardData = try await fetchDashboardData()
        return dashboardData.tasks
    }
    
    // MARK: - Task API (Offline-First)
    
    func fetchTask(id: String) async throws -> FulfillmentTask {
        // Try local first
        if let localTask = try databaseManager.fetchLocalTask(id: id) {
            let task = localTask.asFulfillmentTask
            
            // Try to fetch fresh data in background if online
            if syncManager?.isOnline == true {
                Task {
                    do {
                        let freshTask = try await apiService.fetchTask(id: id)
                        try databaseManager.updateTask(freshTask)
                    } catch {
                        print("Background fetch failed: \(error)")
                    }
                }
            }
            
            return task
        }
        
        // If not in local database and online, fetch from server
        if syncManager?.isOnline == true {
            let task = try await apiService.fetchTask(id: id)
            try databaseManager.updateTask(task)
            return task
        }
        
        throw APIError.serverError(message: "Task not found locally and device is offline")
    }
    
    func performTaskAction(
        taskId: String,
        action: TaskAction,
        operatorId: String,
        payload: [String: String]? = nil
    ) async throws -> FulfillmentTask {
        
        if syncManager?.isOnline == true {
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
            task.status = .picking
            
        case .completePicking:
            task.status = .picked
            
        case .startPacking:
            task.status = .packed
            
        case .startInspection:
            task.status = .inspecting
            
        case .completeInspection:
            task.status = .completed
            
        case .enterCorrection:
            task.status = .correctionNeeded
            
        case .startCorrection:
            task.status = .correcting
            
        case .resolveCorrection:
            task.status = .packed // Return to packed after correction
            
        case .reportException:
            task.status = .cancelled

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
            task.status = .cancelled
        }
        
        // Update current operator
        if let staffMember = try? databaseManager.fetchLocalStaff(id: operatorId) {
            task.currentOperator = staffMember.asStaffMember
        }
        
        // Save optimistic update
        try databaseManager.updateTask(task)
        
        // Queue the action for sync
        try await syncManager?.performTaskActionOffline(
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
        
        if syncManager?.isOnline == true {
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
                try await syncManager?.saveChecklistOffline(checklist, forTaskId: taskId)
            }
        } else {
            // Queue for sync when online
            try await syncManager?.saveChecklistOffline(checklist, forTaskId: taskId)
        }
        
        // Return current task state
        guard let localTask = try databaseManager.fetchLocalTask(id: taskId) else {
            throw APIError.serverError(message: "Task not found locally")
        }
        
        return localTask.asFulfillmentTask
    }
    
    // MARK: - Staff API (Offline-First)
    
    func fetchAllStaff() async throws -> [StaffMember] {
        // Always return local data
        let localStaff = try databaseManager.fetchAllStaff()
        
        // Try to sync in background if online
        if let syncManager = syncManager, syncManager.isOnline && !syncManager.isSyncing {
            Task {
                do {
                    let freshStaff = try await apiService.fetchAllStaff()
                    try databaseManager.saveStaff(freshStaff)
                } catch {
                    print("Background staff sync failed: \(error)")
                }
            }
        }
        
        return localStaff
    }
    
    func checkInStaff(staffId: String, action: CheckInAction) async throws -> CheckInResult {
        
        if syncManager?.isOnline == true {
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
    
    // MARK: - Sync Status
    
    var isOnline: Bool {
        syncManager?.isOnline ?? false
    }
    
    var isSyncing: Bool {
        syncManager?.isSyncing ?? false
    }
    
    var pendingChangesCount: Int {
        syncManager?.pendingChangesCount ?? 0
    }
    
    var lastSyncDate: Date? {
        syncManager?.lastSyncDate
    }
    
    var syncError: String? {
        syncManager?.syncError
    }
    
    func forceSyncNow() async {
        await syncManager?.forceSyncNow()
    }
}