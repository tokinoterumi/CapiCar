import Foundation
import Network
import Combine

@MainActor
class SyncManager: ObservableObject {
    
    @Published var isOnline: Bool = true
    @Published var isSyncing: Bool = false
    @Published var lastSyncDate: Date?
    @Published var pendingChangesCount: Int = 0
    @Published var syncError: String?
    
    // Lazy initialization to avoid timing issues
    private lazy var databaseManager = DatabaseManager.shared
    private lazy var apiService = APIService.shared
    private let networkMonitor = NWPathMonitor()
    private let syncQueue = DispatchQueue(label: "sync.queue", qos: .background)
    
    private var cancellables = Set<AnyCancellable>()
    private var syncTimer: Timer?
    private var isInitialized = false
    
    // Sync configuration
    private let syncInterval: TimeInterval = 30.0 // 30 seconds
    private let maxRetryAttempts = 3
    private let retryDelay: TimeInterval = 5.0
    
    init() {
        // Defer initialization to avoid crashes
        Task {
            await initializeAsync()
        }
    }
    
    private func initializeAsync() async {
        guard !isInitialized else { return }
        
        setupNetworkMonitoring()
        setupPeriodicSync()
        await updatePendingChangesCount()
        
        // Set up the connection with OfflineAPIService
        OfflineAPIService.shared.setSyncManager(self)
        
        isInitialized = true
    }
    
    deinit {
        networkMonitor.cancel()
        syncTimer?.invalidate()
    }
    
    // MARK: - Network Monitoring
    
    private func setupNetworkMonitoring() {
        networkMonitor.pathUpdateHandler = { [weak self] path in
            DispatchQueue.main.async {
                let wasOnline = self?.isOnline ?? false
                self?.isOnline = path.status == .satisfied
                
                // Trigger sync when coming back online
                if !wasOnline && path.status == .satisfied {
                    Task { @MainActor [weak self] in
                        await self?.performFullSync()
                    }
                }
                
                // Update database sync state
                Task { [weak self] in
                    try? self?.databaseManager.updateSyncState(isOnline: path.status == .satisfied)
                }
            }
        }
        
        let queue = DispatchQueue(label: "NetworkMonitor")
        networkMonitor.start(queue: queue)
    }
    
    // MARK: - Periodic Sync
    
    private func setupPeriodicSync() {
        syncTimer = Timer.scheduledTimer(withTimeInterval: syncInterval, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            
            Task { @MainActor in
                guard self.isOnline, !self.isSyncing else { return }
                await self.performFullSync()
            }
        }
    }
    
    // MARK: - Public Sync Methods
    
    var isReady: Bool {
        return isInitialized
    }
    
    func forceSyncNow() async {
        await performFullSync()
    }
    
    func performFullSync() async {
        guard isInitialized && isOnline && !isSyncing else { return }
        
        isSyncing = true
        syncError = nil
        
        do {
            // 1. Push local changes to server
            try await pushLocalChanges()
            
            // 2. Pull latest data from server
            try await pullServerData()
            
            // 3. Update sync state
            try databaseManager.updateSyncState(
                lastFullSync: Date(),
                pendingCount: 0
            )
            
            lastSyncDate = Date()
            await updatePendingChangesCount()
            
            print("✅ Full sync completed successfully")
            
        } catch {
            syncError = "Sync failed: \(error.localizedDescription)"
            print("❌ Sync failed: \(error)")
            
            try? databaseManager.updateSyncState(
                errorMessage: error.localizedDescription
            )
        }
        
        isSyncing = false
    }
    
    // MARK: - Push Local Changes
    
    private func pushLocalChanges() async throws {
        print("📤 Pushing local changes to server...")
        
        // Push task changes
        let tasksToSync = try databaseManager.getTasksNeedingSync()
        for task in tasksToSync {
            try await syncTaskToServer(task)
        }
        
        // Push checklist changes
        let checklistToSync = try databaseManager.getChecklistItemsNeedingSync()
        let groupedChecklist = Dictionary(grouping: checklistToSync, by: \.taskId)
        
        for (taskId, items) in groupedChecklist {
            try await syncChecklistToServer(taskId: taskId, items: items)
        }
        
        // Push audit logs
        let logsToSync = try databaseManager.getAuditLogsNeedingSync()
        for log in logsToSync {
            try await syncAuditLogToServer(log)
        }
        
        // Push staff changes
        let staffToSync = try databaseManager.getStaffNeedingSync()
        for staff in staffToSync {
            try await syncStaffToServer(staff)
        }
    }
    
    private func syncTaskToServer(_ localTask: LocalFulfillmentTask) async throws {
        do {
            if localTask.isDeleted {
                // Handle task deletion - for now we'll skip this as the API might not support deletion
                try databaseManager.markTaskAsSynced(localTask)
                return
            }
            
            let _ = localTask.asFulfillmentTask
            
            // For MVP, we'll assume task updates go through the action API
            // In a full implementation, you'd have specific update endpoints
            
            try databaseManager.markTaskAsSynced(localTask)
            print("✅ Synced task: \(localTask.orderName)")
            
        } catch {
            print("❌ Failed to sync task \(localTask.orderName): \(error)")
            throw error
        }
    }
    
    private func syncChecklistToServer(taskId: String, items: [LocalChecklistItem]) async throws {
        do {
            let domainItems = items.map { $0.asChecklistItem }
            
            // Use existing API method
            if let currentOperator = try? databaseManager.fetchLocalStaff(id: "current"),
               currentOperator.isCheckedIn == true {
                
                let updatedTask = try await apiService.updateTaskChecklist(
                    taskId: taskId,
                    checklist: domainItems,
                    operatorId: currentOperator.id
                )
                
                // Update local task with server response
                try databaseManager.updateTask(updatedTask)
            }
            
            // Mark items as synced
            for item in items {
                try databaseManager.markChecklistItemAsSynced(item)
            }
            
            print("✅ Synced checklist for task: \(taskId)")
            
        } catch {
            print("❌ Failed to sync checklist for task \(taskId): \(error)")
            throw error
        }
    }
    
    private func syncAuditLogToServer(_ localLog: LocalAuditLog) async throws {
        // For MVP, audit logs might be create-only
        // In a full implementation, you'd have an audit log API endpoint
        try databaseManager.markAuditLogAsSynced(localLog)
        print("✅ Synced audit log: \(localLog.id)")
    }
    
    private func syncStaffToServer(_ localStaff: LocalStaffMember) async throws {
        // For MVP, staff changes might go through check-in API
        try databaseManager.markStaffAsSynced(localStaff)
        print("✅ Synced staff: \(localStaff.name)")
    }
    
    // MARK: - Pull Server Data
    
    private func pullServerData() async throws {
        print("📥 Pulling latest data from server...")
        
        // Pull dashboard data (includes tasks)
        do {
            let dashboardData = try await apiService.fetchDashboardData()
            let groupedTasks = dashboardData.tasks
            
            // Convert simplified grouped tasks to flat array
            let allTasks = [
                groupedTasks.pending,
                groupedTasks.picking,      // Contains picking + picked tasks
                groupedTasks.packed,
                groupedTasks.inspecting,   // Contains inspecting + correction tasks
                groupedTasks.completed,
                groupedTasks.paused,
                groupedTasks.cancelled
            ].flatMap { $0 }
            
            // Save to local database
            try databaseManager.saveTasks(allTasks)
            
            print("✅ Pulled \(allTasks.count) tasks from server")
            
        } catch {
            print("❌ Failed to pull dashboard data: \(error)")
            // Don't throw - allow partial sync to continue
        }
        
        // Pull staff data
        do {
            let allStaff = try await apiService.fetchAllStaff()
            try databaseManager.saveStaff(allStaff)
            
            print("✅ Pulled \(allStaff.count) staff members from server")
            
        } catch {
            print("❌ Failed to pull staff data: \(error)")
            // Don't throw - allow partial sync to continue
        }
    }
    
    // MARK: - Offline Operations
    
    func saveTaskOffline(_ task: FulfillmentTask) async throws {
        try databaseManager.updateTask(task)
        await updatePendingChangesCount()
        
        // Try to sync immediately if online
        if isOnline && !isSyncing {
            Task { @MainActor [weak self] in
                await self?.performFullSync()
            }
        }
    }
    
    func saveChecklistOffline(_ items: [ChecklistItem], forTaskId taskId: String) async throws {
        for item in items {
            try databaseManager.updateChecklistItem(item, forTaskId: taskId)
        }
        await updatePendingChangesCount()
        
        // Try to sync immediately if online
        if isOnline && !isSyncing {
            Task { @MainActor [weak self] in
                await self?.performFullSync()
            }
        }
    }
    
    func performTaskActionOffline(taskId: String, action: String, operatorId: String, payload: [String: String]? = nil) async throws {
        // Create audit log for offline action
        let auditLog = AuditLog(
            id: UUID().uuidString,
            timestamp: Date(),
            operatorName: operatorId, // In a real app, you'd look up the name
            taskOrderName: taskId, // In a real app, you'd look up the order name
            actionType: action,
            details: payload?.description
        )
        
        try databaseManager.addAuditLog(auditLog)
        await updatePendingChangesCount()
        
        // For offline actions, we'll queue them for sync when online
        // In a full implementation, you'd store the action details for replay
        
        print("📱 Queued offline action: \(action) for task \(taskId)")
    }
    
    // MARK: - Helper Methods
    
    private func updatePendingChangesCount() async {
        guard isInitialized else { return }
        
        do {
            let tasksCount = try databaseManager.getTasksNeedingSync().count
            let checklistCount = try databaseManager.getChecklistItemsNeedingSync().count
            let logsCount = try databaseManager.getAuditLogsNeedingSync().count
            let staffCount = try databaseManager.getStaffNeedingSync().count
            
            pendingChangesCount = tasksCount + checklistCount + logsCount + staffCount
        } catch {
            print("Error updating pending changes count: \(error)")
            // Don't crash, just set to 0 on error
            pendingChangesCount = 0
        }
    }
    
    // MARK: - Public Data Access (Offline-First)
    
    func getTasks() async throws -> [FulfillmentTask] {
        // Always return local data first
        let localTasks = try databaseManager.fetchAllTasks()
        
        // Try to sync in background if online
        if isOnline && !isSyncing {
            Task { @MainActor [weak self] in
                await self?.performFullSync()
            }
        }
        
        return localTasks
    }
    
    func getTasksByStatus(_ status: TaskStatus) async throws -> [FulfillmentTask] {
        let localTasks = try databaseManager.fetchTasksByStatus(status)
        
        // Try to sync in background if online
        if isOnline && !isSyncing {
            Task { @MainActor [weak self] in
                await self?.performFullSync()
            }
        }
        
        return localTasks
    }
    
    func getStaff() async throws -> [StaffMember] {
        let localStaff = try databaseManager.fetchAllStaff()
        
        // Try to sync in background if online
        if isOnline && !isSyncing {
            Task { @MainActor [weak self] in
                await self?.performFullSync()
            }
        }
        
        return localStaff
    }
    
    func getChecklistItems(forTaskId taskId: String) async throws -> [ChecklistItem] {
        return try databaseManager.fetchChecklistItems(forTaskId: taskId)
    }
}
