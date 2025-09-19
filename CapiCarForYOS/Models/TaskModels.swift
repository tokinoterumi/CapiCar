import Foundation

// MARK: - Fulfillment Task Model
struct FulfillmentTask: Identifiable, Codable, Equatable, Hashable {
    let id: String
    let orderName: String
    var status: TaskStatus
    let shippingName: String
    let createdAt: String  // Temporarily using String to bypass date decoding issues
    let checklistJson: String
    var currentOperator: StaffMember?

    // Exception handling fields
    var inExceptionPool: Bool?
    var exceptionReason: String?
    var exceptionLoggedAt: String?
    
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
    case inspected = "Inspected"
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
    /// Computed property to convert createdAt string to Date for UI formatting
    var createdAtDate: Date {
        return ISO8601DateFormatter().date(from: createdAt) ?? Date()
    }

    /// Returns a status indicator for tasks that need special visual treatment
    /// Used for correction states and exception pool tasks
    var statusIndicator: TaskStatusIndicator? {
        // Exception pool takes priority over other status indicators
        if inExceptionPool == true {
            return TaskStatusIndicator(
                icon: "exclamationmark.circle.fill",
                text: "Exception Reported",
                color: "red"
            )
        }

        // Regular status indicators
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
        case .inspected:
            return .inspected
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

    // Custom decoder to handle both String and Int IDs
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        // Try to decode ID as Int first, then as String and convert
        if let intId = try? container.decode(Int.self, forKey: .id) {
            self.id = intId
        } else if let stringId = try? container.decode(String.self, forKey: .id),
                  let intId = Int(stringId) {
            self.id = intId
        } else {
            // Fallback to a hash of the string ID if conversion fails
            let stringId = try container.decode(String.self, forKey: .id)
            self.id = abs(stringId.hashValue)
        }

        self.sku = try container.decodeIfPresent(String.self, forKey: .sku) ?? ""
        self.name = try container.decodeIfPresent(String.self, forKey: .name) ?? "Unknown Item"
        self.variant_title = try container.decodeIfPresent(String.self, forKey: .variant_title) ?? ""
        self.quantity_required = try container.decodeIfPresent(Int.self, forKey: .quantity_required) ?? 1
        self.image_url = try container.decodeIfPresent(String.self, forKey: .image_url)
        self.quantity_picked = try container.decodeIfPresent(Int.self, forKey: .quantity_picked) ?? 0
        self.is_completed = try container.decodeIfPresent(Bool.self, forKey: .is_completed) ?? false
    }

    // Standard initializer for manual creation
    init(id: Int, sku: String, name: String, variant_title: String, quantity_required: Int, image_url: String? = nil, quantity_picked: Int = 0, is_completed: Bool = false) {
        self.id = id
        self.sku = sku
        self.name = name
        self.variant_title = variant_title
        self.quantity_required = quantity_required
        self.image_url = image_url
        self.quantity_picked = quantity_picked
        self.is_completed = is_completed
    }
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
