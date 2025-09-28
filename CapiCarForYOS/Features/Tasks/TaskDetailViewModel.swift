import Foundation

@MainActor
class TaskDetailViewModel: ObservableObject {
    
    // MARK: - Published Properties
    
    @Published var task: FulfillmentTask
    @Published var checklistItems: [ChecklistItem] = []
    @Published var canStartPacking: Bool = false
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    // State for data entry when completing picking
    @Published var weightInput: String = ""
    @Published var dimensionsInput: String = ""

    // Dimension dropdown options
    let dimensionOptions = [60, 80, 100, 120, 140, 160, 180, 200]
    @Published var selectedDimension: Int = 60
    
    // State for correction flow
    @Published var correctionErrorType: String = ""
    @Published var correctionNotes: String = ""
    @Published var newTrackingNumber: String = ""
    
    // State for exception reporting
    @Published var exceptionReason: String = ""
    @Published var exceptionNotes: String = ""
    
    // State for item highlighting
    
    // This is passed in during initialization
    let currentOperator: StaffMember?
    
    // State for inspection completion - would be updated by InspectionView when criteria change
    @Published var canCompleteInspection: Bool = false

    // MARK: - Private Properties

    private let offlineAPIService: OfflineAPIService
    
    // MARK: - Initializer
    
    init(task: FulfillmentTask, currentOperator: StaffMember?, offlineAPIService: OfflineAPIService? = nil) {
        self.task = task
        self.currentOperator = currentOperator
        self.offlineAPIService = offlineAPIService ?? OfflineAPIService.shared

        parseChecklist(from: task.checklistJson)
        updateCanStartPacking()

        // Auto-start picking when user enters TaskDetailView from pending state
        if task.status == .pending {
            print("DEBUG: Task is pending - initiating automatic picking transition")

            Task {
                print("DEBUG: Starting automatic picking action...")
                await startPicking()
                print("DEBUG: Automatic picking action completed, status: \(self.task.status)")
            }
        } else {
            print("DEBUG: Task status is \(task.status) - no automatic transition needed")
        }
    }
    
    // MARK: - Checklist Interaction Methods
    
    /// Increments the picked quantity for a specific checklist item.
    func incrementQuantity(for item: ChecklistItem) async {
        guard let index = checklistItems.firstIndex(where: { $0.id == item.id }) else { return }

        var updatedItem = checklistItems[index]
        if updatedItem.quantity_picked < updatedItem.quantity_required {
            updatedItem.quantity_picked += 1

            // If quantity matches, automatically mark as completed.
            if updatedItem.quantity_picked == updatedItem.quantity_required {
                updatedItem.is_completed = true
            }

            checklistItems[index] = updatedItem
        }

        // Update button state
        updateCanStartPacking()

        // No immediate sync - checklist is UI-only until task completion
    }
    
    /// Decrements the picked quantity for a specific checklist item.
    func decrementQuantity(for item: ChecklistItem) async {
        guard let index = checklistItems.firstIndex(where: { $0.id == item.id }) else { return }

        var updatedItem = checklistItems[index]
        if updatedItem.quantity_picked > 0 {
            updatedItem.quantity_picked -= 1
            // Always un-mark as completed if quantity is adjusted down.
            updatedItem.is_completed = false
            checklistItems[index] = updatedItem
        }

        // Update button state
        updateCanStartPacking()

        // No immediate sync - checklist is UI-only until task completion
    }

    /// Toggles the completion status for a single-quantity item.
    func toggleCompletion(for item: ChecklistItem) {
        guard let index = checklistItems.firstIndex(where: { $0.id == item.id }),
              item.quantity_required == 1 else { return }

        var updatedItem = checklistItems[index]
        updatedItem.is_completed.toggle()
        updatedItem.quantity_picked = updatedItem.is_completed ? 1 : 0
        checklistItems[index] = updatedItem

        // Update button state
        updateCanStartPacking()

        // No immediate sync - checklist is UI-only until task completion
    }

    /// Updates the canStartPacking state based on current checklist completion
    private func updateCanStartPacking() {
        let allItemsCompleted = checklistItems.allSatisfy { $0.is_completed }
        canStartPacking = allItemsCompleted

        print("DEBUG: updateCanStartPacking - allItemsCompleted: \(allItemsCompleted), current status: \(task.status)")
        print("DEBUG: UI State - canStartPacking: \(canStartPacking), primaryActionText: '\(primaryActionText)', canPerformPrimaryAction: \(canPerformPrimaryAction)")

        // Handle state transitions based on checklist completion
        // SIMPLIFIED DESIGN: Checklist completion is purely UI state
        // No automatic status transitions based on checklist completion
        // Status only changes when user explicitly completes the packing with weight/dimensions

        if task.status == .pending {
            print("DEBUG: Status is pending - should transition to picking in init()")
        } else if task.status == .picking {
            print("DEBUG: Status is picking - checklist completion is UI-only")
        } else if task.status == .correcting {
            print("DEBUG: Status is correcting - maintaining correcting status")
        }

        print("DEBUG: Final status: \(task.status)")
    }

    // MARK: - Public Computed Properties for the View
    
    var primaryActionText: String {
        // Paused tasks should not show any primary action button
        // Resume action should only be available from TaskPreviewSheet
        if task.isPaused == true {
            return ""
        }

        switch task.status {
        case .picking: return "Packing Completed"
        case .inspecting: return "Complete Inspection"
        case .correcting: return "Complete Correction"
        default: return ""
        }
    }
    
    var canPerformPrimaryAction: Bool {
        guard currentOperator != nil else { return false }

        // Paused tasks should not show any primary action button
        // Resume action should only be available from TaskPreviewSheet
        if task.isPaused == true {
            return false
        }

        switch task.status {
        case .picking:
            // During picking: button enabled only when all items are completed (no weight required yet)
            return canStartPacking
        case .inspecting:
            return canCompleteInspection // Can complete inspection only when criteria are met
        case .correcting:
            // For correction workflow, require weight (dimensions selected from dropdown)
            return !weightInput.isEmpty
        case .pending, .packed, .correctionNeeded, .completed, .cancelled:
            return false
        }
    }
    
    // MARK: - Validation Properties
    
    var canEnterCorrection: Bool {
        return currentOperator != nil && !correctionErrorType.isEmpty
    }
    
    var canResolveCorrection: Bool {
        return currentOperator != nil
    }
    
    var canReportException: Bool {
        return currentOperator != nil && !exceptionReason.isEmpty
    }
    
    // MARK: - UI State Properties
    
    var isInCorrectionFlow: Bool {
        return task.status == .correctionNeeded || task.status == .correcting
    }
    
    var needsWeightAndDimensions: Bool {
        return task.status == .picking && canStartPacking
    }
    
    var checklistCompletionRate: Double {
        guard !checklistItems.isEmpty else { return 0.0 }
        let completedCount = checklistItems.filter { $0.is_completed }.count
        return Double(completedCount) / Double(checklistItems.count)
    }
    
    var isReadyForInspection: Bool {
        return task.status == .packed || task.status == .inspecting
    }
    
    var canUseDetailedInspection: Bool {
        return isReadyForInspection && currentOperator != nil
    }
    
    // MARK: - Task Actions (Happy Path & Escape Hatches)
    
    func handlePrimaryAction() async {
        // Paused tasks should not have primary actions in TaskDetailView
        // Resume functionality is only available from TaskPreviewSheet
        guard task.isPaused != true else { return }

        switch task.status {
        case .picking:
            // Directly transition from picking to packed with weight/dimensions
            await startPacking()
        case .inspecting:
            await completeInspection()
        case .correcting:
            await completeCorrection()
        default:
            break
        }
    }

    // MARK: - Specific Action Methods
    
    /// Start picking process
    func startPicking() async {
        print("DEBUG: startPicking() called")
        await performTaskAction(.startPicking)
        print("DEBUG: startPicking() completed, status is now: \(task.status)")
    }
    
    // completePicking() removed - no longer needed in simplified design
    
    /// Start packing with weight, dimensions, and final checklist
    func startPacking() async {
        guard !weightInput.isEmpty else {
            errorMessage = "Please enter weight before starting packing."
            return
        }

        guard canStartPacking else {
            errorMessage = "Please complete all checklist items before packing."
            return
        }

        // Include checklist in the payload for final submission
        let checklistData = try? JSONEncoder().encode(checklistItems)
        let checklistString = checklistData.flatMap { String(data: $0, encoding: .utf8) } ?? "[]"

        let payload = [
            "weight": weightInput,
            "dimensions": String(selectedDimension),
            "checklist": checklistString
        ]
        await performTaskAction(.startPacking, payload: payload)
    }
    
    /// Start inspection process
    func startInspection() async {
        await performTaskAction(.startInspection)
    }
    
    /// Complete inspection successfully
    func completeInspection() async {
        await performTaskAction(.completeInspection)
    }
    
    /// Start correction process
    func startCorrection() async {
        await performTaskAction(.startCorrection)
    }
    
    /// Complete correction and finish task (no further inspection needed)
    func completeCorrection() async {
        await performTaskAction(.resolveCorrection)
    }
    
    /// Enter correction due to failed inspection
    func enterCorrection() async {
        guard !correctionErrorType.isEmpty else {
            errorMessage = "Please specify the error type before entering correction."
            return
        }
        
        var payload = ["errorType": correctionErrorType]
        if !correctionNotes.isEmpty {
            payload["notes"] = correctionNotes
        }
        
        await performTaskAction(.enterCorrection, payload: payload)
    }
    
    /// Resolve correction and complete task (no further inspection needed)
    func resolveCorrection() async {
        var payload: [String: String] = [:]
        if !newTrackingNumber.isEmpty {
            payload["newTrackingNumber"] = newTrackingNumber
        }
        
        await performTaskAction(.resolveCorrection, payload: payload.isEmpty ? nil : payload)
    }
    
    /// Report general exception
    func reportException() async {
        guard !exceptionReason.isEmpty else {
            errorMessage = "Please specify the reason before reporting exception."
            return
        }
        
        var payload = ["reason": exceptionReason]
        if !exceptionNotes.isEmpty {
            payload["notes"] = exceptionNotes
        }
        
        await performTaskAction(.reportException, payload: payload)
    }
    
    /// Convenience method for reporting exception with reason
    func reportException(reason: String, notes: String = "") async {
        exceptionReason = reason
        exceptionNotes = notes
        await reportException()
    }
    
    /// Pause task (local state change for MVP)
    func pauseTask() async {
        await performTaskAction(.pauseTask)
    }

    /// Resume a paused task
    func resumeTask() async {
        // Use the dedicated RESUME_TASK action to let backend handle the resume logic
        await performTaskAction(.resumeTask)
    }
    
    /// Cancel task - leads to cancelled state, freeing up operators
    func cancelTask() async {
        await performTaskAction(.cancelTask)
    }

    // MARK: - Private Helper Methods
    
    private func performTaskAction(_ action: TaskAction, payload: [String: String]? = nil) async {
        print("DEBUG: performTaskAction called with action: \(action)")

        guard let operatorId = currentOperator?.id else {
            print("DEBUG: No current operator available")
            errorMessage = "No active operator. Please check in on the dashboard."
            return
        }

        print("DEBUG: Operator ID: \(operatorId), starting action...")
        isLoading = true
        errorMessage = nil

        do {
            let updatedTask = try await offlineAPIService.performTaskAction(
                taskId: task.id,
                action: action,
                operatorId: operatorId,
                payload: payload
            )
            print("DEBUG: Action succeeded, updating task from \(task.status) to \(updatedTask.status)")
            await MainActor.run {
                self.task = updatedTask
            }
        } catch {
            let isOnline = offlineAPIService.isOnline
            self.errorMessage = isOnline
                ? "Failed to perform task action. Please try again."
                : "Action saved offline. Will sync when connection is restored."
            print("DEBUG: Error performing task action \(action): \(error)")
        }

        isLoading = false
    }
    
    private func parseChecklist(from jsonString: String) {
        guard !jsonString.isEmpty, let data = jsonString.data(using: .utf8) else {
            self.checklistItems = []
            return
        }

        print("DEBUG: Raw JSON string: \(jsonString)")

        do {
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase

            // First, try to decode as an array directly
            if let checklistArray = try? decoder.decode([ChecklistItem].self, from: data) {
                print("DEBUG: Successfully decoded as direct array with \(checklistArray.count) items")
                self.checklistItems = checklistArray
                return
            }

            // If that fails, try to decode as a dictionary with a "checklist" or "items" key
            if let jsonObject = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                print("DEBUG: Checklist JSON structure: \(jsonObject.keys)")

                // Try different possible keys
                var itemsArray: [[String: Any]]?
                if let items = jsonObject["checklist"] as? [[String: Any]] {
                    itemsArray = items
                } else if let items = jsonObject["items"] as? [[String: Any]] {
                    itemsArray = items
                } else if let items = jsonObject["checklist_items"] as? [[String: Any]] {
                    itemsArray = items
                } else if let jsonString = jsonObject["json"] as? String {
                    print("DEBUG: Found nested JSON string: \(jsonString)")
                    // Handle nested JSON string
                    if let nestedData = jsonString.data(using: .utf8) {
                        do {
                            let nestedObject = try JSONSerialization.jsonObject(with: nestedData)
                            if let nestedArray = nestedObject as? [[String: Any]] {
                                print("DEBUG: Successfully parsed nested JSON array with \(nestedArray.count) items")
                                itemsArray = nestedArray
                            } else if let singleItem = nestedObject as? [String: Any] {
                                print("DEBUG: Found single item, converting to array")
                                itemsArray = [singleItem]
                            } else {
                                print("DEBUG: Nested JSON is neither array nor object")
                            }
                        } catch {
                            print("DEBUG: Error parsing nested JSON: \(error)")
                        }
                    }
                }

                if let items = itemsArray {
                    print("DEBUG: Attempting to decode \(items.count) items")
                    let itemsData = try JSONSerialization.data(withJSONObject: items)
                    do {
                        self.checklistItems = try decoder.decode([ChecklistItem].self, from: itemsData)
                        print("DEBUG: Successfully decoded \(self.checklistItems.count) checklist items")
                        return
                    } catch {
                        print("DEBUG: Error decoding ChecklistItem array: \(error)")
                        // Don't return here, let it fall through to empty array
                    }
                }
            }

            // If all else fails, set empty array
            print("DEBUG: Could not find checklist items in JSON structure")
            self.checklistItems = []

        } catch {
            print("Error parsing checklist JSON: \(error)")
            print("DEBUG: Raw JSON string: \(jsonString)")
            self.checklistItems = []
            // Only show error message in non-preview context
            #if !DEBUG
            self.errorMessage = "Could not read checklist data."
            #endif
        }
    }
    
    /// Syncs the current checklist state to the server
    private func syncChecklistToServer() async {
        guard let operatorId = currentOperator?.id else { return }
        
        do {
            let updatedTask = try await offlineAPIService.updateTaskChecklist(
                taskId: task.id,
                checklist: checklistItems,
                operatorId: operatorId
            )
            // Update the task with the response, but preserve any status changes that might be in progress
            // Only update if the returned status is more recent or different
            let oldStatus = self.task.status
            let newStatus = updatedTask.status

            // Update the task but preserve checklist items that user might still be interacting with
            let mergedTask = updatedTask
            // Keep our current checklist since user might still be modifying it
            // The checklist sync is separate from task status changes

            // Only update status if it's actually different and we're not in the middle of a status transition
            if !isLoading && (newStatus != oldStatus) {
                print("DEBUG: Updating task status from sync: \(oldStatus) → \(newStatus)")
                self.task = mergedTask
            } else if isLoading {
                print("DEBUG: Skipping task update - action in progress")
            } else {
                print("DEBUG: Task status unchanged from sync: \(oldStatus)")
            }
        } catch {
            print("Error syncing checklist: \(error)")
            // Don't show error to user for checklist sync - it's background operation
            // The offline service will handle queuing for later sync

            // Don't re-evaluate status on sync failure to avoid race conditions
            // The UI state should remain consistent with user actions
            print("DEBUG: Checklist sync failed - keeping current UI state")
        }
    }
    
}
