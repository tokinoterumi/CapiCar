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
            task.syncStatus == .pendingSync || task.syncStatus == .pausedPendingSync
        }
    }
    
    /// (調試用) 獲取所有本地儲存的任務。
    func fetchAllLocalTasks() throws -> [LocalTask] {
        let descriptor = FetchDescriptor<LocalTask>()
        return try mainContext.fetch(descriptor)
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

    /// Save multiple tasks from API response
    func saveTasks(_ tasks: [FulfillmentTask]) throws {
        print("🔥 DATABASE: Starting to save \(tasks.count) tasks")
        // For now, just save them as individual tasks
        // In a full implementation, we might want to batch this operation
        for task in tasks {
            print("🔥 DATABASE: Processing task \(task.id) (\(task.orderName)) - status: \(task.status)")
            // Convert FulfillmentTask to LocalTask for storage
            if let currentOperator = task.currentOperator {
                print("🔥 DATABASE: Task has operator: \(currentOperator.name)")
                // Task has an operator - use existing method
                let localTask = LocalTask.fromFulfillmentTask(task, assignedTo: currentOperator)
                try saveLocalTask(localTask)
            } else {
                print("🔥 DATABASE: Task has no operator - creating without operator")
                // Task doesn't have an operator yet (e.g., pending tasks)
                // Create a LocalTask without operator assignment
                let localTask = LocalTask.fromFulfillmentTaskWithoutOperator(task)
                try saveLocalTask(localTask)
            }
            print("🔥 DATABASE: Successfully saved task \(task.id)")
        }
        print("🔥 DATABASE: Finished saving all \(tasks.count) tasks")
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

    /// Update a task from API response
    func updateTask(_ task: FulfillmentTask) throws {
        guard let existingTask = try fetchTask(withId: task.id) else {
            // Task doesn't exist locally, save it if it has an operator
            if let currentOperator = task.currentOperator {
                let localTask = LocalTask.fromFulfillmentTask(task, assignedTo: currentOperator)
                try saveLocalTask(localTask)
            }
            return
        }

        // Update existing task properties
        existingTask.name = task.orderName
        existingTask.status = LocalTaskStatus(from: task.status)
        existingTask.isPaused = task.isPaused ?? false
        existingTask.lastModifiedLocally = Date()
        existingTask.syncStatus = .synced // Mark as synced since this came from API

        if let currentOperator = task.currentOperator {
            existingTask.assignedStaffId = currentOperator.id
            existingTask.assignedStaffName = currentOperator.name
        }

        try mainContext.save()
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
}

// MARK: - Helper Extensions

extension LocalTaskStatus {
    init(from taskStatus: TaskStatus) {
        switch taskStatus {
        case .pending:
            self = .pending
        case .picking:
            self = .picking
        case .picked:
            self = .picked
        case .packed:
            self = .packed
        case .inspecting:
            self = .inspecting
        case .inspected:
            self = .inspecting // Map inspected to inspecting since LocalTaskStatus doesn't have inspected
        case .completed:
            self = .completed
        case .cancelled:
            self = .cancelled
        case .correctionNeeded:
            self = .correcting // Map to closest available status
        case .correcting:
            self = .correcting
        }
    }
}

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

// MARK: - Database Errors
enum DatabaseError: Error {
    case taskNotFound(String)
    case initializationFailed(Error)
}
