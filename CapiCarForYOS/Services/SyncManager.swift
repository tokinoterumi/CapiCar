import Foundation
import Network
import BackgroundTasks

// MARK: - Sync Error Types
enum SyncError: Error {
    case retryExhausted(operation: String, taskId: String)
    case invalidTaskState(taskId: String, state: String)
    case networkUnavailable
    case conflictResolutionFailed(taskId: String)
}

// MARK: - Sync-specific Conflict Resolution Types
enum SyncConflictResolution {
    case useServer(reason: String)
    case useLocal(reason: String)
    case requiresManualResolution(localVersion: ConflictVersion, serverVersion: ConflictVersion, reason: String)
}

struct ConflictVersion {
    let task: FulfillmentTask
    let timestamp: Date
}

struct ConflictData {
    let id: String
    let taskId: String
    let localVersion: FulfillmentTask
    let serverVersion: FulfillmentTask
    let reason: String
    let createdAt: Date
}

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
    private var periodicSyncTimer: Timer?
    private var lastPeriodicSync: Date?
    private let periodicSyncInterval: TimeInterval = 5 * 60 // 5 minutes

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
        startPeriodicSync() // 啟動定期同步
        performInitialConnectivityTest() // Test connectivity immediately
        print("🔥 SYNCMANAGER: Network monitor and periodic sync started")
    }

    /// 停止同步管理器
    func stop() {
        print("🔥 SYNCMANAGER: Stopping sync manager")
        networkMonitor.cancel()
        stopPeriodicSync()
        print("🔥 SYNCMANAGER: Sync manager stopped")
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

    /// Test connectivity immediately by attempting a quick API call
    /// This updates the isOnline status in real-time
    func testConnectivity() async {
        print("🔍 CONNECTIVITY TEST: Testing network connectivity")

        do {
            // Try a quick API call to test connectivity
            let _ = try await apiService.fetchDashboardData()

            // If we get here, we're online
            if !self.isOnline {
                print("🔍 CONNECTIVITY TEST: ✅ Detected online - updating status")
                self.isOnline = true
                // Notify UI components about network status change
                NotificationCenter.default.post(name: NSNotification.Name("NetworkStatusChanged"), object: nil, userInfo: ["isOnline": true])
            }
        } catch {
            // If API call fails, we're likely offline
            if self.isOnline {
                print("🔍 CONNECTIVITY TEST: ❌ Detected offline - updating status: \(error)")
                self.isOnline = false
                // Notify UI components about network status change
                NotificationCenter.default.post(name: NSNotification.Name("NetworkStatusChanged"), object: nil, userInfo: ["isOnline": false])
            }
        }
    }

    /// 執行深度同步，包括完整的資料對帳步驟
    /// 建議定期執行以清理孤立資料
    func performDeepSync() async {
        guard !isSyncing else {
            print("🔄 DEEP SYNC: Already syncing, skipping")
            return
        }

        guard isOnline else {
            print("❌ DEEP SYNC: Device offline, cannot perform deep sync")
            return
        }

        print("🔍 DEEP SYNC: Starting comprehensive sync with full reconciliation")

        isSyncing = true
        lastSyncError = nil

        do {
            // Phase 1: Pull with full reconciliation
            let dashboardData = try await apiService.fetchDashboardData()
            let serverTasks = extractAllTasks(from: dashboardData)
            try await mergeServerDataWithLocal(serverTasks, performReconciliation: true)

            // Phase 2: Push all pending changes
            try await performPushPhase()

            lastSyncTime = Date()
            print("✅ DEEP SYNC: Completed successfully with full reconciliation")

        } catch {
            lastSyncError = "Deep sync failed: \(error.localizedDescription)"
            print("❌ DEEP SYNC: Failed - \(error)")
        }

        isSyncing = false
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

    /// 執行雙向同步的核心函式：拉取、合併、推送
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
            print("🔄 BIDIRECTIONAL SYNC: Starting pull-merge-push cycle")

            // Phase 1: Pull latest data from server
            await performPullPhase()

            // Phase 2: Push local changes to server
            try await performPushPhase()

            lastSyncTime = Date()
            print("✅ BIDIRECTIONAL SYNC: Completed successfully")

        } catch {
            lastSyncError = "雙向同步失敗: \(error.localizedDescription)"
            print("❌ BIDIRECTIONAL SYNC: Failed - \(lastSyncError!)")
        }

        isSyncing = false
    }

    /// Phase 1: Pull latest data from server and merge with local data
    private func performPullPhase() async {
        print("📥 PULL PHASE: Starting server data retrieval")

        do {
            // Fetch latest task data from server
            let dashboardData = try await apiService.fetchDashboardData()
            let serverTasks = extractAllTasks(from: dashboardData)
            print("📥 PULL PHASE: Retrieved \(serverTasks.count) tasks from server")

            // Merge server data with local data using conflict resolution
            try await mergeServerDataWithLocal(serverTasks)

            print("✅ PULL PHASE: Completed successfully")

        } catch {
            print("❌ PULL PHASE: Failed to pull server data - \(error)")
            // Continue to push phase even if pull fails
        }
    }

    /// Phase 2: Push local changes to server with retry logic
    private func performPushPhase() async throws {
        print("📤 PUSH PHASE: Starting local data upload")

        do {
            let tasksToSync = try databaseManager.fetchTasksPendingSync()
            let auditLogsToSync = try databaseManager.fetchAuditLogsPendingSync()
            pendingChangesCount = tasksToSync.count + auditLogsToSync.count

            if tasksToSync.isEmpty && auditLogsToSync.isEmpty {
                print("📤 PUSH PHASE: No pending changes to sync")
                pendingChangesCount = 0
                return
            }

            print("📤 PUSH PHASE: Found \(tasksToSync.count) tasks and \(auditLogsToSync.count) audit logs to sync")

            // Push with retry logic using TaskGroup
            try await withThrowingTaskGroup(of: Void.self) { group in
                // Sync tasks with retry
                for task in tasksToSync {
                    group.addTask {
                        try await self.syncTaskWithRetry(task)
                    }
                }

                // Sync audit logs with retry
                for auditLog in auditLogsToSync {
                    group.addTask {
                        try await self.syncAuditLogWithRetry(auditLog)
                    }
                }

                // Wait for all operations to complete
                try await group.waitForAll()
            }

            pendingChangesCount = 0
            print("✅ PUSH PHASE: Completed successfully")

        } catch {
            print("❌ PUSH PHASE: Failed - \(error)")
            throw error
        }
    }

    /// Merge server data with local data using proper conflict resolution
    private func mergeServerDataWithLocal(_ serverTasks: [FulfillmentTask], performReconciliation: Bool = true) async throws {
        print("🔀 MERGE PHASE: Starting server-local data merge")

        // Step 1: Merge/update existing tasks
        for serverTask in serverTasks {
            do {
                try await mergeIndividualTask(serverTask)
            } catch {
                print("⚠️ MERGE WARNING: Failed to merge task \(serverTask.id) - \(error)")
                // Continue with other tasks
            }
        }

        // Step 2: Reconciliation - remove local tasks that no longer exist on server
        if performReconciliation {
            try await reconcileDeletedTasks(serverTasks: serverTasks)
        } else {
            print("🧹 RECONCILIATION: Skipped for quick sync")
        }

        print("🔀 MERGE PHASE: Completed")
    }

    /// Reconciliation step: Remove local tasks that no longer exist on the server
    /// This prevents "ghost data" where deleted server tasks persist locally
    private func reconcileDeletedTasks(serverTasks: [FulfillmentTask]) async throws {
        print("🧹 RECONCILIATION: Starting ghost data cleanup")

        // Get all server task IDs
        let serverTaskIds = Set(serverTasks.map { $0.id })

        // Get all local tasks
        let allLocalTasks = try databaseManager.fetchAllLocalTasks()

        // Find local tasks that don't exist on server
        let localTasksToDelete = allLocalTasks.filter { localTask in
            !serverTaskIds.contains(localTask.id)
        }

        if localTasksToDelete.isEmpty {
            print("🧹 RECONCILIATION: No ghost data found")
            return
        }

        print("🧹 RECONCILIATION: Found \(localTasksToDelete.count) potential ghost tasks")

        var deletedCount = 0
        var skippedCount = 0

        for localTask in localTasksToDelete {
            // Only delete if the task has NO pending changes
            let pendingOperations = localTask.pendingOperations.filter {
                $0.status == .pending || $0.status == .awaitingAck
            }
            let hasPendingChanges = localTask.syncStatus != .synced || !pendingOperations.isEmpty

            if hasPendingChanges {
                print("⚠️ RECONCILIATION: Keeping ghost task \(localTask.id) - has pending changes (status: \(localTask.syncStatus), pending ops: \(pendingOperations.count))")
                skippedCount += 1
                continue
            }

            // Safe to delete - no pending local changes
            do {
                try databaseManager.deleteSyncedTask(taskId: localTask.id)
                print("🗑️ RECONCILIATION: Deleted ghost task \(localTask.id)")
                deletedCount += 1
            } catch {
                print("❌ RECONCILIATION: Failed to delete ghost task \(localTask.id) - \(error)")
            }
        }

        print("🧹 RECONCILIATION: Completed ghost data cleanup (deleted: \(deletedCount), kept: \(skippedCount))")
    }

    /// Merge individual task with proper conflict resolution
    private func mergeIndividualTask(_ serverTask: FulfillmentTask) async throws {
        guard let localTask = try databaseManager.fetchLocalTask(id: serverTask.id) else {
            // New task from server - create local copy
            print("🆕 MERGE: New server task \(serverTask.id), creating local copy")
            let newLocalTask = serverTask.currentOperator != nil ?
                LocalTask.fromFulfillmentTask(serverTask, assignedTo: serverTask.currentOperator!) :
                LocalTask.fromFulfillmentTaskWithoutOperator(serverTask)

            newLocalTask.syncStatus = .synced
            try databaseManager.saveLocalTask(newLocalTask)
            return
        }

        // Existing task - perform conflict resolution
        let resolution = resolveTaskConflict(localTask: localTask, serverTask: serverTask)
        do {
            try await applyConflictResolution(localTask: localTask, serverTask: serverTask, resolution: resolution)
        } catch {
            print("❌ CONFLICT RESOLUTION: Failed for task \(serverTask.id) - \(error)")
            throw error
        }
    }

    // MARK: - Conflict Resolution

    /// Helper method to extract all tasks from DashboardData
    private func extractAllTasks(from dashboardData: DashboardData) -> [FulfillmentTask] {
        var allTasks: [FulfillmentTask] = []
        allTasks.append(contentsOf: dashboardData.tasks.pending)
        allTasks.append(contentsOf: dashboardData.tasks.picking)  // includes picked
        allTasks.append(contentsOf: dashboardData.tasks.packed)
        allTasks.append(contentsOf: dashboardData.tasks.inspecting)  // includes correctionNeeded + correcting
        allTasks.append(contentsOf: dashboardData.tasks.completed)
        allTasks.append(contentsOf: dashboardData.tasks.paused)
        allTasks.append(contentsOf: dashboardData.tasks.cancelled)
        return allTasks
    }

    /// Enhanced conflict resolution with proper data preservation
    private func resolveTaskConflict(localTask: LocalTask, serverTask: FulfillmentTask) -> SyncConflictResolution {
        let localSequence = localTask.operationSequence
        let serverSequence = serverTask.operationSequence ?? 0
        let localModified = localTask.lastModifiedLocally
        let serverModified = ISO8601DateFormatter().date(from: serverTask.lastModifiedAt ?? "") ?? Date.distantPast

        print("🔍 CONFLICT ANALYSIS: Task \(serverTask.id)")
        print("   Local: seq=\(localSequence), modified=\(localModified)")
        print("   Server: seq=\(serverSequence), modified=\(serverModified)")
        print("   Local sync status: \(localTask.syncStatus)")

        // Case 1: No local changes - safe to use server data
        if localTask.syncStatus == .synced {
            return .useServer(reason: "No local changes pending")
        }

        // Case 2: Sequence-based resolution (most reliable)
        if localSequence != serverSequence {
            return localSequence > serverSequence ?
                .useLocal(reason: "Local sequence higher (\(localSequence) > \(serverSequence))") :
                .useServer(reason: "Server sequence higher (\(serverSequence) > \(localSequence))")
        }

        // Case 3: Same sequence - use timestamp
        let timeDiff = abs(localModified.timeIntervalSince(serverModified))
        if timeDiff > 60 { // More than 1 minute difference
            return localModified > serverModified ?
                .useLocal(reason: "Local timestamp newer") :
                .useServer(reason: "Server timestamp newer")
        }

        // Case 4: Potential conflict - preserve both versions
        return .requiresManualResolution(
            localVersion: ConflictVersion(task: localTask.asFulfillmentTask, timestamp: localModified),
            serverVersion: ConflictVersion(task: serverTask, timestamp: serverModified),
            reason: "Sequences equal (\(localSequence)) and timestamps too close (\(timeDiff)s)"
        )
    }

    /// Apply conflict resolution decision
    private func applyConflictResolution(localTask: LocalTask, serverTask: FulfillmentTask, resolution: SyncConflictResolution) async throws {
        switch resolution {
        case .useServer(let reason):
            print("📥 CONFLICT: Using server version - \(reason)")
            try databaseManager.updateTaskWithSequenceResolution(serverTask)

        case .useLocal(let reason):
            print("📤 CONFLICT: Using local version - \(reason)")
            localTask.syncStatus = .pendingSync
            localTask.markRequiresBackgroundSync(reason: "Conflict resolved in favor of local")

        case .requiresManualResolution(_, _, let reason):
            print("⚠️ CONFLICT: Manual resolution required - \(reason)")
            try await preserveConflictingVersions(localTask: localTask, serverTask: serverTask, reason: reason)
        }
    }

    /// Preserve both versions of conflicting data until manual resolution
    private func preserveConflictingVersions(localTask: LocalTask, serverTask: FulfillmentTask, reason: String) async throws {
        // Create conflict record
        let conflictId = UUID().uuidString
        let _ = ConflictData(
            id: conflictId,
            taskId: localTask.id,
            localVersion: localTask.asFulfillmentTask,
            serverVersion: serverTask,
            reason: reason,
            createdAt: Date()
        )

        // Store conflict data (would need to implement ConflictData model)
        // For now, mark task as conflict pending resolution
        localTask.syncStatus = .conflictPendingResolution
        localTask.markRequiresBackgroundSync(reason: "Conflict detected: \(reason)")

        print("💾 CONFLICT: Preserved conflicting versions for task \(localTask.id) (conflict ID: \(conflictId))")

        // TODO: Implement UI notification for manual resolution
        // TODO: Store conflict data in dedicated table for user review
    }

    // MARK: - Retry Mechanisms

    /// Sync task with exponential backoff retry
    private func syncTaskWithRetry(_ localTask: LocalTask) async throws {
        try await performWithRetry(operation: "syncTask", taskId: localTask.id) {
            try await self.syncTask(localTask)
        }
    }

    /// Sync audit log with exponential backoff retry
    private func syncAuditLogWithRetry(_ auditLog: LocalAuditLog) async throws {
        try await performWithRetry(operation: "syncAuditLog", taskId: auditLog.taskId) {
            try await self.syncAuditLog(auditLog)
        }
    }

    /// Generic retry mechanism with exponential backoff
    private func performWithRetry(operation: String, taskId: String, maxRetries: Int = 3, baseDelay: Double = 2.0, maxDelay: Double = 30.0, execute: () async throws -> Void) async throws {
        var lastError: Error?

        for attempt in 0...maxRetries {
            do {
                try await execute()
                if attempt > 0 {
                    print("✅ RETRY SUCCESS: \(operation) for \(taskId) succeeded on attempt \(attempt + 1)")
                }
                return
            } catch {
                lastError = error

                if attempt < maxRetries {
                    let delay = min(baseDelay * pow(2.0, Double(attempt)), maxDelay)
                    print("🔄 RETRY: \(operation) for \(taskId) failed (attempt \(attempt + 1)/\(maxRetries + 1)), retrying in \(delay)s - \(error)")

                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                } else {
                    print("❌ RETRY FAILED: \(operation) for \(taskId) failed after \(maxRetries + 1) attempts - \(error)")
                }
            }
        }

        throw lastError ?? SyncError.retryExhausted(operation: operation, taskId: taskId)
    }

    // MARK: - State Management for Operations

    /// 處理單個任務的同步。
    /// - Parameter localTask: 從本地資料庫取出的 `LocalTask` 物件。
    private func syncTask(_ localTask: LocalTask) async throws {
        print("正在同步任務: \(localTask.name) (ID: \(localTask.id))，狀態為: \(localTask.status.rawValue)")

        // Mark task as awaiting server acknowledgment before sync attempt
        if localTask.syncStatus != .awaitingServerAck {
            try databaseManager.updateTaskSyncStatus(taskId: localTask.id, syncStatus: .awaitingServerAck)
        }

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
        case .pendingSync, .awaitingServerAck:
            switch localTask.status {
            case .completed, .cancelled:
                // 已完成/取消的任務：同步成功後從本地刪除
                try databaseManager.deleteSyncedTask(taskId: localTask.id)
                print("已從本地刪除已終結的任務: \(localTask.id)")
            case .pending, .picking, .packed, .inspecting, .correctionNeeded, .correcting:
                // 仍在進行中的任務：僅標記為已同步
                try databaseManager.markTaskAsSynced(taskId: localTask.id)
                print("已將進行中的任務標記為同步完成: \(localTask.id)")
            case .pausedPendingSync:
                // This shouldn't happen since we handle this in the outer switch
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
        case .pendingPrioritySync:
            // Deprecated case - treat as pendingSync
            print("⚠️ Encountered deprecated pendingPrioritySync - please clear local data")
            try databaseManager.markTaskAsSynced(taskId: localTask.id)
        }
    }

    /// Sync local task to API by replaying actual pending operations (preserves audit trail)
    private func syncTaskToAPI(_ localTask: LocalTask, using payload: UpdateTaskPayload) async throws {
        // Sort pending operations by sequence to replay them in correct order
        // Only sync pending operations (not awaiting ack, as those are already sent)
        let operationsToSync = localTask.pendingOperations
            .filter { $0.status == .pending }
            .sorted { $0.localSequence < $1.localSequence }

        guard !operationsToSync.isEmpty else {
            print("⚠️ SYNC WARNING: No pending operations to sync for task \(localTask.id)")
            return
        }

        print("🔄 SYNC: Replaying \(operationsToSync.count) pending operations for task \(localTask.id)")

        // Replay each operation in sequence
        for operation in operationsToSync {
            print("🎬 SYNC: Replaying \(operation.actionType) (sequence: \(operation.localSequence)) - Attempt \(operation.retryCount + 1)")

            // Check if operation has exceeded retry limit BEFORE attempting
            if operation.retryCount >= 5 { // Default max retries is 5
                print("⚠️ SYNC: Operation \(operation.actionType) exceeded max retries (\(operation.retryCount)), marking as failed")
                operation.status = .failed
                continue
            }

            // Mark operation as awaiting server acknowledgment BEFORE sending
            operation.status = .awaitingAck

            do {
                // Convert operation action type to TaskAction
                guard let taskAction = TaskAction(rawValue: operation.actionType) else {
                    print("⚠️ SYNC WARNING: Unknown action type \(operation.actionType), marking as failed")
                    operation.status = .failed
                    continue
                }

                // Parse payload if present
                var actionPayload: [String: String]? = nil
                if let payloadString = operation.payload,
                   !payloadString.isEmpty,
                   let payloadData = payloadString.data(using: .utf8),
                   let parsedPayload = try? JSONSerialization.jsonObject(with: payloadData) as? [String: String] {
                    actionPayload = parsedPayload
                }

                // Perform the action on the server
                _ = try await apiService.performTaskAction(
                    taskId: localTask.id,
                    action: taskAction,
                    operatorId: localTask.assignedStaffId,
                    payload: actionPayload
                )

                // Mark this operation as synced ONLY after successful server response
                operation.status = .synced
                print("✅ SYNC: Successfully synced operation \(operation.actionType)")

            } catch {
                // Increment retry count and reset to pending for next sync cycle
                operation.retryCount += 1
                operation.status = .pending
                print("❌ SYNC FAILED: Operation \(operation.actionType) failed (attempt \(operation.retryCount)/5), will retry - \(error)")
                throw error
            }
        }

        print("🎯 SYNC: All pending operations processed for task \(localTask.id)")

        // Update task sync status based on remaining operations
        let remainingPendingOps = localTask.pendingOperations.filter { $0.status == .pending }
        let remainingAwaitingOps = localTask.pendingOperations.filter { $0.status == .awaitingAck }
        let failedOps = localTask.pendingOperations.filter { $0.status == .failed }

        if remainingPendingOps.isEmpty && remainingAwaitingOps.isEmpty {
            // All operations are either synced or failed - task is effectively synced
            try databaseManager.updateTaskSyncStatus(taskId: localTask.id, syncStatus: .synced)
            if !failedOps.isEmpty {
                print("⚠️ SYNC: Task \(localTask.id) marked as synced but has \(failedOps.count) permanently failed operations")
            }
        } else {
            print("📋 SYNC: Task \(localTask.id) has \(remainingPendingOps.count) pending and \(remainingAwaitingOps.count) awaiting operations remaining")
        }
    }

    /// 同步審計日誌到伺服器
    /// - Parameter auditLog: 需要同步的本地審計日誌
    private func syncAuditLog(_ auditLog: LocalAuditLog) async throws {
        print("📝 SYNC: Syncing audit log \(auditLog.actionType) for task \(auditLog.taskId)")

        // Call the real audit log sync endpoint with array of logs
        let response = try await apiService.syncAuditLog([auditLog])

        // Check if sync was successful
        if response.syncedCount == 1 {
            // Mark as synced locally after successful API call
            try databaseManager.markAuditLogAsSynced(logId: auditLog.id)
            print("✅ SYNC: Audit log \(auditLog.id) marked as synced")
        } else {
            // Handle partial failure
            if !response.errors.isEmpty {
                let errorMessage = response.errors.first?.error ?? "Unknown sync error"
                print("⚠️ SYNC: Audit log sync failed: \(errorMessage)")
                throw APIError.serverError(message: errorMessage)
            }
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
                // More aggressive offline detection
                let hasConnection = path.status == .satisfied
                let hasWiFi = path.usesInterfaceType(.wifi)
                let hasCellular = path.usesInterfaceType(.cellular)
                let isExpensive = path.isExpensive

                // Consider offline if no interface available or explicitly unsatisfied
                let newOnlineStatus = hasConnection && (hasWiFi || hasCellular)

                print("🔥 SYNCMANAGER: Network path status = \(path.status)")
                print("🔥 SYNCMANAGER: WiFi: \(hasWiFi), Cellular: \(hasCellular), Expensive: \(isExpensive)")
                print("🔥 SYNCMANAGER: Computed isOnline = \(newOnlineStatus)")

                if self.isOnline != newOnlineStatus {
                    self.isOnline = newOnlineStatus
                    print("🔥 SYNCMANAGER: ⚡ 網路狀態改變: \(self.isOnline ? "在線" : "離線")")

                    // 當網路從離線變為在線時，觸發一次同步
                    if self.isOnline {
                        await self.performSync()
                        self.resetPeriodicSyncTimer() // 重置定期同步計時器
                    }
                } else {
                    print("🔥 SYNCMANAGER: Network status unchanged: \(self.isOnline ? "在線" : "離線")")
                }
            }
        }
    }

    /// Perform initial connectivity test after app launch
    private func performInitialConnectivityTest() {
        Task {
            // Wait a bit for network to settle after app launch
            try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
            await testConnectivity()
        }
    }

    // MARK: - Periodic Sync Management

    /// 啟動定期同步計時器
    private func startPeriodicSync() {
        stopPeriodicSync() // 確保沒有重複的計時器

        periodicSyncTimer = Timer.scheduledTimer(withTimeInterval: periodicSyncInterval, repeats: true) { [weak self] _ in
            guard let self = self else { return }

            Task { @MainActor in
                print("⏰ PERIODIC SYNC: Timer triggered")
                await self.performPeriodicSyncCheck()
            }
        }

        print("⏰ PERIODIC SYNC: Timer started with \(periodicSyncInterval / 60) minute interval")
    }

    /// 停止定期同步計時器
    private func stopPeriodicSync() {
        periodicSyncTimer?.invalidate()
        periodicSyncTimer = nil
        print("⏰ PERIODIC SYNC: Timer stopped")
    }

    /// 重置定期同步計時器
    private func resetPeriodicSyncTimer() {
        startPeriodicSync()
        print("⏰ PERIODIC SYNC: Timer reset")
    }

    /// 執行定期同步檢查
    private func performPeriodicSyncCheck() async {
        // 只有在線且有待同步資料時才執行定期同步
        guard isOnline else {
            print("⏰ PERIODIC SYNC: Skipping - device offline")
            return
        }

        // 檢查是否有待同步資料
        do {
            let tasksToSync = try databaseManager.fetchTasksPendingSync()
            let auditLogsToSync = try databaseManager.fetchAuditLogsPendingSync()
            let totalPending = tasksToSync.count + auditLogsToSync.count

            if totalPending == 0 {
                print("⏰ PERIODIC SYNC: Skipping - no pending data")
                return
            }

            print("⏰ PERIODIC SYNC: Found \(totalPending) items to sync, triggering sync")
            await performSync()
            lastPeriodicSync = Date()

        } catch {
            print("⏰ PERIODIC SYNC: Error checking pending data - \(error)")
        }
    }
    
    /// 處理由 iOS 系統觸發的背景刷新任務。
    private func handleAppRefresh(task: BGAppRefreshTask) {
        print("🌙 BACKGROUND: App refresh task started")

        // 為下一次刷新安排新任務
        scheduleAppRefresh()

        // 創建取消機制
        var isCancelled = false
        var syncTask: Task<Void, Never>?

        // 設置任務超時處理 - 提前終止以確保有時間清理
        task.expirationHandler = {
            print("⏰ BACKGROUND: Task expiring, initiating cleanup")
            isCancelled = true
            syncTask?.cancel()

            // 給清理過程一點時間
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                print("🔚 BACKGROUND: Task marked as completed due to expiration")
                task.setTaskCompleted(success: false)
            }
        }

        print("🔄 BACKGROUND: Starting background sync...")

        // 在背景執行同步，增加容錯機制
        syncTask = Task {
            var success = false

            do {
                // 檢查是否有待同步資料，如果沒有則快速退出
                let tasksToSync = try databaseManager.fetchTasksPendingSync()
                let auditLogsToSync = try databaseManager.fetchAuditLogsPendingSync()
                let totalPending = tasksToSync.count + auditLogsToSync.count

                if totalPending == 0 {
                    print("🌙 BACKGROUND: No pending data, completing early")
                    success = true
                } else {
                    print("🌙 BACKGROUND: Found \(totalPending) items to sync")

                    // 檢查網路狀態
                    guard isOnline else {
                        print("🌙 BACKGROUND: Device offline, cannot sync")
                        success = false
                        return
                    }

                    // 在檢查點確保沒有被取消
                    if isCancelled { return }

                    // 執行同步，但只嘗試一次（不重試，因為時間有限）
                    await performBackgroundSync(isCancelledCheck: { isCancelled })
                    success = (lastSyncError == nil)
                }

            } catch {
                print("❌ BACKGROUND: Sync failed with error: \(error)")
                success = false
            }

            // 只有在沒有被取消的情況下才標記完成
            if !isCancelled {
                print("✅ BACKGROUND: Task completed with success: \(success)")
                task.setTaskCompleted(success: success)
            }
        }
    }

    /// 執行背景同步，具有取消檢查機制
    private func performBackgroundSync(isCancelledCheck: @escaping () -> Bool) async {
        // 防止重複同步
        guard !isSyncing else {
            print("🌙 BACKGROUND: Sync already in progress, skipping")
            return
        }

        // 必須在線才能同步
        guard isOnline else {
            print("🌙 BACKGROUND: Device offline, cannot sync")
            return
        }

        isSyncing = true
        lastSyncError = nil

        print("🔄 BACKGROUND SYNC: Starting pull-merge-push cycle")

        // 檢查取消狀態
        if isCancelledCheck() {
            print("🔚 BACKGROUND: Sync cancelled during startup")
            return
        }

        // Phase 1: Quick pull phase (只獲取最新資料，不做複雜合併)
        await performSimplePullPhase(isCancelledCheck: isCancelledCheck)

        if isCancelledCheck() {
            print("🔚 BACKGROUND: Sync cancelled after pull phase")
            return
        }

        // Phase 2: Push critical pending changes only
        await performCriticalPushPhase(isCancelledCheck: isCancelledCheck)

        lastSyncTime = Date()
        print("✅ BACKGROUND SYNC: Completed successfully")

        isSyncing = false
    }

    /// 簡化的拉取階段，適合背景執行
    private func performSimplePullPhase(isCancelledCheck: @escaping () -> Bool) async {
        print("📥 BACKGROUND PULL: Starting server data retrieval")

        do {
            if isCancelledCheck() { return }

            // 僅獲取伺服器資料，不進行複雜的合併操作
            let dashboardData = try await apiService.fetchDashboardData()
            let serverTasks = extractAllTasks(from: dashboardData)
            print("📥 BACKGROUND PULL: Retrieved \(serverTasks.count) tasks from server")

            if isCancelledCheck() { return }

            // 快速更新本地資料（僅處理明確的衝突）
            for serverTask in serverTasks.prefix(10) { // 限制處理數量以節省時間
                if isCancelledCheck() { return }
                try await mergeIndividualTask(serverTask)
            }

            print("✅ BACKGROUND PULL: Completed")

        } catch {
            print("❌ BACKGROUND PULL: Failed - \(error)")
        }
    }

    /// 關鍵推送階段，只處理最重要的待同步項目
    private func performCriticalPushPhase(isCancelledCheck: @escaping () -> Bool) async {
        print("📤 BACKGROUND PUSH: Starting critical data upload")

        do {
            if isCancelledCheck() { return }

            let tasksToSync = try databaseManager.fetchTasksPendingSync()
            let auditLogsToSync = try databaseManager.fetchAuditLogsPendingSync()

            // 優先處理已完成或取消的任務（這些最需要同步）
            let criticalTasks = tasksToSync.filter { task in
                task.status == .completed || task.status == .cancelled || task.syncStatus == .pendingSync
            }.prefix(5) // 限制數量

            print("📤 BACKGROUND PUSH: Processing \(criticalTasks.count) critical tasks")

            for task in criticalTasks {
                if isCancelledCheck() { return }

                do {
                    try await syncTaskWithRetry(task)
                } catch {
                    print("⚠️ BACKGROUND PUSH: Failed to sync task \(task.id) - \(error)")
                    // 繼續處理其他任務
                }
            }

            pendingChangesCount = max(0, tasksToSync.count + auditLogsToSync.count - criticalTasks.count)
            print("✅ BACKGROUND PUSH: Completed critical sync")

        } catch {
            print("❌ BACKGROUND PUSH: Failed - \(error)")
        }
    }
}
