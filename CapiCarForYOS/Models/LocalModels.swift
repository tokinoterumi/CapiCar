import Foundation
import SwiftData

// MARK: - SwiftData Models for Local Persistence

@Model
final class LocalFulfillmentTask {
    @Attribute(.unique) var id: String
    var orderName: String
    var status: String
    var shippingName: String
    var createdAt: Date
    var checklistJson: String
    var currentOperatorId: String?
    var currentOperatorName: String?
    
    // Sync tracking
    var lastSyncedAt: Date?
    var needsSync: Bool = false
    var isDeleted: Bool = false
    
    // Offline state tracking
    var localModifiedAt: Date = Date()
    var syncVersion: Int = 0
    
    init(id: String, orderName: String, status: String, shippingName: String, createdAt: Date, checklistJson: String, currentOperatorId: String? = nil, currentOperatorName: String? = nil) {
        self.id = id
        self.orderName = orderName
        self.status = status
        self.shippingName = shippingName
        self.createdAt = createdAt
        self.checklistJson = checklistJson
        self.currentOperatorId = currentOperatorId
        self.currentOperatorName = currentOperatorName
        self.localModifiedAt = Date()
        self.needsSync = false
    }
    
    // Convert to domain model
    var asFulfillmentTask: FulfillmentTask {
        let currentOperator: StaffMember? = {
            guard let operatorId = currentOperatorId,
                  let operatorName = currentOperatorName else { return nil }
            return StaffMember(id: operatorId, name: operatorName)
        }()
        
        return FulfillmentTask(
            id: id,
            orderName: orderName,
            status: TaskStatus(rawValue: status) ?? .pending,
            shippingName: shippingName,
            createdAt: createdAt.ISO8601Format(),
            checklistJson: checklistJson,
            currentOperator: currentOperator
        )
    }
    
    // Update from domain model
    func update(from task: FulfillmentTask) {
        self.orderName = task.orderName
        self.status = task.status.rawValue
        self.shippingName = task.shippingName
        self.checklistJson = task.checklistJson
        self.currentOperatorId = task.currentOperator?.id
        self.currentOperatorName = task.currentOperator?.name
        self.localModifiedAt = Date()
        self.needsSync = true
    }
}

@Model
final class LocalStaffMember {
    @Attribute(.unique) var id: String
    var name: String
    var isCheckedIn: Bool = false
    var checkedInAt: Date?
    
    // Sync tracking
    var lastSyncedAt: Date?
    var needsSync: Bool = false
    
    init(id: String, name: String) {
        self.id = id
        self.name = name
    }
    
    // Convert to domain model
    var asStaffMember: StaffMember {
        StaffMember(id: id, name: name)
    }
    
    // Update from domain model
    func update(from staff: StaffMember) {
        self.name = staff.name
        self.needsSync = true
    }
}

@Model
final class LocalChecklistItem {
    @Attribute(.unique) var id: String
    var taskId: String
    var itemId: Int
    var sku: String
    var name: String
    var variantTitle: String
    var quantityRequired: Int
    var imageUrl: String?
    var quantityPicked: Int = 0
    var isCompleted: Bool = false
    
    // Sync tracking
    var lastSyncedAt: Date?
    var needsSync: Bool = false
    var localModifiedAt: Date = Date()
    
    init(taskId: String, itemId: Int, sku: String, name: String, variantTitle: String, quantityRequired: Int, imageUrl: String? = nil) {
        self.id = "\(taskId)_\(itemId)"
        self.taskId = taskId
        self.itemId = itemId
        self.sku = sku
        self.name = name
        self.variantTitle = variantTitle
        self.quantityRequired = quantityRequired
        self.imageUrl = imageUrl
    }
    
    // Convert to domain model
    var asChecklistItem: ChecklistItem {
        ChecklistItem(
            id: itemId,
            sku: sku,
            name: name,
            variant_title: variantTitle,
            quantity_required: quantityRequired,
            image_url: imageUrl,
            quantity_picked: quantityPicked,
            is_completed: isCompleted
        )
    }
    
    // Update from domain model
    func update(from item: ChecklistItem) {
        self.quantityPicked = item.quantity_picked
        self.isCompleted = item.is_completed
        self.localModifiedAt = Date()
        self.needsSync = true
    }
}

@Model
final class LocalAuditLog {
    @Attribute(.unique) var id: String
    var timestamp: Date
    var operatorName: String
    var taskOrderName: String
    var actionType: String
    var details: String?
    
    // Sync tracking
    var lastSyncedAt: Date?
    var needsSync: Bool = false
    
    init(id: String, timestamp: Date, operatorName: String, taskOrderName: String, actionType: String, details: String? = nil) {
        self.id = id
        self.timestamp = timestamp
        self.operatorName = operatorName
        self.taskOrderName = taskOrderName
        self.actionType = actionType
        self.details = details
        self.needsSync = false
    }
    
    // Convert to domain model
    var asAuditLog: AuditLog {
        AuditLog(
            id: id,
            timestamp: timestamp,
            operatorName: operatorName,
            taskOrderName: taskOrderName,
            actionType: actionType,
            details: details
        )
    }
}

@Model
final class LocalSyncState {
    @Attribute(.unique) var id: String = "singleton"
    var lastFullSyncAt: Date?
    var isOnline: Bool = true
    var pendingActionCount: Int = 0
    var lastErrorMessage: String?
    var lastErrorAt: Date?
    
    init() {
        self.id = "singleton"
    }
}

// MARK: - Conversion Extensions

extension FulfillmentTask {
    func asLocalTask() -> LocalFulfillmentTask {
        LocalFulfillmentTask(
            id: id,
            orderName: orderName,
            status: status.rawValue,
            shippingName: shippingName,
            createdAt: ISO8601DateFormatter().date(from: createdAt) ?? Date(),
            checklistJson: checklistJson,
            currentOperatorId: currentOperator?.id,
            currentOperatorName: currentOperator?.name
        )
    }
}

extension StaffMember {
    func asLocalStaff() -> LocalStaffMember {
        LocalStaffMember(id: id, name: name)
    }
}

extension ChecklistItem {
    func asLocalItem(taskId: String) -> LocalChecklistItem {
        let localItem = LocalChecklistItem(
            taskId: taskId,
            itemId: id,
            sku: sku,
            name: name,
            variantTitle: variant_title,
            quantityRequired: quantity_required,
            imageUrl: image_url
        )
        localItem.quantityPicked = quantity_picked
        localItem.isCompleted = is_completed
        return localItem
    }
}

extension AuditLog {
    func asLocalLog() -> LocalAuditLog {
        LocalAuditLog(
            id: id,
            timestamp: timestamp,
            operatorName: operatorName,
            taskOrderName: taskOrderName,
            actionType: actionType,
            details: details
        )
    }
}