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

    /// 同步時發生錯誤。
    case error
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
    
    /// 與此任務關聯的所有檢查項目列表。
    /// 設定 `.cascade` 可以在刪除任務時，一併刪除其下的所有 checklist items。
    @Relationship(deleteRule: .cascade, inverse: \LocalChecklistItem.task)
    var checklistItems: [LocalChecklistItem] = []
    
    init(id: String, name: String, type: String, soNumber: String, assignedStaffId: String, assignedStaffName: String, status: LocalTaskStatus = .picking, isPaused: Bool = false) {
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
            isPaused: isPaused
        )
    }

    /// Create LocalTask from FulfillmentTask (for task claiming)
    static func fromFulfillmentTask(_ task: FulfillmentTask, assignedTo staff: StaffMember) -> LocalTask {
        let localTask = LocalTask(
            id: task.id,
            name: task.orderName,
            type: "Fulfillment",
            soNumber: task.shippingName,
            assignedStaffId: staff.id,
            assignedStaffName: staff.name,
            status: .picking,
            isPaused: task.isPaused ?? false
        )

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
        let localTask = LocalTask(
            id: task.id,
            name: task.orderName,
            type: "Fulfillment",
            soNumber: task.shippingName,
            assignedStaffId: "", // No operator assigned yet
            assignedStaffName: "", // No operator assigned yet
            status: LocalTaskStatus(from: task.status),
            isPaused: task.isPaused ?? false
        )

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

