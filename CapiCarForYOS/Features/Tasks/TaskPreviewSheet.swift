import SwiftUI

struct TaskPreviewSheet: View {
    let task: FulfillmentTask
    @EnvironmentObject private var staffManager: StaffManager
    @Environment(\.dismiss) private var dismiss

    // Binding to control navigation to full workflow
    @Binding var showingFullWorkflow: Bool
    @Binding var showingInspectionView: Bool
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    
                    // MARK: - Task Header
                    taskHeaderSection
                    
                    // MARK: - Customer Information
                    customerInfoSection
                    
                    // MARK: - Quick Checklist Preview
                    checklistPreviewSection
                    
                    // MARK: - Task Status
                    taskStatusSection
                }
                .padding()
            }
            .navigationTitle("Task Preview")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(content: {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Close") {
                        dismiss()
                    }
                }
            })
            
            // MARK: - Action Button
            actionButtonSection
        }
    }
    
    // MARK: - Subviews
    
    private var taskHeaderSection: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(task.orderName)
                    .font(.title2)
                    .fontWeight(.bold)
                
                Text("Created: \(task.createdAtDate, style: .date)")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            statusBadge
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(12)
    }
    
    private var statusBadge: some View {
        Text(task.status.rawValue)
            .font(.caption)
            .fontWeight(.semibold)
            .foregroundColor(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(statusColor)
            .cornerRadius(20)
    }
    
    private var statusColor: Color {
        switch task.status {
        case .pending: return .orange
        case .picking: return .blue
        case .picked: return .cyan
        case .packed, .inspecting, .inspected: return .purple
        case .correctionNeeded: return .red
        case .correcting: return .pink
        case .completed: return .green
        case .cancelled: return .gray
        case .paused: return .yellow
        }
    }
    
    private var customerInfoSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Shipping Information")
                .font(.headline)
                .fontWeight(.semibold)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(task.shippingName)
                    .font(.body)
                    .fontWeight(.medium)
                
                // Mock address - in production this would come from task data
                Text("123 Apple Park Way")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                Text("Cupertino, CA 95014")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(12)
    }
    
    private var checklistPreviewSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Items Overview")
                .font(.headline)
                .fontWeight(.semibold)
            
            if let checklistItems = parseChecklistItems() {
                VStack(spacing: 8) {
                    ForEach(checklistItems.prefix(3)) { item in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.name)
                                    .font(.body)
                                    .lineLimit(1)
                                
                                Text(item.sku)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            
                            Spacer()
                            
                            Text("Qty: \(item.quantity_required)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                    
                    if checklistItems.count > 3 {
                        Text("+ \(checklistItems.count - 3) more items")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.top, 4)
                    }

                }
            } else {
                Text("No items found")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(12)
    }
    
    private var taskStatusSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Current Status")
                .font(.headline)
                .fontWeight(.semibold)
            
            if let currentOperator = task.currentOperator {
                HStack {
                    Image(systemName: "person.fill")
                        .foregroundColor(statusColor)
                    
                    Text("Assigned to: \(currentOperator.name)")
                        .font(.body)
                }
            } else {
                HStack {
                    Image(systemName: "person.badge.plus")
                        .foregroundColor(.orange)
                    
                    Text("Unassigned - Ready to start")
                        .font(.body)
                        .foregroundColor(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(12)
    }
    
    private var actionButtonSection: some View {
        VStack(spacing: 12) {
            if canStartTask {
                PrimaryButton(
                    title: primaryActionTitle,
                    action: {
                        dismiss() // Close preview sheet

                        // Route to appropriate view based on task status
                        if task.status == .packed {
                            showingInspectionView = true // Go to InspectionView
                        } else {
                            showingFullWorkflow = true // Go to TaskDetailView
                        }
                    }
                )
                .padding(.horizontal)
            } else {
                Text(actionUnavailableReason)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
        }
        .padding(.bottom)
        .background(.regularMaterial)
    }
    
    // MARK: - Computed Properties
    
    private var canStartTask: Bool {
        guard staffManager.isOperatorCheckedIn else { return false }

        switch task.status {
        case .pending, .paused, .packed:
            // These statuses are unassigned - any checked-in operator can start
            return true
        case .picking, .picked, .inspecting, .inspected, .correctionNeeded, .correcting:
            // These statuses require operator assignment match
            return task.currentOperator?.id == staffManager.currentOperator?.id
        case .completed, .cancelled:
            return false
        }
    }
    
    private var primaryActionTitle: String {
        switch task.status {
        case .pending, .paused: return "Start Picking"
        case .picked: return "Start Packing"
        case .packed: return "Start Inspection"
        case .correctionNeeded: return "Start Correction"
        case .completed: return "View Details"
        case .cancelled: return "View Details"
        case .picking, .inspecting, .inspected, .correcting: return "Continue Task"
        }
    }
    
    private var actionUnavailableReason: String {
        if !staffManager.isOperatorCheckedIn {
            return "Please check in as an operator to start working on tasks"
        }
        
        switch task.status {
        case .picking, .picked, .packed, .inspecting, .correctionNeeded, .correcting:
            if task.currentOperator?.id != staffManager.currentOperator?.id {
                return "This task is currently assigned to \(task.currentOperator?.name ?? "another operator")"
            }
        case .completed:
            return "This task has been completed"
        case .cancelled:
            return "This task has been cancelled"
        default:
            break
        }
        
        return "Task cannot be started at this time"
    }
    
    // MARK: - Helper Methods
    
    private func parseChecklistItems() -> [ChecklistItem]? {
        guard !task.checklistJson.isEmpty,
              let data = task.checklistJson.data(using: .utf8) else {
            return nil
        }

        do {
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase

            // First, try to decode as an array directly
            if let checklistArray = try? decoder.decode([ChecklistItem].self, from: data) {
                return checklistArray
            }

            // If that fails, try to decode as a dictionary with nested JSON
            if let jsonObject = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                // Try different possible keys
                var itemsArray: [[String: Any]]?
                if let items = jsonObject["checklist"] as? [[String: Any]] {
                    itemsArray = items
                } else if let items = jsonObject["items"] as? [[String: Any]] {
                    itemsArray = items
                } else if let items = jsonObject["checklist_items"] as? [[String: Any]] {
                    itemsArray = items
                } else if let jsonString = jsonObject["json"] as? String {
                    // Handle nested JSON string
                    if let nestedData = jsonString.data(using: .utf8) {
                        do {
                            let nestedObject = try JSONSerialization.jsonObject(with: nestedData)
                            if let nestedArray = nestedObject as? [[String: Any]] {
                                itemsArray = nestedArray
                            } else if let singleItem = nestedObject as? [String: Any] {
                                itemsArray = [singleItem]
                            }
                        } catch {
                            print("Error parsing nested JSON in preview: \(error)")
                        }
                    }
                }

                if let items = itemsArray {
                    let itemsData = try JSONSerialization.data(withJSONObject: items)
                    return try decoder.decode([ChecklistItem].self, from: itemsData)
                }
            }

            return nil
        } catch {
            print("Error parsing checklist: \(error)")
            return nil
        }
    }
}

#if DEBUG
struct TaskPreviewSheet_Previews: PreviewProvider {
    static var previews: some View {
        let mockTask = FulfillmentTask(
            id: "preview_001",
            orderName: "#YM1001",
            status: .pending,
            shippingName: "John Appleseed",
            createdAt: Date().ISO8601Format(),
            checklistJson: """
            [
                {
                    "id": 1,
                    "sku": "TS-BLK-L",
                    "name": "Classic T-Shirt",
                    "variant_title": "Black / L",
                    "quantity_required": 2,
                    "image_url": null,
                    "quantity_picked": 0,
                    "is_completed": false
                },
                {
                    "id": 2,
                    "sku": "MUG-WHT-01",
                    "name": "Company Mug",
                    "variant_title": "White",
                    "quantity_required": 1,
                    "image_url": null,
                    "quantity_picked": 0,
                    "is_completed": false
                }
            ]
            """,
            currentOperator: nil
        )
        
        let mockStaffManager = StaffManager()
        mockStaffManager.currentOperator = StaffMember(id: "staff1", name: "Test User")
        
        return TaskPreviewSheet(
            task: mockTask,
            showingFullWorkflow: .constant(false),
            showingInspectionView: .constant(false)
        )
        .environmentObject(mockStaffManager)
    }
}
#endif
