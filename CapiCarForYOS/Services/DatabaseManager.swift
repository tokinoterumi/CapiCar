import Foundation
import SwiftData

/// 一個採用 MainActor 的單例，用於安全地與 SwiftData 資料庫互動。
/// 這是 Offline-First 策略的核心資料層，提供所有本地資料的 CRUD (創建、讀取、更新、刪除) 操作。
@MainActor
class DatabaseManager {
    /// 全局共享的單例實例。
    static let shared = DatabaseManager()

    /// SwiftData 的資料容器，管理 App 的資料模型。
    private var _modelContainer: ModelContainer?

    /// 主要的資料操作上下文，與主線程關聯。
    var mainContext: ModelContext {
        guard let container = _modelContainer else {
            fatalError("DatabaseManager not initialized with ModelContainer")
        }
        return container.mainContext
    }

    /// 私有化初始化方法，確保單例模式。
    private init() {
        // DatabaseManager will be initialized with the shared container from the app
    }

    /// Initialize with shared ModelContainer from the app
    func initialize(with container: ModelContainer) {
        self._modelContainer = container
    }

    // MARK: - Task Write Operations

    /// 從伺服器 API 回傳的資料創建並儲存一個本地任務。
    /// 這是 "領取任務" 流程的關鍵步驟。
    /// - Parameters:
    ///   - apiTask: 從伺服器獲取的 `FulfillmentTask` domain model。
    ///   - staff: 當前登入的作業人員。
    func saveTaskFromAPI(apiTask: FulfillmentTask, assignedTo staff: StaffMember) async throws {
        // 將 API model 轉換為本地資料庫 model
        let localTask = LocalTask(
            id: apiTask.id,
            name: apiTask.orderName,
            type: "Fulfillment", // 可根據需要擴展
            soNumber: apiTask.shippingName, // 假設 soNumber 對應 shippingName
            assignedStaffId: staff.id,
            assignedStaffName: staff.name,
            status: .picking,
            isPaused: false
        )
        
        // 將 JSON checklist 轉換為 LocalChecklistItem 物件
        if let checklistData = apiTask.checklistJson.data(using: .utf8) {
            let checklistItems = try JSONDecoder().decode([ChecklistItem].self, from: checklistData)
            localTask.checklistItems = checklistItems.map { apiItem in
                let localItem = LocalChecklistItem(
                    id: "\(apiTask.id)-\(apiItem.id)", // 確保 ID 唯一
                    itemName: apiItem.name,
                    sku: apiItem.sku,
                    barcode: apiItem.sku, // 假設 barcode 與 SKU 相同
                    quantity: apiItem.quantity_required,
                    status: .pending
                )
                localItem.task = localTask // 建立雙向關係
                return localItem
            }
        }
        
        mainContext.insert(localTask)
        try mainContext.save()
    }

    /// 更新指定任務的本地狀態。
    /// 用於「完成」、「取消」或「暫停」任務。
    /// - Parameters:
    ///   - taskId: 要更新的任務 ID。
    ///   - newStatus: 新的 `LocalTaskStatus`。
    func updateTaskStatus(taskId: String, newStatus: LocalTaskStatus) throws {
        guard let task = try fetchTask(withId: taskId) else {
            // 應處理任務不存在的情況
            print("錯誤：嘗試更新一個不存在的任務 (ID: \(taskId))")
            return
        }
        task.status = newStatus
        task.syncStatus = .pendingSync
        task.lastModifiedLocally = Date()
        
        try mainContext.save()
    }
    
    // MARK: - Checklist Item Write Operations

    /// 更新指定檢查清單項目的狀態。
    /// 這是作業員在執行任務時最頻繁的操作。
    /// - Parameters:
    ///   - itemId: 要更新的項目 ID。
    ///   - status: 新的 `LocalChecklistItemStatus`。
    ///   - scannedAt: 掃描或確認的時間。
    func updateChecklistItemStatus(itemId: String, status: LocalChecklistItemStatus, scannedAt: Date) throws {
        let predicate = #Predicate<LocalChecklistItem> { $0.id == itemId }
        var fetchDescriptor = FetchDescriptor<LocalChecklistItem>(predicate: predicate)
        fetchDescriptor.fetchLimit = 1

        if let itemToUpdate = try mainContext.fetch(fetchDescriptor).first {
            itemToUpdate.status = status
            itemToUpdate.scannedAt = scannedAt
            
            // 重要：當子項目變更時，必須將父任務標記為待同步。
            if let parentTask = itemToUpdate.task {
                parentTask.syncStatus = .pendingSync
                parentTask.lastModifiedLocally = Date()
            }
            
            try mainContext.save()
        }
    }
    
    // MARK: - Sync Operations
    
    /// 將一個任務的同步狀態標記為已成功同步。
    /// - Parameter taskId: 已成功同步的任務 ID。
    func markTaskAsSynced(taskId: String) throws {
        guard let task = try fetchTask(withId: taskId) else { return }
        task.syncStatus = .synced
        try mainContext.save()
    }
    
    /// 刪除一個已同步且已完成/取消/暫停的本地任務，以清理空間。
    /// - Parameter taskId: 要刪除的任務 ID。
    func deleteSyncedTask(taskId: String) throws {
        guard let task = try fetchTask(withId: taskId) else { return }
        mainContext.delete(task)
        try mainContext.save()
    }


    // MARK: - Read Operations

    /// 根據 ID 獲取一個特定的本地任務。
    /// - Parameter id: 任務的唯一識別碼。
    /// - Returns: 找到的 `LocalTask` 或 `nil`。
    func fetchTask(withId id: String) throws -> LocalTask? {
        let predicate = #Predicate<LocalTask> { $0.id == id }
        var fetchDescriptor = FetchDescriptor<LocalTask>(predicate: predicate)
        fetchDescriptor.fetchLimit = 1
        let results = try mainContext.fetch(fetchDescriptor)
        return results.first
    }
    
    /// 獲取指派給特定作業員且仍在進行中的任務。
    /// 用於 App 啟動時恢復作業員的當前工作。
    /// - Parameter staffId: 作業人員的 ID。
    /// - Returns: 找到的進行中的 `LocalTask` 或 `nil`。
    func fetchActiveTask(for staffId: String) throws -> LocalTask? {
        // Fetch all tasks for the staff member and filter manually
        let allTasksDescriptor = FetchDescriptor<LocalTask>()
        let allTasks = try mainContext.fetch(allTasksDescriptor)
        let filteredTasks = allTasks.filter { task in
            task.assignedStaffId == staffId && task.status == .picking
        }
        return filteredTasks.sorted { $0.lastModifiedLocally > $1.lastModifiedLocally }.first
    }
    
    /// 獲取所有需要同步到伺服器的任務。
    /// 這是 `SyncManager` 的核心數據來源。
    /// - Returns: 一個 `LocalTask` 陣列，其 `syncStatus` 為 `pendingSync` 或 `pausedPendingSync`。
    func fetchTasksPendingSync() throws -> [LocalTask] {
        // Fetch all tasks and filter manually
        let allTasksDescriptor = FetchDescriptor<LocalTask>()
        let allTasks = try mainContext.fetch(allTasksDescriptor)
        return allTasks.filter { task in
            task.syncStatus == .pendingSync ||
            task.syncStatus == .pausedPendingSync ||
            task.syncStatus == .awaitingServerAck
        }
    }
    
    /// (調試用) 獲取所有本地儲存的任務。
    func fetchAllLocalTasks() throws -> [LocalTask] {
        let descriptor = FetchDescriptor<LocalTask>()
        return try mainContext.fetch(descriptor)
    }

    // MARK: - Audit Log Management

    /// 獲取所有需要同步的審計日誌
    func fetchAuditLogsPendingSync() throws -> [LocalAuditLog] {
        let descriptor = FetchDescriptor<LocalAuditLog>()
        let allLogs = try mainContext.fetch(descriptor)
        return allLogs.filter { log in
            log.syncStatus == .pendingSync ||
            log.syncStatus == .pendingPrioritySync ||
            log.syncStatus == .awaitingServerAck
        }
    }

    /// 標記審計日誌為已同步
    func markAuditLogAsSynced(logId: String) throws {
        let descriptor = FetchDescriptor<LocalAuditLog>(
            predicate: #Predicate { $0.id == logId }
        )
        guard let auditLog = try mainContext.fetch(descriptor).first else {
            throw DatabaseError.taskNotFound(logId)
        }
        auditLog.syncStatus = .synced
        try mainContext.save()
    }

    /// 批量標記審計日誌為已同步
    func markAuditLogsAsSynced(logIds: [String]) throws {
        for logId in logIds {
            try markAuditLogAsSynced(logId: logId)
        }
    }

    // MARK: - Additional Methods for Offline-First Strategy

    /// Save a LocalTask instance directly to the database
    /// Used for task claiming (Phase 2) when transferring ownership to device
    func saveLocalTask(_ localTask: LocalTask) throws {
        mainContext.insert(localTask)
        try mainContext.save()
    }

    /// Update a task's sync status
    /// Used for marking tasks as paused pending sync
    func updateTaskSyncStatus(taskId: String, syncStatus: SyncStatus) throws {
        guard let task = try fetchTask(withId: taskId) else {
            throw DatabaseError.taskNotFound(taskId)
        }
        task.syncStatus = syncStatus
        task.lastModifiedLocally = Date()
        try mainContext.save()
    }

    /// Clear all data from the database
    /// Used for cache management
    func clearAllData() throws {
        // Delete all LocalTask instances (cascade will delete checklist items)
        let allTasks = try fetchAllLocalTasks()
        for task in allTasks {
            mainContext.delete(task)
        }
        try mainContext.save()
    }

    // MARK: - Additional Methods for OfflineAPIService Support

    /// Save multiple tasks from API response using Latest-data wins conflict resolution
    func saveTasks(_ tasks: [FulfillmentTask]) throws {
        print("🔥 DATABASE: Starting Latest-data wins merge for \(tasks.count) tasks")

        for serverTask in tasks {
            try saveTaskWithConflictResolution(serverTask)
        }

        print("🔥 DATABASE: Finished Latest-data wins merge for \(tasks.count) tasks")
    }

    /// Save a single task with operationSequence-based conflict resolution
    private func saveTaskWithConflictResolution(_ serverTask: FulfillmentTask) throws {
        let taskId = serverTask.id
        let serverSequence = serverTask.operationSequence ?? 0

        print("🔍 CONFLICT RESOLUTION: Processing task \(taskId) - server sequence: \(serverSequence)")

        // Try to find existing local task
        if let existingLocalTask = try fetchLocalTask(id: taskId) {
            let localSequence = existingLocalTask.operationSequence

            print("🔍 CONFLICT RESOLUTION: Found existing task \(taskId)")
            print("🔍 CONFLICT RESOLUTION: Local sequence: \(localSequence), Server sequence: \(serverSequence)")

            if serverSequence > localSequence {
                // Server data is newer - update local task
                print("✅ LATEST-DATA WINS: Server data is newer, updating local task \(taskId)")

                // Update existing task with server data while preserving local metadata
                existingLocalTask.name = serverTask.orderName
                existingLocalTask.soNumber = serverTask.shippingName
                existingLocalTask.status = LocalTaskStatus(from: serverTask.status)
                existingLocalTask.isPaused = serverTask.isPaused ?? false
                existingLocalTask.operationSequence = serverSequence
                existingLocalTask.lastKnownServerSequence = serverSequence

                // Update operator if present
                if let serverOperator = serverTask.currentOperator {
                    existingLocalTask.assignedStaffId = serverOperator.id
                    existingLocalTask.assignedStaffName = serverOperator.name
                }

                // Mark as synced since we're getting server data
                existingLocalTask.syncStatus = .synced

                try mainContext.save()

            } else if serverSequence == localSequence {
                // Same sequence - but still update with latest server data to ensure consistency
                print("📊 LATEST-DATA WINS: Same sequence, updating with server data for task \(taskId)")

                // Update all task fields with server data using correct LocalTask properties
                existingLocalTask.name = serverTask.orderName
                existingLocalTask.soNumber = serverTask.shippingName
                existingLocalTask.status = LocalTaskStatus(from: serverTask.status)
                existingLocalTask.isPaused = serverTask.isPaused ?? false
                existingLocalTask.operationSequence = serverTask.operationSequence ?? 0
                existingLocalTask.lastKnownServerSequence = serverSequence

                // Update operator if present
                if let serverOperator = serverTask.currentOperator {
                    existingLocalTask.assignedStaffId = serverOperator.id
                    existingLocalTask.assignedStaffName = serverOperator.name
                }

                existingLocalTask.syncStatus = .synced
                try mainContext.save()

            } else {
                // Local data is newer - keep local changes
                print("🏠 LATEST-DATA WINS: Local data is newer, preserving local changes for task \(taskId)")
                // Update last known server sequence for reference but keep local data
                existingLocalTask.lastKnownServerSequence = serverSequence
                try mainContext.save()
            }

        } else {
            // New task from server - create local copy
            print("🆕 LATEST-DATA WINS: New task from server \(taskId), creating local copy")

            let newLocalTask: LocalTask
            if let currentOperator = serverTask.currentOperator {
                newLocalTask = LocalTask.fromFulfillmentTask(serverTask, assignedTo: currentOperator)
            } else {
                newLocalTask = LocalTask.fromFulfillmentTaskWithoutOperator(serverTask)
            }

            // New server task is always synced
            newLocalTask.syncStatus = .synced

            mainContext.insert(newLocalTask)
            try mainContext.save()
        }
    }

    /// Update a single task with sequence-based conflict resolution (used for task actions)
    func updateTaskWithSequenceResolution(_ serverTask: FulfillmentTask) throws {
        try saveTaskWithConflictResolution(serverTask)
    }

    /// Fetch all tasks and convert to FulfillmentTasks
    func fetchAllTasks() throws -> [FulfillmentTask] {
        let localTasks = try fetchAllLocalTasks()
        return localTasks.map { $0.asFulfillmentTask }
    }

    /// Fetch a local task by ID
    func fetchLocalTask(id: String) throws -> LocalTask? {
        return try fetchTask(withId: id)
    }

    /// Update a task from API response with conflict resolution
    func updateTask(_ task: FulfillmentTask) throws {
        guard let existingTask = try fetchTask(withId: task.id) else {
            // Task doesn't exist locally, save it if it has an operator
            if let currentOperator = task.currentOperator {
                let localTask = LocalTask.fromFulfillmentTask(task, assignedTo: currentOperator)
                try saveLocalTask(localTask)
            }
            return
        }

        // Apply timestamp-based conflict resolution
        try updateTaskWithConflictResolution(existingTask, from: task)
    }

    /// Enhanced conflict resolution logic
    private func updateTaskWithConflictResolution(_ localTask: LocalTask, from serverTask: FulfillmentTask) throws {
        // Parse server timestamp if available
        let serverLastModified: Date?
        if let serverTimestamp = serverTask.lastModifiedAt {
            let formatter = ISO8601DateFormatter()
            serverLastModified = formatter.date(from: serverTimestamp)
        } else {
            serverLastModified = nil
        }

        let resolution = resolveTaskConflict(
            localTask: localTask,
            serverTask: serverTask,
            serverLastModified: serverLastModified
        )

        switch resolution.action {
        case .useServer(let reason):
            print("🔄 CONFLICT RESOLVED: Using server data for task \(serverTask.id) - \(reason)")
            try applyServerUpdate(localTask, from: serverTask)

        case .useLocal(let reason):
            print("🔄 CONFLICT RESOLVED: Using local data for task \(serverTask.id) - \(reason)")
            // Keep local changes, mark for priority sync
            localTask.syncStatus = .pendingPrioritySync
            localTask.lastModifiedLocally = Date()

        case .requiresManualResolution(let localTime, let serverTime):
            print("🚨 CONFLICT DETECTED: Manual resolution needed for task \(serverTask.id)")
            print("   Local timestamp: \(localTime)")
            print("   Server timestamp: \(serverTime)")
            // For MVP: use local changes but mark for investigation
            localTask.syncStatus = .conflictPendingResolution
        }

        try mainContext.save()
    }

    /// Apply server updates to local task with enhanced sequence management
    private func applyServerUpdate(_ localTask: LocalTask, from serverTask: FulfillmentTask) throws {
        // Standard field updates
        localTask.name = serverTask.orderName
        localTask.status = LocalTaskStatus(from: serverTask.status)
        localTask.isPaused = serverTask.isPaused ?? false

        if let currentOperator = serverTask.currentOperator {
            localTask.assignedStaffId = currentOperator.id
            localTask.assignedStaffName = currentOperator.name
        }

        // Enhanced sequence management updates
        let serverSequence = serverTask.operationSequence ?? 0

        // Update sequence tracking
        localTask.operationSequence = serverSequence
        localTask.lastKnownServerSequence = serverSequence

        // Handle pending operations based on server sequence
        if !localTask.pendingOperations.isEmpty {
            print("🔄 SYNC UPDATE: Reconciling \(localTask.pendingOperations.count) pending operations")

            // Find operations that appear to have been processed by server
            let processedOperations = localTask.pendingOperations.filter { operation in
                operation.localSequence <= serverSequence
            }

            if !processedOperations.isEmpty {
                print("✅ SYNC UPDATE: \(processedOperations.count) operations appear synced")
                localTask.updateAfterSuccessfulSync(serverSequence: serverSequence, syncedOperations: processedOperations)
            } else {
                // Reset local operation count if server sequence advanced beyond expectations
                localTask.localOperationCount = localTask.pendingOperations.count
                if localTask.pendingOperations.count > 1 {
                    localTask.syncStatus = .pendingSyncWithSequenceDrift
                } else if localTask.pendingOperations.count == 1 {
                    localTask.syncStatus = .pendingSync
                } else {
                    localTask.syncStatus = .synced
                }
                print("⚠️ SYNC UPDATE: Sequence mismatch - updated sync status to \(localTask.syncStatus.rawValue)")
            }
        } else {
            // No pending operations - fully synced
            localTask.localOperationCount = 0
            localTask.syncStatus = .synced
        }

        print("🔢 SYNC COMPLETE for task \(serverTask.id):")
        print("   Server sequence: \(serverSequence)")
        print("   Sync status: \(localTask.syncStatus.rawValue)")
        print("   Remaining pending operations: \(localTask.pendingOperations.count)")
    }

    /// Save checklist items for a task
    func saveChecklistItems(_ items: [ChecklistItem], forTaskId taskId: String) throws {
        guard let task = try fetchTask(withId: taskId) else {
            throw DatabaseError.taskNotFound(taskId)
        }

        // Clear existing checklist items
        for item in task.checklistItems {
            mainContext.delete(item)
        }

        // Add new checklist items
        for item in items {
            let localItem = LocalChecklistItem(
                id: "\(taskId)-\(item.id)",
                itemName: item.name,
                sku: item.sku,
                barcode: item.sku,
                quantity: item.quantity_required,
                status: item.is_completed ? .completed : .pending
            )
            localItem.task = task
            localItem.scannedAt = item.is_completed ? Date() : nil
            mainContext.insert(localItem)
        }

        task.syncStatus = .pendingSync
        task.lastModifiedLocally = Date()
        try mainContext.save()
    }

    /// Save staff members to local storage
    func saveStaff(_ staff: [StaffMember]) throws {
        // For now, we don't have a LocalStaff model, so this is a no-op
        // In a full implementation, we would create LocalStaff models and save them
        print("Staff saving not implemented - no LocalStaff model")
    }

    /// Fetch all staff members
    func fetchAllStaff() throws -> [StaffMember] {
        // For now, return empty array since we don't have LocalStaff model
        // In a full implementation, we would fetch from local storage
        return []
    }

    /// Update staff check-in status
    func updateStaffCheckInStatus(staffId: String, isCheckedIn: Bool) throws {
        // For now, this is a no-op since we don't have LocalStaff model
        // In a full implementation, we would update the staff member's status
        print("Staff check-in status update not implemented - no LocalStaff model")
    }

    /// Fetch a local staff member by ID
    func fetchLocalStaff(id: String) throws -> LocalStaff? {
        // For now, return nil since we don't have LocalStaff model
        // In a full implementation, we would fetch from local storage
        return nil
    }

    // MARK: - Conflict Resolution Logic

    /// Enhanced conflict resolution strategy using operation sequence and timestamp fallback
    private func resolveTaskConflict(
        localTask: LocalTask,
        serverTask: FulfillmentTask,
        serverLastModified: Date?
    ) -> ConflictResolution {

        // Case 1: No local changes pending - safe to use server
        if localTask.syncStatus != .pendingSync &&
           localTask.syncStatus != .pendingPrioritySync &&
           localTask.syncStatus != .conflictPendingResolution &&
           localTask.syncStatus != .pendingSyncWithSequenceDrift &&
           localTask.syncStatus != .awaitingServerAck {
            return ConflictResolution(
                action: .useServer(reason: "No local changes pending"),
                reason: "Local task syncStatus: \(localTask.syncStatus.rawValue)"
            )
        }

        // Case 2: Enhanced sequence-based resolution with drift detection
        let localSequence = localTask.operationSequence
        let serverSequence = serverTask.operationSequence ?? 0
        let lastKnownServerSequence = localTask.lastKnownServerSequence
        let localOperationCount = localTask.localOperationCount

        print("🔢 ENHANCED SEQUENCE COMPARISON for task \(serverTask.id):")
        print("   Local sequence:        \(localSequence)")
        print("   Server sequence:       \(serverSequence)")
        print("   Last known server seq: \(lastKnownServerSequence)")
        print("   Local operation count: \(localOperationCount)")
        print("   Sequence drift risk:   \(localTask.sequenceDriftRisk)")
        print("   Pending operations:    \(localTask.pendingOperationsSummary)")

        // Case 2a: Handle sequence drift scenarios
        if localTask.syncStatus == .pendingSyncWithSequenceDrift {
            print("⚠️ SEQUENCE DRIFT DETECTED - analyzing scenario")

            // If server sequence jumped ahead significantly, other operations happened
            let serverAdvancement = serverSequence - lastKnownServerSequence
            let expectedLocalSequence = lastKnownServerSequence + localOperationCount

            if serverAdvancement > localOperationCount {
                print("🔄 Server has more operations than expected - using server data")
                return ConflictResolution(
                    action: .useServer(reason: "Server sequence advanced beyond local operations"),
                    reason: "Server advancement (\(serverAdvancement)) > Local operations (\(localOperationCount))"
                )
            } else if expectedLocalSequence == serverSequence {
                print("✅ Sequences align perfectly - server caught up with local operations")
                return ConflictResolution(
                    action: .useServer(reason: "Server and local sequences are now aligned"),
                    reason: "Expected local sequence (\(expectedLocalSequence)) matches server (\(serverSequence))"
                )
            } else {
                print("🔀 Complex drift scenario - requires priority sync")
                return ConflictResolution(
                    action: .useLocal(reason: "Complex sequence drift - local operations need priority sync"),
                    reason: "Expected: \(expectedLocalSequence), Server: \(serverSequence), Need manual reconciliation"
                )
            }
        }

        // Case 2b: Standard sequence comparison
        if localSequence > serverSequence {
            return ConflictResolution(
                action: .useLocal(reason: "Local sequence is higher"),
                reason: "Local sequence (\(localSequence)) > Server sequence (\(serverSequence))"
            )
        } else if serverSequence > localSequence {
            return ConflictResolution(
                action: .useServer(reason: "Server sequence is higher"),
                reason: "Server sequence (\(serverSequence)) > Local sequence (\(localSequence))"
            )
        }

        // Case 3: Same sequence - fallback to timestamp comparison
        print("⚠️ Same sequence numbers (\(localSequence)) - falling back to timestamp comparison")

        guard let serverTime = serverLastModified else {
            return ConflictResolution(
                action: .useLocal(reason: "Same sequence, server timestamp missing"),
                reason: "Cannot determine server modification time, preserving local changes"
            )
        }

        let localTime = localTask.lastModifiedLocally
        let timeDiff = abs(localTime.timeIntervalSince(serverTime))

        print("🕐 TIMESTAMP FALLBACK for task \(serverTask.id):")
        print("   Local:  \(localTime)")
        print("   Server: \(serverTime)")
        print("   Diff:   \(timeDiff) seconds")

        // Case 4: Timestamps very close (< 60 seconds) - potential race condition
        if timeDiff < 60 {
            return ConflictResolution(
                action: .requiresManualResolution(localTime: localTime, serverTime: serverTime),
                reason: "Same sequence (\(localSequence)) and timestamps too close (\(timeDiff)s)"
            )
        }

        // Case 5: Use most recent timestamp as final tiebreaker
        if localTime > serverTime {
            return ConflictResolution(
                action: .useLocal(reason: "Same sequence, local timestamp newer"),
                reason: "Local (\(localTime)) > Server (\(serverTime))"
            )
        } else {
            return ConflictResolution(
                action: .useServer(reason: "Same sequence, server timestamp newer"),
                reason: "Server (\(serverTime)) > Local (\(localTime))"
            )
        }
    }
}

// MARK: - Helper Extensions

// MARK: - Temporary LocalStaff model for compilation

/// Temporary stub for LocalStaff until full staff model is implemented
struct LocalStaff {
    let id: String
    let name: String
    let isCheckedIn: Bool

    var asStaffMember: StaffMember {
        StaffMember(id: id, name: name)
    }
}

// MARK: - Conflict Resolution Support Types

/// Result of conflict resolution analysis
struct ConflictResolution {
    let action: Action
    let reason: String

    enum Action {
        case useLocal(reason: String)
        case useServer(reason: String)
        case requiresManualResolution(localTime: Date, serverTime: Date)
    }
}

// MARK: - Database Errors
enum DatabaseError: Error {
    case taskNotFound(String)
    case initializationFailed(Error)
}
