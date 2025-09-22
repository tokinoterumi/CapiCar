import Foundation
import SwiftData

// MARK: - Enums for Local State Management

/// 本地任務的同步狀態
/// 用於追蹤任務是否已與伺服器同步。
enum SyncStatus: String, Codable {
    /// 資料已與伺服器同步。
    case synced

    /// 本地有變更，等待上傳至伺服器。
    case pendingSync

    /// 任務已在本地暫停，等待同步暫停狀態回伺服器。
    case pausedPendingSync

    /// 本地變更需要優先同步 (timestamp conflict resolved in favor of local)
    case pendingPrioritySync

    /// 檢測到衝突，需要人工解決 (timestamps too close)
    case conflictPendingResolution

    /// 多個離線操作等待同步，存在序列漂移風險
    case pendingSyncWithSequenceDrift

    /// 同步時發生錯誤。
    case error
}

/// 本地待處理操作記錄
/// 用於追蹤離線期間執行的操作序列
@Model
final class LocalPendingOperation {
    /// 唯一識別碼
    @Attribute(.unique)
    var id: String

    /// 所屬任務的 ID
    var taskId: String

    /// 操作類型 (例如：START_PICKING, COMPLETE_INSPECTION)
    var actionType: String

    /// 本地序列號 (預測性遞增)
    var localSequence: Int

    /// 操作執行時間
    var performedAt: Date

    /// 操作的額外資料 (JSON 格式)
    var payload: String?

    /// 操作詳細描述
    var details: String

    /// 操作狀態
    var status: PendingOperationStatus

    init(id: String = UUID().uuidString, taskId: String, actionType: String, localSequence: Int, details: String, payload: String? = nil) {
        self.id = id
        self.taskId = taskId
        self.actionType = actionType
        self.localSequence = localSequence
        self.performedAt = Date()
        self.payload = payload
        self.details = details
        self.status = .pending
    }
}

/// 待處理操作的狀態
enum PendingOperationStatus: String, Codable {
    /// 等待同步至伺服器
    case pending

    /// 已成功同步
    case synced

    /// 同步失敗，需要重試
    case failed

    /// 操作被取消或覆蓋
    case cancelled
}

/// 本地任務在其生命週期中的狀態
/// 這區別於伺服器的狀態，專門為離線操作設計。
enum LocalTaskStatus: String, Codable {
    /// 任務待領取 (Phase 1: Discovery)
    case pending

    /// 任務已被領取並正在執行中。
    case picking

    /// 任務撿選完成，等待包裝
    case picked

    /// 任務已包裝，等待檢查
    case packed

    /// 任務正在檢查中
    case inspecting

    /// 任務需要修正
    case correctionNeeded

    /// 任務正在修正中
    case correcting

    /// 任務已在本地完成，等待同步。
    case completed

    /// 任務已在本地取消，等待同步。
    case cancelled

    /// 任務已在本地暫停，等待同步暫停狀態回伺服器。
    case pausedPendingSync
}

/// 本地檢查清單項目的狀態
enum LocalChecklistItemStatus: String, Codable {
    /// 項目等待處理。
    case pending
    
    /// 項目已完成掃描或確認。
    case completed
    
    /// 項目被標記為損壞或有問題。
    case damaged
}


// MARK: - SwiftData Models

/// `LocalTask` 代表儲存在裝置本地資料庫中的一個任務。
/// 這是 Offline-First 策略的核心，所有操作都應先更新此模型。
@Model
final class LocalTask {
    /// 來自伺服器的唯一識別碼，用於同步。
    @Attribute(.unique)
    var id: String
    
    var name: String
    var type: String
    var soNumber: String
    
    /// 分配給此任務的作業人員 ID。
    var assignedStaffId: String
    
    /// 分配給此任務的作業人員姓名 (用於 UI 顯示)。
    var assignedStaffName: String
    
    /// 任務在本地的狀態 (例如：正在執行、已完成待同步)。
    var status: LocalTaskStatus
    
    /// 標記任務是否已暫停。
    var isPaused: Bool
    
    /// 此任務在本地最後被修改的時間戳。
    var lastModifiedLocally: Date
    
    /// 此任務與伺服器的同步狀態。
    var syncStatus: SyncStatus

    /// 操作序列號，用於衝突解決。
    var operationSequence: Int

    /// 最後一次從伺服器同步的序列號 (用於檢測序列漂移)
    var lastKnownServerSequence: Int

    /// 本地操作計數器 (用於預測性序列遞增)
    var localOperationCount: Int

    /// 與此任務關聯的所有檢查項目列表。
    /// 設定 `.cascade` 可以在刪除任務時，一併刪除其下的所有 checklist items。
    @Relationship(deleteRule: .cascade, inverse: \LocalChecklistItem.task)
    var checklistItems: [LocalChecklistItem] = []

    /// 與此任務關聯的待處理操作列表。
    /// 用於追蹤離線期間執行的操作序列。
    @Relationship(deleteRule: .cascade)
    var pendingOperations: [LocalPendingOperation] = []
    
    init(id: String, name: String, type: String, soNumber: String, assignedStaffId: String, assignedStaffName: String, status: LocalTaskStatus = .picking, isPaused: Bool = false, operationSequence: Int = 0) {
        self.id = id
        self.name = name
        self.type = type
        self.soNumber = soNumber
        self.assignedStaffId = assignedStaffId
        self.assignedStaffName = assignedStaffName
        self.status = status
        self.isPaused = isPaused
        self.lastModifiedLocally = Date()
        self.syncStatus = .pendingSync // 新任務預設為待同步狀態
        self.operationSequence = operationSequence
        self.lastKnownServerSequence = operationSequence // 初始化時與 operationSequence 相同
        self.localOperationCount = 0 // 新任務無本地操作
    }
}

// MARK: - LocalTask Extensions

extension LocalTask {
    /// Convert LocalTask to FulfillmentTask for UI display
    var asFulfillmentTask: FulfillmentTask {
        let taskStatus: TaskStatus
        switch status {
        case .pending:
            taskStatus = .pending
        case .picking:
            taskStatus = .picking
        case .picked:
            taskStatus = .picked
        case .packed:
            taskStatus = .packed
        case .inspecting:
            taskStatus = .inspecting
        case .correctionNeeded:
            taskStatus = .correctionNeeded
        case .correcting:
            taskStatus = .correcting
        case .completed:
            taskStatus = .completed
        case .cancelled:
            taskStatus = .cancelled
        case .pausedPendingSync:
            taskStatus = .pending // Return to pending when paused
        }

        let currentOperator = StaffMember(id: assignedStaffId, name: assignedStaffName)

        // Convert checklist items back to JSON string
        let checklistJSON: String
        if checklistItems.isEmpty {
            checklistJSON = "[]"
        } else {
            let checklistData = checklistItems.map { localItem in
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

            if let jsonData = try? JSONEncoder().encode(checklistData),
               let jsonString = String(data: jsonData, encoding: .utf8) {
                checklistJSON = jsonString
            } else {
                checklistJSON = "[]"
            }
        }

        return FulfillmentTask(
            id: id,
            orderName: name,
            status: taskStatus,
            shippingName: soNumber,
            createdAt: lastModifiedLocally.ISO8601Format(),
            checklistJson: checklistJSON,
            currentOperator: currentOperator,
            isPaused: isPaused,
            operationSequence: operationSequence
        )
    }

    /// Create LocalTask from FulfillmentTask (for task claiming)
    static func fromFulfillmentTask(_ task: FulfillmentTask, assignedTo staff: StaffMember) -> LocalTask {
        let serverSequence = task.operationSequence ?? 0
        let localTask = LocalTask(
            id: task.id,
            name: task.orderName,
            type: "Fulfillment",
            soNumber: task.shippingName,
            assignedStaffId: staff.id,
            assignedStaffName: staff.name,
            status: .picking,
            isPaused: task.isPaused ?? false,
            operationSequence: serverSequence
        )

        // Initialize sequence management for newly claimed task
        localTask.lastKnownServerSequence = serverSequence
        localTask.localOperationCount = 0

        // Parse checklist from JSON
        if let checklistData = task.checklistJson.data(using: .utf8),
           let checklistItems = try? JSONDecoder().decode([ChecklistItem].self, from: checklistData) {
            localTask.checklistItems = checklistItems.map { apiItem in
                let localItem = LocalChecklistItem(
                    id: "\(task.id)-\(apiItem.id)",
                    itemName: apiItem.name,
                    sku: apiItem.sku,
                    barcode: apiItem.sku,
                    quantity: apiItem.quantity_required,
                    status: apiItem.is_completed ? .completed : .pending
                )
                localItem.task = localTask
                return localItem
            }
        }

        return localTask
    }

    /// Create LocalTask from FulfillmentTask without an assigned operator
    /// Used for tasks that haven't been claimed yet (e.g., pending tasks)
    static func fromFulfillmentTaskWithoutOperator(_ task: FulfillmentTask) -> LocalTask {
        let serverSequence = task.operationSequence ?? 0
        let localTask = LocalTask(
            id: task.id,
            name: task.orderName,
            type: "Fulfillment",
            soNumber: task.shippingName,
            assignedStaffId: "", // No operator assigned yet
            assignedStaffName: "", // No operator assigned yet
            status: LocalTaskStatus(from: task.status),
            isPaused: task.isPaused ?? false,
            operationSequence: serverSequence
        )

        // Initialize sequence management for server task
        localTask.lastKnownServerSequence = serverSequence
        localTask.localOperationCount = 0

        // Parse checklist from JSON
        if let checklistData = task.checklistJson.data(using: .utf8),
           let checklistItems = try? JSONDecoder().decode([ChecklistItem].self, from: checklistData) {
            localTask.checklistItems = checklistItems.map { apiItem in
                let localItem = LocalChecklistItem(
                    id: "\(task.id)-\(apiItem.id)",
                    itemName: apiItem.name,
                    sku: apiItem.sku,
                    barcode: apiItem.sku,
                    quantity: apiItem.quantity_required,
                    status: apiItem.is_completed ? .completed : .pending
                )
                localItem.task = localTask
                localItem.scannedAt = apiItem.is_completed ? Date() : nil
                return localItem
            }
        }

        return localTask
    }

    // MARK: - Local Sequence Management

    /// 執行本地操作並管理序列號
    /// 這是離線期間執行操作的核心方法
    func performLocalOperation(
        actionType: String,
        details: String,
        payload: String? = nil
    ) -> LocalPendingOperation {
        // 1. 遞增本地操作計數器
        localOperationCount += 1

        // 2. 計算預測性序列號：最後已知伺服器序列 + 本地操作計數
        let predictedSequence = lastKnownServerSequence + localOperationCount

        // 3. 更新本地操作序列號
        operationSequence = predictedSequence

        // 4. 創建待處理操作記錄
        let pendingOperation = LocalPendingOperation(
            taskId: id,
            actionType: actionType,
            localSequence: predictedSequence,
            details: details,
            payload: payload
        )

        // 5. 添加到待處理操作列表
        pendingOperations.append(pendingOperation)

        // 6. 更新同步狀態
        if localOperationCount > 1 {
            // 多個操作存在序列漂移風險
            syncStatus = .pendingSyncWithSequenceDrift
        } else {
            // 單個操作，正常待同步
            syncStatus = .pendingSync
        }

        // 7. 更新最後修改時間
        lastModifiedLocally = Date()

        print("🔢 LOCAL OPERATION: \(actionType) on task \(id)")
        print("   Predicted sequence: \(predictedSequence)")
        print("   Local operation count: \(localOperationCount)")
        print("   Sync status: \(syncStatus.rawValue)")

        return pendingOperation
    }

    /// 同步成功後更新序列號狀態
    /// 當操作成功同步到伺服器後調用
    func updateAfterSuccessfulSync(serverSequence: Int, syncedOperations: [LocalPendingOperation]) {
        // 1. 更新最後已知的伺服器序列號
        lastKnownServerSequence = serverSequence
        operationSequence = serverSequence

        // 2. 標記同步的操作為已完成
        for operation in syncedOperations {
            operation.status = .synced
        }

        // 3. 移除已同步的操作
        pendingOperations.removeAll { syncedOperations.contains($0) }

        // 4. 重新計算本地操作計數
        localOperationCount = pendingOperations.count

        // 5. 更新同步狀態
        if pendingOperations.isEmpty {
            syncStatus = .synced
        } else {
            // 還有其他待同步操作
            syncStatus = localOperationCount > 1 ? .pendingSyncWithSequenceDrift : .pendingSync
        }

        print("✅ SYNC SUCCESS: Task \(id) updated to server sequence \(serverSequence)")
        print("   Remaining pending operations: \(pendingOperations.count)")
        print("   Updated sync status: \(syncStatus.rawValue)")
    }

    /// 檢測序列漂移風險
    /// 返回本地序列與伺服器序列的預期差異
    var sequenceDriftRisk: Int {
        return operationSequence - lastKnownServerSequence
    }

    /// 是否存在序列漂移風險
    var hasSequenceDriftRisk: Bool {
        return sequenceDriftRisk > 0
    }

    /// 獲取本地操作摘要 (用於調試和同步日誌)
    var pendingOperationsSummary: String {
        let actions = pendingOperations.map { "\($0.actionType)(\($0.localSequence))" }
        return "[\(actions.joined(separator: ", "))]"
    }
}


// MARK: - LocalTaskStatus Conversion Extension

extension LocalTaskStatus {
    /// Create LocalTaskStatus from TaskStatus
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
            self = .inspecting // Map inspected back to inspecting for local state
        case .correctionNeeded:
            self = .correctionNeeded
        case .correcting:
            self = .correcting
        case .completed:
            self = .completed
        case .cancelled:
            self = .cancelled
        }
    }
}

/// `LocalChecklistItem` 代表一個任務中的單個檢查項目。
@Model
final class LocalChecklistItem {
    /// 來自伺服器的唯一識別碼。
    @Attribute(.unique)
    var id: String
    
    var itemName: String
    var sku: String
    var barcode: String
    var quantity: Int
    
    /// 項目在本地的狀態 (例如：待處理、已完成)。
    var status: LocalChecklistItemStatus
    
    /// 項目被掃描或確認的時間。
    var scannedAt: Date?
    
    /// 此項目所屬的任務 (多對一關係)。
    var task: LocalTask?
    
    init(id: String, itemName: String, sku: String, barcode: String, quantity: Int, status: LocalChecklistItemStatus = .pending) {
        self.id = id
        self.itemName = itemName
        self.sku = sku
        self.barcode = barcode
        self.quantity = quantity
        self.status = status
    }
}

