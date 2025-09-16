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
    case picked = "Picked"
    case packed = "Packed"
    case inspecting = "Inspecting"
    case correctionNeeded = "Correction_Needed"
    case correcting = "Correcting"
    case completed = "Completed"
    case paused = "Paused"
    case cancelled = "Cancelled"
}

// MARK: - Status Indicator Model
struct TaskStatusIndicator {
    let icon: String
    let text: String
    let color: String // SF Symbol color name
}

// MARK: - Task Status Extensions
extension FulfillmentTask {
    /// Returns a status indicator for tasks that need special visual treatment
    /// Used for correction states within the simplified "Inspecting" group
    var statusIndicator: TaskStatusIndicator? {
        switch status {
        case .correctionNeeded:
            return TaskStatusIndicator(
                icon: "exclamationmark.triangle.fill",
                text: "Needs Correction",
                color: "orange"
            )
        case .correcting:
            return TaskStatusIndicator(
                icon: "wrench.fill", 
                text: "Being Corrected",
                color: "blue"
            )
        default:
            return nil
        }
    }
    
    /// Returns the simplified group status for UI display
    /// Maps granular statuses to user-friendly groups
    var groupStatus: TaskStatus {
        switch status {
        case .pending:
            return .pending
        case .picking, .picked:
            return .picking
        case .packed:
            return .packed
        case .inspecting, .correctionNeeded, .correcting:
            return .inspecting
        case .completed:
            return .completed
        case .paused:
            return .paused
        case .cancelled:
            return .cancelled
        }
    }
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
// Simplified grouping that combines granular statuses for better UX
struct GroupedTasks: Codable {
    let pending: [FulfillmentTask]       // pending
    let picking: [FulfillmentTask]       // picking + picked
    let packed: [FulfillmentTask]        // packed
    let inspecting: [FulfillmentTask]    // inspecting + correctionNeeded + correcting
    let completed: [FulfillmentTask]     // completed
    let paused: [FulfillmentTask]        // paused
    let cancelled: [FulfillmentTask]     // cancelled
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
