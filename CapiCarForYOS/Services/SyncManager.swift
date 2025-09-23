import Foundation
import Network
import BackgroundTasks

// MARK: - API Payload Models for Sync

/// Payload for updating task status and checklist on the server
struct UpdateTaskPayload: Codable {
    let id: String
    let status: String
    let lastModified: Date
    let checklist: [ChecklistItemPayload]
}

/// Individual checklist item payload for sync
struct ChecklistItemPayload: Codable {
    let id: String
    let sku: String
    let status: String
    let scannedAt: Date?
}

/// 管理本地資料與遠端伺服器之間的同步。
/// 這是 Offline-First 策略的核心協調者。
@MainActor
class SyncManager: ObservableObject {
    /// 全局共享的單例實例。
    static let shared = SyncManager()
    
    // MARK: - Published Properties for UI
    
    @Published private(set) var isOnline: Bool = true
    @Published private(set) var isSyncing: Bool = false
    @Published private(set) var lastSyncTime: Date?
    @Published private(set) var lastSyncError: String?
    @Published private(set) var pendingChangesCount: Int = 0
    @Published private(set) var isReady: Bool = true

    // MARK: - Private Properties
    
    private let databaseManager = DatabaseManager.shared
    private let apiService = APIService.shared
    private let networkMonitor = NWPathMonitor()
    private let backgroundTaskIdentifier = "com.capicar.app.backgroundSync" // 應與 Info.plist 中的設定一致

    /// 私有化初始化方法，確保單例模式。
    private init() {
        print("🔥 SYNCMANAGER: Initializing SyncManager")
        setupNetworkMonitoring()
        // Auto-start network monitoring
        start()
        print("🔥 SYNCMANAGER: SyncManager initialized with isOnline = \(isOnline)")
    }

    // MARK: - Public Methods

    /// 啟動同步管理器，開始監聽網路變化。
    func start() {
        print("🔥 SYNCMANAGER: Starting network monitor")
        networkMonitor.start(queue: DispatchQueue(label: "NetworkMonitor"))
        scheduleAppRefresh() // 嘗試在啟動時安排一次背景任務
        print("🔥 SYNCMANAGER: Network monitor started")
    }
    
    /// 手動觸發一次同步流程。
    func triggerSync() async {
        await performSync()
    }

    /// Temporarily suppress sync operations to prevent sync flood during bulk operations
    func suppressSyncTemporarily() {
        // This can be implemented if needed for bulk operations
        // For now, it's a no-op since our sync manager is designed to handle concurrent operations
        print("🔇 Sync temporarily suppressed (no-op in current implementation)")
    }

    /// Force sync now - alias for triggerSync for UI compatibility
    func forceSyncNow() async {
        await triggerSync()
    }

    /// Queue a task action for offline sync
    func performTaskActionOffline(
        taskId: String,
        action: String,
        operatorId: String,
        payload: [String: String]?
    ) async throws {
        // Mark the task as pending sync
        try databaseManager.updateTaskSyncStatus(taskId: taskId, syncStatus: .pendingSync)

        // Update pending changes count
        pendingChangesCount = try databaseManager.fetchTasksPendingSync().count

        // Trigger sync when convenient (not blocking)
        Task {
            await performSync()
        }
    }

    /// Save checklist items for offline sync
    func saveChecklistOffline(_ checklist: [ChecklistItem], forTaskId taskId: String) async throws {
        // Mark the task as pending sync
        try databaseManager.updateTaskSyncStatus(taskId: taskId, syncStatus: .pendingSync)

        // Update pending changes count
        pendingChangesCount = try databaseManager.fetchTasksPendingSync().count

        // Trigger sync when convenient (not blocking)
        Task {
            await performSync()
        }
    }

    // MARK: - Computed Properties for UI Compatibility

    /// Sync error for UI display (alias for lastSyncError)
    var syncError: String? {
        lastSyncError
    }

    /// Last sync date for UI compatibility (alias for lastSyncTime)
    var lastSyncDate: Date? {
        lastSyncTime
    }

    // MARK: - Background Task Handling

    /// 向 iOS 系統註冊背景任務。
    /// 應在 App 啟動時 (例如在 App 主體中使用 `.onAppear` 或 `init`) 呼叫。
    func registerBackgroundTask() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: backgroundTaskIdentifier, using: nil) { task in
            self.handleAppRefresh(task: task as! BGAppRefreshTask)
        }
    }
    
    /// 安排下一次的背景 App 刷新任務。
    func scheduleAppRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: backgroundTaskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60) // 至少 15 分鐘後執行

        do {
            try BGTaskScheduler.shared.submit(request)
            print("背景同步任務已成功排程。")
        } catch {
            print("無法排程背景同步任務: \(error)")
        }
    }

    // MARK: - Core Sync Logic

    /// 執行同步的核心函式。
    private func performSync() async {
        // 防止重複同步
        guard !isSyncing else {
            print("同步已在進行中，跳過此次觸發。")
            return
        }
        
        // 必須在線才能同步
        guard isOnline else {
            print("設備處於離線狀態，無法執行同步。")
            return
        }

        isSyncing = true
        lastSyncError = nil
        
        do {
            let tasksToSync = try databaseManager.fetchTasksPendingSync()
            pendingChangesCount = tasksToSync.count

            if tasksToSync.isEmpty {
                print("沒有需要同步的任務。")
            } else {
                print("發現 \(tasksToSync.count) 個任務需要同步...")
                
                // 使用 TaskGroup 來並行處理多個任務的上傳
                try await withThrowingTaskGroup(of: Void.self) { group in
                    for task in tasksToSync {
                        group.addTask {
                            try await self.syncTask(task)
                        }
                    }
                    // 等待所有任務完成
                    try await group.waitForAll()
                }
            }
            
            lastSyncTime = Date()
            pendingChangesCount = 0
            print("同步成功完成。")

        } catch {
            lastSyncError = "同步失敗: \(error.localizedDescription)"
            print(lastSyncError!)
        }

        isSyncing = false
    }
    
    // MARK: - Private Helper Methods

    /// 處理單個任務的同步。
    /// - Parameter localTask: 從本地資料庫取出的 `LocalTask` 物件。
    private func syncTask(_ localTask: LocalTask) async throws {
        print("正在同步任務: \(localTask.name) (ID: \(localTask.id))，狀態為: \(localTask.status.rawValue)")
        
        // 1. 將本地模型轉換為 API Payload
        let payload = try createPayload(from: localTask)

        // 2. 呼叫 API 服務 (convert payload to appropriate API calls)
        try await syncTaskToAPI(localTask, using: payload)
        
        // 3. 處理同步成功的後續操作
        print("任務 \(localTask.id) 已成功上傳。")
        switch localTask.syncStatus {
        case .pausedPendingSync:
            // 暫停的任務：同步成功後從本地刪除 (ownership transfer back to server)
            try databaseManager.deleteSyncedTask(taskId: localTask.id)
            print("已從本地刪除暫停的任務 (返回伺服器池): \(localTask.id)")
        case .pendingSync:
            switch localTask.status {
            case .completed, .cancelled:
                // 已完成/取消的任務：同步成功後從本地刪除
                try databaseManager.deleteSyncedTask(taskId: localTask.id)
                print("已從本地刪除已終結的任務: \(localTask.id)")
            case .pending, .picking, .picked, .packed, .inspecting, .correctionNeeded, .correcting:
                // 仍在進行中的任務：僅標記為已同步
                try databaseManager.markTaskAsSynced(taskId: localTask.id)
                print("已將進行中的任務標記為同步完成: \(localTask.id)")
            case .pausedPendingSync:
                // This shouldn't happen since we handle this in the outer switch
                break
            }
        case .pendingPrioritySync:
            // 優先同步任務：處理方式與 pendingSync 相同，但具有更高優先級
            switch localTask.status {
            case .completed, .cancelled:
                try databaseManager.deleteSyncedTask(taskId: localTask.id)
                print("已從本地刪除優先同步的已終結任務: \(localTask.id)")
            case .pending, .picking, .picked, .packed, .inspecting, .correctionNeeded, .correcting:
                try databaseManager.markTaskAsSynced(taskId: localTask.id)
                print("已將優先同步的進行中任務標記為同步完成: \(localTask.id)")
            case .pausedPendingSync:
                break
            }
        case .conflictPendingResolution:
            // 衝突待解決：標記為已同步，但可能需要額外處理
            try databaseManager.markTaskAsSynced(taskId: localTask.id)
            print("衝突任務已同步，需要進一步檢查: \(localTask.id)")
        case .pendingSyncWithSequenceDrift:
            // 序列漂移風險：同步成功後標記為已同步
            try databaseManager.markTaskAsSynced(taskId: localTask.id)
            print("序列漂移任務已成功同步: \(localTask.id)")
        case .synced, .error:
            // 這些狀態不應該在待同步列表中
            break
        }
    }

    /// Sync local task to API using existing APIService methods
    private func syncTaskToAPI(_ localTask: LocalTask, using payload: UpdateTaskPayload) async throws {
        // Convert LocalTask status to appropriate TaskAction
        let action: TaskAction
        switch localTask.status {
        case .pending:
            action = .startPicking // Pending tasks start picking when synced
        case .picking:
            action = .startPicking
        case .picked:
            action = .completePicking
        case .packed:
            action = .startPacking
        case .inspecting:
            action = .startInspection
        case .correctionNeeded:
            action = .enterCorrection
        case .correcting:
            action = .startCorrection
        case .completed:
            action = .completeInspection
        case .cancelled:
            action = .cancelTask
        case .pausedPendingSync:
            action = .pauseTask
        }

        // Use existing performTaskAction method
        _ = try await apiService.performTaskAction(
            taskId: localTask.id,
            action: action,
            operatorId: localTask.assignedStaffId,
            payload: nil
        )

        // If there are checklist updates, sync them too
        if !localTask.checklistItems.isEmpty {
            let checklistItems = localTask.checklistItems.map { localItem in
                ChecklistItem(
                    id: Int(localItem.id.split(separator: "-").last.flatMap { Int($0) } ?? 0),
                    sku: localItem.sku,
                    name: localItem.itemName,
                    variant_title: "",
                    quantity_required: localItem.quantity,
                    image_url: nil,
                    quantity_picked: localItem.status == .completed ? localItem.quantity : 0,
                    is_completed: localItem.status == .completed
                )
            }

            _ = try await apiService.updateTaskChecklist(
                taskId: localTask.id,
                checklist: checklistItems,
                operatorId: localTask.assignedStaffId
            )
        }
    }

    /// 建立上傳至 API 的 payload。
    private func createPayload(from localTask: LocalTask) throws -> UpdateTaskPayload {
        // 將 LocalChecklistItem 轉換為 API 需要的格式
        let checklistPayload = localTask.checklistItems.map { localItem in
            ChecklistItemPayload(
                id: localItem.id, // 注意：這裡的 ID 可能是組合 ID，需要 API 端能正確解析
                sku: localItem.sku,
                status: localItem.status.rawValue,
                scannedAt: localItem.scannedAt
            )
        }
        
        return UpdateTaskPayload(
            id: localTask.id,
            status: localTask.status.rawValue,
            lastModified: localTask.lastModifiedLocally,
            checklist: checklistPayload
        )
    }

    /// 設定網路狀態監聽。
    private func setupNetworkMonitoring() {
        print("🔥 SYNCMANAGER: Setting up network monitoring")
        networkMonitor.pathUpdateHandler = { path in
            Task { @MainActor in
                let newOnlineStatus = path.status == .satisfied
                print("🔥 SYNCMANAGER: Network path status = \(path.status), isOnline = \(newOnlineStatus)")
                if self.isOnline != newOnlineStatus {
                    self.isOnline = newOnlineStatus
                    print("🔥 SYNCMANAGER: 網路狀態改變: \(self.isOnline ? "在線" : "離線")")

                    // 當網路從離線變為在線時，觸發一次同步
                    if self.isOnline {
                        await self.performSync()
                    }
                } else {
                    print("🔥 SYNCMANAGER: Network status unchanged: \(self.isOnline ? "在線" : "離線")")
                }
            }
        }
    }
    
    /// 處理由 iOS 系統觸發的背景刷新任務。
    private func handleAppRefresh(task: BGAppRefreshTask) {
        // 為下一次刷新安排新任務
        scheduleAppRefresh()

        // 設置任務超時處理
        task.expirationHandler = {
            // 在這裡清理並取消同步任務
            // 例如：apiService.cancelCurrentTasks()
            task.setTaskCompleted(success: false)
        }

        print("開始執行背景同步任務...")
        
        // 在背景執行同步
        Task {
            await performSync()
            let success = (lastSyncError == nil)
            print("背景同步任務完成，結果: \(success ? "成功" : "失敗")")
            task.setTaskCompleted(success: success)
        }
    }
}
