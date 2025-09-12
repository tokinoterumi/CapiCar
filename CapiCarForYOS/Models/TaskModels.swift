import Foundation

// MARK: - Fulfillment Task Model
struct FulfillmentTask: Identifiable, Codable, Equatable, Hashable {
    let id: String
    let orderName: String
    var status: TaskStatus
    let shippingName: String
    let createdAt: Date
    let checklistJson: String
    var currentOperator: StaffMember?
    
    // Equatable conformance for easy comparison
    static func == (lhs: FulfillmentTask, rhs: FulfillmentTask) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Supporting Models
struct StaffMember: Codable, Equatable, Identifiable, Hashable {
    let id: String
    let name: String
}

enum TaskStatus: String, CaseIterable, Codable {
    case pending = "Pending"
    case picking = "Picking"
    case packed = "Packed"
    case inspecting = "Inspecting"
    case completed = "Completed"
    case paused = "Paused"
    case cancelled = "Cancelled"
}

struct ChecklistItem: Identifiable, Codable {
    let id: Int
    let sku: String
    let name: String
    let variant_title: String
    let quantity_required: Int
    let image_url: String?
    var quantity_picked: Int = 0
    var is_completed: Bool = false
}

// MARK: - Grouped Tasks
// A helper struct to organize tasks for the DashboardView
struct GroupedTasks: Codable {
    let pending: [FulfillmentTask]
    let picking: [FulfillmentTask]
    let packed: [FulfillmentTask]
    let inspecting: [FulfillmentTask]
    let paused: [FulfillmentTask]
    let completed: [FulfillmentTask]
    let cancelled: [FulfillmentTask]
}

// MARK: - Activity Feed
struct AuditLog: Identifiable, Codable, Hashable {
    let id: String
    let timestamp: Date
    let operatorName: String
    let taskOrderName: String
    let actionType: String
    let details: String?
}
