import SwiftUI

struct TaskPreviewSheet: View {
    let initialTask: FulfillmentTask
    @EnvironmentObject private var staffManager: StaffManager
    @Environment(\.dismiss) private var dismiss

    // Binding to control navigation to full workflow
    @Binding var showingFullWorkflow: Bool
    @Binding var showingInspectionView: Bool

    // State for current task data
    @State private var currentTask: FulfillmentTask
    @State private var isLoading = false

    init(task: FulfillmentTask, showingFullWorkflow: Binding<Bool>, showingInspectionView: Binding<Bool>) {
        self.initialTask = task
        self._showingFullWorkflow = showingFullWorkflow
        self._showingInspectionView = showingInspectionView
        self._currentTask = State(initialValue: task)
    }

    // Use currentTask throughout the view instead of task
    private var task: FulfillmentTask {
        currentTask
    }
    
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

                    // MARK: - Work History (for completed/cancelled tasks)
                    if task.status == .completed || task.status == .cancelled {
                        workHistorySection
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
        .onAppear {
            Task {
                await fetchLatestTaskData()
            }
        }
        .onChange(of: initialTask.id) { _, _ in
            // Refresh data when a new task is passed in
            Task {
                await fetchLatestTaskData()
            }
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

    private var workHistorySection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "clock.arrow.circlepath")
                    .foregroundColor(.blue)
                Text("📋 Work History")
                    .font(.headline)
                    .fontWeight(.semibold)
            }

            VStack(spacing: 12) {
                ForEach(mockWorkHistory, id: \.timestamp) { entry in
                    WorkHistoryRow(entry: entry)
                }
            }

            // Completion summary
            if task.status == .completed {
                CompletionSummaryView(task: task)
            } else if task.status == .cancelled {
                CancellationSummaryView(task: task)
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
                        Task {
                            // If this is a paused task, resume it first
                            if task.isPaused == true {
                                await resumeTask()
                            }

                            await MainActor.run {
                                dismiss() // Close preview sheet

                                // Navigate based on task status
                                if shouldNavigateToInspection {
                                    showingInspectionView = true
                                } else {
                                    showingFullWorkflow = true
                                }
                            }
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
        print("🔍 TaskPreviewSheet DEBUG:")
        print("  - Task status: \(task.status.rawValue)")
        print("  - Staff checked in: \(staffManager.isOperatorCheckedIn)")
        print("  - Current operator: \(staffManager.currentOperator?.id ?? "nil") (\(staffManager.currentOperator?.name ?? "nil"))")
        print("  - Task operator: \(task.currentOperator?.id ?? "nil") (\(task.currentOperator?.name ?? "nil"))")

        // Completed and cancelled tasks don't need action buttons - they show work history instead
        if task.status == .completed || task.status == .cancelled {
            print("  - Result: false (completed/cancelled - no actions needed)")
            return false
        }

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
            // These are handled above - no action buttons
            print("  - Result: false (completed/cancelled)")
            return false
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
        case .picking: return "View Progress"
        case .picked: return "Start Packing"
        case .packed: return "Start Inspection"
        case .inspecting: return "View Progress"
        case .inspected: return "Complete Inspection"
        case .correctionNeeded: return "Start Correction"
        case .correcting: return "View Progress"
        case .completed: return "View Details"
        case .cancelled: return "View Details"
        }
    }
    
    private var actionUnavailableReason: String {
        // For completed/cancelled tasks, show completion summary instead of action unavailable message
        switch task.status {
        case .completed:
            return "Task completed successfully. See work history below for details."
        case .cancelled:
            return "Task was cancelled. See work history below for details."
        default:
            break
        }

        if !staffManager.isOperatorCheckedIn {
            return "Please check in as an operator to start working on tasks"
        }

        switch task.status {
        case .picking, .picked, .packed, .inspecting, .correctionNeeded, .correcting:
            if task.currentOperator?.id != staffManager.currentOperator?.id {
                return "This task is currently assigned to \(task.currentOperator?.name ?? "another operator")"
            }
        default:
            break
        }

        return "Task cannot be started at this time"
    }

    private var shouldNavigateToInspection: Bool {
        // Check if this is an inspection-related task (after resume if applicable)
        let currentStatus = task.status

        switch currentStatus {
        case .packed, .inspecting, .inspected:
            return true
        default:
            return false
        }
    }

    // MARK: - Mock Work History Data

    private var mockWorkHistory: [WorkHistoryEntry] {
        let baseTime = task.createdAtDate

        switch task.status {
        case .completed:
            return [
                WorkHistoryEntry(
                    timestamp: baseTime,
                    action: "Task Created",
                    operatorName: "System",
                    icon: "plus.circle",
                    color: .gray
                ),
                WorkHistoryEntry(
                    timestamp: baseTime.addingTimeInterval(300),
                    action: "Picking Started",
                    operatorName: "Capybara",
                    icon: "hand.point.up.braille",
                    color: .blue
                ),
                WorkHistoryEntry(
                    timestamp: baseTime.addingTimeInterval(900),
                    action: "All Items Picked",
                    operatorName: "Capybara",
                    icon: "checkmark.circle",
                    color: .blue
                ),
                WorkHistoryEntry(
                    timestamp: baseTime.addingTimeInterval(1200),
                    action: "Packing Completed",
                    operatorName: "Capybara",
                    icon: "shippingbox",
                    color: .cyan
                ),
                WorkHistoryEntry(
                    timestamp: baseTime.addingTimeInterval(1500),
                    action: "Inspection Started",
                    operatorName: "Caterpillar",
                    icon: "magnifyingglass",
                    color: .purple
                ),
                WorkHistoryEntry(
                    timestamp: baseTime.addingTimeInterval(1800),
                    action: "Inspection Passed",
                    operatorName: "Caterpillar",
                    icon: "checkmark.seal",
                    color: .green
                ),
                WorkHistoryEntry(
                    timestamp: baseTime.addingTimeInterval(1900),
                    action: "Task Completed",
                    operatorName: "Caterpillar",
                    icon: "checkmark.circle.fill",
                    color: .green
                )
            ]
        case .cancelled:
            return [
                WorkHistoryEntry(
                    timestamp: baseTime,
                    action: "Task Created",
                    operatorName: "System",
                    icon: "plus.circle",
                    color: .gray
                ),
                WorkHistoryEntry(
                    timestamp: baseTime.addingTimeInterval(300),
                    action: "Picking Started",
                    operatorName: "Capybara",
                    icon: "hand.point.up.braille",
                    color: .blue
                ),
                WorkHistoryEntry(
                    timestamp: baseTime.addingTimeInterval(600),
                    action: "Exception Reported",
                    operatorName: "Capybara",
                    icon: "exclamationmark.triangle",
                    color: .red
                ),
                WorkHistoryEntry(
                    timestamp: baseTime.addingTimeInterval(900),
                    action: "Task Cancelled",
                    operatorName: "Manager",
                    icon: "xmark.circle.fill",
                    color: .red
                )
            ]
        default:
            return []
        }
    }

    // MARK: - Helper Methods

    private func fetchLatestTaskData() async {
        isLoading = true

        do {
            let latestTask = try await OfflineAPIService.shared.fetchTask(id: task.id)
            currentTask = latestTask
            print("TaskPreviewSheet: Updated to latest task data - status: \(latestTask.status), isPaused: \(latestTask.isPaused ?? false)")
        } catch {
            print("Error fetching latest task data: \(error)")
        }

        isLoading = false
    }

    private func resumeTask() async {
        guard let operatorId = staffManager.currentOperator?.id else {
            print("No current operator available for resuming task")
            return
        }

        do {
            let resumedTask = try await OfflineAPIService.shared.performTaskAction(
                taskId: task.id,
                action: .resumeTask,
                operatorId: operatorId,
                payload: nil
            )
            currentTask = resumedTask
            print("Task resumed successfully")
        } catch {
            print("Error resuming task: \(error)")
        }
    }

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

// MARK: - Work History Data Structure

struct WorkHistoryEntry {
    let timestamp: Date
    let action: String
    let operatorName: String
    let icon: String
    let color: Color
}

// MARK: - Work History Components

struct WorkHistoryRow: View {
    let entry: WorkHistoryEntry

    var body: some View {
        HStack(spacing: 12) {
            // Timeline indicator
            VStack {
                Circle()
                    .fill(entry.color)
                    .frame(width: 12, height: 12)
            }

            // Action icon
            Image(systemName: entry.icon)
                .foregroundColor(entry.color)
                .font(.body)
                .frame(width: 20)

            // Content
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.action)
                    .font(.body)
                    .fontWeight(.medium)

                HStack {
                    Text(entry.operatorName)
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Spacer()

                    Text(entry.timestamp, style: .time)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()
        }
        .padding(.vertical, 4)
    }
}

struct CompletionSummaryView: View {
    let task: FulfillmentTask

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider()

            HStack {
                Image(systemName: "checkmark.seal.fill")
                    .foregroundColor(.green)
                Text("✅ Task Completed Successfully")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.green)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Final Details:")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.secondary)

                Text("• All items picked and packed")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Text("• Quality inspection passed")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Text("• Ready for shipment")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.top, 8)
    }
}

struct CancellationSummaryView: View {
    let task: FulfillmentTask

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider()

            HStack {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.red)
                Text("❌ Task Cancelled")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.red)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Reason:")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.secondary)

                Text("• Exception reported during picking")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Text("• Unable to fulfill order")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.top, 8)
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
