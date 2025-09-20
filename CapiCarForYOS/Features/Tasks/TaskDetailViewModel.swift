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
            Task {
                await startPicking()
            }
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

        // Sync checklist changes to server
        await syncChecklistToServer()
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

        // Sync checklist changes to server
        await syncChecklistToServer()
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

        // Sync checklist changes to server
        Task {
            await syncChecklistToServer()
        }
    }

    /// Updates the canStartPacking state based on current checklist completion
    private func updateCanStartPacking() {
        let allItemsCompleted = checklistItems.allSatisfy { $0.is_completed }
        canStartPacking = allItemsCompleted

        print("DEBUG: updateCanStartPacking - allItemsCompleted: \(allItemsCompleted), current status: \(task.status)")

        // Handle state transitions based on checklist completion
        if task.status == .pending {
            // Pending should automatically transition to picking when user enters TaskDetailView
            // This happens in init(), not here
            print("DEBUG: Status is pending - should have transitioned to picking in init()")
        } else if task.status == .picking {
            if allItemsCompleted {
                print("DEBUG: Transitioning from picking to picked")
                task.status = .picked
            }
            // If not all items completed, stay in picking
        } else if task.status == .picked {
            if !allItemsCompleted {
                print("DEBUG: Transitioning from picked back to picking")
                task.status = .picking
            }
            // If all items completed, stay in picked
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
        case .picking: return "" // No button when picking
        case .picked: return "Packing Completed"
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
            // Can only start packing if all items are picked
            return canStartPacking
        case .picked:
            // Can start packing if weight/dimensions entered
            return !weightInput.isEmpty && !dimensionsInput.isEmpty
        case .inspecting, .inspected:
            return canCompleteInspection // Can complete inspection only when criteria are met
        case .correcting:
            return true
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
        // In a real app, you might have a task status like .inCorrection
        // For now, we can track this with additional state if needed
        return false // TODO: Implement correction flow state tracking
    }
    
    var needsWeightAndDimensions: Bool {
        return task.status == .picked
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
            // This shouldn't happen since picking auto-completes when all items are done
            // But handle it gracefully
            await completePicking()
            await startPacking()
        case .picked:
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
        await performTaskAction(.startPicking)
    }
    
    /// Complete picking (just finish picking items)
    func completePicking() async {
        await performTaskAction(.completePicking)
    }
    
    /// Start packing with weight and dimensions
    func startPacking() async {
        guard !weightInput.isEmpty && !dimensionsInput.isEmpty else {
            errorMessage = "Please enter weight and dimensions before starting packing."
            return
        }
        
        let payload = [
            "weight": weightInput,
            "dimensions": dimensionsInput
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
    
    /// Complete correction and return to workflow
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
    
    /// Resolve correction and continue workflow
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
        // ... (same as your original implementation)
        guard let operatorId = currentOperator?.id else {
            errorMessage = "No active operator. Please check in on the dashboard."
            return
        }
        
        isLoading = true
        errorMessage = nil
        
        do {
            let updatedTask = try await offlineAPIService.performTaskAction(
                taskId: task.id,
                action: action,
                operatorId: operatorId,
                payload: payload
            )
            self.task = updatedTask
        } catch {
            let isOnline = offlineAPIService.isOnline
            self.errorMessage = isOnline 
                ? "Failed to perform task action. Please try again."
                : "Action saved offline. Will sync when connection is restored."
            print("Error performing task action: \(error)")
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
            // Update the task with the response, but keep our local checklist items
            // since the user might still be interacting with them
            self.task = updatedTask

            // Re-evaluate status after sync to ensure UI consistency
            updateCanStartPacking()
        } catch {
            print("Error syncing checklist: \(error)")
            // Don't show error to user for checklist sync - it's background operation
            // The offline service will handle queuing for later sync

            // Even if sync fails, we should re-evaluate status for UI consistency
            updateCanStartPacking()
        }
    }
    
}
