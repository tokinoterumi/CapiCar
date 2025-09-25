import SwiftUI

struct TaskPreviewSheet: View {
    let initialTask: FulfillmentTask
    @EnvironmentObject private var staffManager: StaffManager
    @Environment(\.dismiss) private var dismiss

    // Binding to control navigation to full workflow
    @Binding var showingFullWorkflow: Bool
    @Binding var showingInspectionView: Bool
    @Binding var showingCorrectionFlow: Bool

    // State for current task data
    @State private var currentTask: FulfillmentTask
    @State private var isLoading = true  // Start with loading state
    @State private var workHistory: [WorkHistoryEntry] = []

    // Navigation intent enum
    private enum NavigationIntent {
        case correction
        case inspection
        case workflow
    }

    init(task: FulfillmentTask, showingFullWorkflow: Binding<Bool>, showingInspectionView: Binding<Bool>, showingCorrectionFlow: Binding<Bool>) {
        self.initialTask = task
        self._showingFullWorkflow = showingFullWorkflow
        self._showingInspectionView = showingInspectionView
        self._showingCorrectionFlow = showingCorrectionFlow
        self._currentTask = State(initialValue: task)
    }

    // Use currentTask throughout the view instead of task
    private var task: FulfillmentTask {
        currentTask
    }
    
    var body: some View {
        NavigationStack {
            if isLoading {
                VStack {
                    Spacer()
                    ProgressView("Loading task data...")
                        .font(.headline)
                    Spacer()
                }
            } else {
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
        case .picking, .picked: baseColor = .blue
        case .packed: baseColor = Color(.systemIndigo)
        case .inspecting, .inspected: baseColor = .teal
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

                // Real shipping address data from task
                if let address1 = task.shippingAddress1, !address1.isEmpty {
                    Text(address1)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                if let address2 = task.shippingAddress2, !address2.isEmpty {
                    Text(address2)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                // City, Province, ZIP
                let locationLine = buildLocationLine()
                if !locationLine.isEmpty {
                    Text(locationLine)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                // Phone number if available
                if let phone = task.shippingPhone, !phone.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "phone.fill")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(phone)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
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
                        ItemPreviewRow(item: item)
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
                Text("Exception Reported")
                    .font(.headline)
                    .fontWeight(.semibold)
            }

            if let reason = task.exceptionReason, !reason.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Issue Type")
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
                    Text("Reported")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.secondary)

                    Text(formatExceptionDate(loggedAt))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            if let notes = task.exceptionNotes, !notes.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Description")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.secondary)

                    Text(notes)
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

            Text("This task has been moved to the exception pool and requires attention before it can proceed.")
                .font(.caption)
                .foregroundColor(.secondary)
                .italic()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color.red.opacity(0.05))
        .cornerRadius(12)
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
                Text("Work History")
                    .font(.headline)
                    .fontWeight(.semibold)
            }

            VStack(spacing: 12) {
                if workHistory.isEmpty {
                    Text("No work history available")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .padding()
                } else {
                    ForEach(workHistory, id: \.timestamp) { entry in
                        WorkHistoryRow(entry: entry)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(12)
    }

    private var actionButtonSection: some View {
        // Capture navigation intent at render time to prevent timing issues
        let navigationIntent = determineNavigationIntent()

        return VStack(spacing: 12) {
            if canStartTask {
                PrimaryButton(
                    title: primaryActionTitle,
                    action: {
                        Task {
                            print("🔍 NAVIGATION DEBUG:")
                            print("  - Task status at button press: \(task.status.rawValue)")
                            print("  - Task isPaused: \(task.isPaused ?? false)")
                            print("  - Button title: \(primaryActionTitle)")
                            print("  - Navigation intent: \(navigationIntent)")

                            // If this is a paused task, resume it first
                            if task.isPaused == true {
                                print("  - Resuming paused task...")
                                await resumeTask()
                                print("  - Task resumed. New status: \(task.status.rawValue)")
                            }

                            await MainActor.run {
                                dismiss() // Close preview sheet

                                // Navigate based on captured intent (from render time)
                                switch navigationIntent {
                                case .correction:
                                    print("  - Navigating to CorrectionFlowView")
                                    showingCorrectionFlow = true
                                case .inspection:
                                    print("  - Navigating to InspectionView")
                                    showingInspectionView = true
                                case .workflow:
                                    print("  - Navigating to TaskDetailView (fullWorkflow)")
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
            case .correctionNeeded: return "Resume Correction" // Add this case for paused correction tasks
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

    private var shouldNavigateToCorrection: Bool {
        // Check if this is a correction task
        return task.status == .correctionNeeded
    }

    private func determineNavigationIntent() -> NavigationIntent {
        // Use the current (fresh) task status for navigation decisions
        // This ensures we navigate based on the actual database state, not stale memory
        if task.status == .correctionNeeded {
            return .correction
        } else if task.status == .packed || task.status == .inspecting || task.status == .inspected {
            return .inspection
        } else {
            return .workflow
        }
    }

    // MARK: - Helper Methods

    private func buildLocationLine() -> String {
        var components: [String] = []

        if let city = task.shippingCity, !city.isEmpty {
            components.append(city)
        }

        if let province = task.shippingProvince, !province.isEmpty {
            components.append(province)
        }

        if let zip = task.shippingZip, !zip.isEmpty {
            components.append(zip)
        }

        return components.joined(separator: ", ")
    }

    private func fetchLatestTaskData() async {
        isLoading = true

        print("🔍 FETCH DEBUG: Starting to fetch task \(task.id)")
        print("🔍 FETCH DEBUG: Initial task status: \(initialTask.status.rawValue)")
        print("🔍 FETCH DEBUG: Current task status before fetch: \(currentTask.status.rawValue)")

        // Check if we're transitioning from online to offline with fresh data
        let isOnline = OfflineAPIService.shared.isOnline
        print("🔍 FETCH DEBUG: Currently online: \(isOnline)")

        // If we're offline and this TaskPreviewSheet was just created with fresh online data,
        // use that data instead of fetching stale cached data
        if !isOnline {
            print("🔍 FETCH DEBUG: Device is offline - using existing task data to prevent stale override")
            print("🔍 FETCH DEBUG: Current task already has status: \(currentTask.status.rawValue)")

            // Still try to fetch work history if possible
            do {
                let history = try await OfflineAPIService.shared.fetchTaskWorkHistory(taskId: task.id)
                workHistory = history
                print("TaskPreviewSheet: Fetched \(history.count) work history entries (offline)")
            } catch {
                print("🔍 FETCH DEBUG: Could not fetch work history offline: \(error)")
                workHistory = [] // Ensure we have empty array instead of undefined state
            }

            isLoading = false
            return
        }

        do {
            let latestTask = try await OfflineAPIService.shared.fetchTask(id: task.id)
            print("🔍 FETCH DEBUG: Fetched task status: \(latestTask.status.rawValue)")
            print("🔍 FETCH DEBUG: Fetched task isPaused: \(latestTask.isPaused ?? false)")
            print("🔍 FETCH DEBUG: Fetched task currentOperator: \(latestTask.currentOperator?.name ?? "nil")")

            // Only update if the fetched task seems more recent or valid
            // If API fetch succeeds, trust it over current data
            // If it returns obviously stale data (different status), be careful
            let shouldUpdate = isOnline ? true : (latestTask.status != currentTask.status)

            if shouldUpdate {
                currentTask = latestTask
                print("TaskPreviewSheet: Updated to latest task data - status: \(latestTask.status), isPaused: \(latestTask.isPaused ?? false)")
            } else {
                print("🔍 FETCH DEBUG: Keeping current task data - fetched data appears stale")
            }

            // Fetch work history
            let history = try await OfflineAPIService.shared.fetchTaskWorkHistory(taskId: task.id)
            workHistory = history
            print("TaskPreviewSheet: Fetched \(history.count) work history entries")
        } catch {
            print("🔍 FETCH DEBUG: Error fetching task data: \(error)")
            print("🔍 FETCH DEBUG: Keeping existing fresh data instead of falling back to potentially stale data")

            // Don't update currentTask on error - keep the fresh data we have
            // Still try to get work history if possible
            do {
                let history = try await OfflineAPIService.shared.fetchTaskWorkHistory(taskId: task.id)
                workHistory = history
                print("TaskPreviewSheet: Fetched \(history.count) work history entries (after fetch error)")
            } catch {
                print("🔍 FETCH DEBUG: Could not fetch work history: \(error)")
                workHistory = []
            }
        }

        isLoading = false
        print("🔍 FETCH DEBUG: Finished fetching, isLoading set to false")
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

// MARK: - Item Preview Row Component

struct ItemPreviewRow: View {
    let item: ChecklistItem
    @State private var isExpanded = false

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .font(.body)
                    .lineLimit(isExpanded ? nil : 2)
                    .multilineTextAlignment(.leading)
                    .onTapGesture {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isExpanded.toggle()
                        }
                    }

                Text(item.sku)
                    .font(.caption)
                    .foregroundColor(.secondary)

                // Show expand/collapse hint for long text
                if !isExpanded && item.name.count > 40 {
                    Text("Tap to expand")
                        .font(.caption2)
                        .foregroundColor(.blue)
                        .padding(.top, 1)
                }
            }

            Spacer()

            Text("Qty: \(item.quantity_required)")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Work History Data Structure
// WorkHistoryEntry is now defined in Models/TaskModels.swift

// MARK: - Work History Components

struct WorkHistoryRow: View {
    let entry: WorkHistoryEntry

    var body: some View {
        HStack(spacing: 12) {
            // Action icon
            Image(systemName: entry.icon)
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

                    Text(formatTimestamp(entry.timestamp))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()
        }
        .padding(.vertical, 4)
    }

    // Helper function to format timestamp string
    private func formatTimestamp(_ timestampString: String) -> String {
        let formatter = ISO8601DateFormatter()
        if let date = formatter.date(from: timestampString) {
            let timeFormatter = DateFormatter()
            timeFormatter.timeStyle = .short
            return timeFormatter.string(from: date)
        }
        return timestampString // fallback to original string
    }
}

#if DEBUG
struct TaskPreviewSheet_Previews: PreviewProvider {
    static var previews: some View {
        var mockTask = FulfillmentTask(
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

        // Add shipping address data for preview
        mockTask.shippingAddress1 = "1 Apple Park Way"
        mockTask.shippingAddress2 = "Building 4"
        mockTask.shippingCity = "Cupertino"
        mockTask.shippingProvince = "CA"
        mockTask.shippingZip = "95014"
        mockTask.shippingPhone = "+1 (408) 996-1010"
        
        let mockStaffManager = StaffManager()
        mockStaffManager.currentOperator = StaffMember(id: "staff1", name: "Test User")
        
        return TaskPreviewSheet(
            task: mockTask,
            showingFullWorkflow: .constant(false),
            showingInspectionView: .constant(false),
            showingCorrectionFlow: .constant(false)
        )
        .environmentObject(mockStaffManager)
        .environmentObject(DashboardViewModel())
    }
}
#endif
