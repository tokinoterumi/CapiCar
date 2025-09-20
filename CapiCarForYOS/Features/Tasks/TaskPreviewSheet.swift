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

                    // MARK: - Exception Notes (if applicable)
                    if task.inExceptionPool == true {
                        exceptionNotesSection
                    }

                    // MARK: - Correction Notes (if applicable)
                    if task.status == .correctionNeeded {
                        correctionNotesSection
                    }

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
        Text(task.groupStatus.rawValue)
            .font(.caption)
            .fontWeight(.semibold)
            .foregroundColor(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(statusColor)
            .cornerRadius(20)
    }
    
    private var statusColor: Color {
        let baseColor: Color

        switch task.status {
        case .pending: baseColor = .orange
        case .picking: baseColor = .blue
        case .picked: baseColor = .cyan
        case .packed, .inspecting, .inspected: baseColor = .purple
        case .correctionNeeded: baseColor = .red
        case .correcting: baseColor = .pink
        case .completed: baseColor = .green
        case .cancelled: baseColor = .gray
        }

        // If task is paused, make it semi-transparent to show paused state
        // while preserving the original work status color
        if task.isPaused == true {
            return baseColor.opacity(0.5)
        }

        return baseColor
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

    private var exceptionNotesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "exclamationmark.circle.fill")
                    .foregroundColor(.red)
                Text("⚠️ Exception Reported")
                    .font(.headline)
                    .fontWeight(.semibold)
            }

            if let reason = task.exceptionReason, !reason.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Issue Type:")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.secondary)

                    Text(formatIssueType(reason))
                        .font(.body)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color.red.opacity(0.1))
                        .cornerRadius(8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.red.opacity(0.3), lineWidth: 1)
                        )
                }
            }

            if let loggedAt = task.exceptionLoggedAt, !loggedAt.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Reported:")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.secondary)

                    Text(formatExceptionDate(loggedAt))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Text("This task has been moved to the exception pool and requires attention before it can proceed.")
                .font(.caption)
                .foregroundColor(.secondary)
                .italic()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color.red.opacity(0.05))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.red.opacity(0.3), lineWidth: 1.5)
        )
    }

    private var correctionNotesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)
                Text("🔧 Correction Required")
                    .font(.headline)
                    .fontWeight(.semibold)
            }

            Text("This task requires corrections before it can be completed. Please address the inspection issues and make necessary adjustments.")
                .font(.body)
                .foregroundColor(.primary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color.orange.opacity(0.05))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.orange.opacity(0.3), lineWidth: 1.5)
        )
    }

    private var actionButtonSection: some View {
        VStack(spacing: 12) {
            if canStartTask {
                PrimaryButton(
                    title: primaryActionTitle,
                    action: {
                        dismiss() // Close preview sheet

                        // Always route to TaskDetailView for all actionable tasks
                        showingFullWorkflow = true
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
        print("🔍 TaskPreviewSheet DEBUG:")
        print("  - Task status: \(task.status.rawValue)")
        print("  - Staff checked in: \(staffManager.isOperatorCheckedIn)")
        print("  - Current operator: \(staffManager.currentOperator?.id ?? "nil") (\(staffManager.currentOperator?.name ?? "nil"))")
        print("  - Task operator: \(task.currentOperator?.id ?? "nil") (\(task.currentOperator?.name ?? "nil"))")

        guard staffManager.isOperatorCheckedIn else {
            print("  - Result: false (not checked in)")
            return false
        }

        // Handle paused tasks separately - they can be resumed by any checked-in operator
        if task.isPaused == true {
            print("  - Result: true (paused task)")
            return true
        }

        switch task.status {
        case .pending, .packed, .correctionNeeded:
            // These statuses are unassigned - any checked-in operator can start
            print("  - Result: true (unassigned status)")
            return true
        case .picking, .picked, .inspecting, .inspected, .correcting:
            // These statuses require operator assignment match
            let result = task.currentOperator?.id == staffManager.currentOperator?.id
            print("  - Result: \(result) (operator match required)")
            return result
        case .completed, .cancelled:
            // Always show button for completed/cancelled to allow viewing details
            print("  - Result: true (completed/cancelled)")
            return true
        }
    }
    
    private var primaryActionTitle: String {
        // Handle paused tasks first - show specific resume action based on work status
        if task.isPaused == true {
            switch task.status {
            case .picking: return "Resume Picking"
            case .inspecting: return "Resume Inspection"
            case .correcting: return "Resume Correction"
            default: return "Resume" // Fallback for edge cases
            }
        }

        switch task.status {
        case .pending: return "Start Picking"
        case .picking: return "Continue Picking"
        case .picked: return "Start Packing"
        case .packed: return "Start Inspection"
        case .inspecting: return "Continue Inspection"
        case .inspected: return "Complete Inspection"
        case .correctionNeeded: return "Start Correction"
        case .correcting: return "Continue Correction"
        case .completed: return "View Details"
        case .cancelled: return "View Details"
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

    private func formatIssueType(_ issueType: String) -> String {
        // Convert snake_case issue types to readable format
        let issueTypeMapping: [String: String] = [
            "damaged_item": "Damaged Item / 商品破損",
            "missing_item": "Missing Item / 商品不足",
            "wrong_item": "Wrong Item / 商品違い",
            "quality_issue": "Quality Issue / 品質問題",
            "packaging_issue": "Packaging Issue / 梱包問題",
            "system_error": "System Error / システムエラー",
            "equipment_failure": "Equipment Failure / 機器故障",
            "other": "Other / その他"
        ]

        return issueTypeMapping[issueType] ?? issueType.replacingOccurrences(of: "_", with: " ").capitalized
    }

    private func formatExceptionDate(_ dateString: String) -> String {
        // Parse ISO8601 date and format it nicely
        let isoFormatter = ISO8601DateFormatter()
        if let date = isoFormatter.date(from: dateString) {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .short
            formatter.locale = Locale.current
            return formatter.string(from: date)
        }
        return dateString
    }

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
        .environmentObject(DashboardViewModel())
    }
}
#endif
