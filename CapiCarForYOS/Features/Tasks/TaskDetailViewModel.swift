import Foundation

@MainActor
class TaskDetailViewModel: ObservableObject {
    
    // MARK: - Published Properties
    
    @Published var task: FulfillmentTask
    @Published var checklistItems: [ChecklistItem] = []
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
    
    // MARK: - Private Properties
    
    private let offlineAPIService: OfflineAPIService
    
    // MARK: - Initializer
    
    init(task: FulfillmentTask, currentOperator: StaffMember?, offlineAPIService: OfflineAPIService? = nil) {
        self.task = task
        self.currentOperator = currentOperator
        self.offlineAPIService = offlineAPIService ?? OfflineAPIService.shared
        
        parseChecklist(from: task.checklistJson)
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
        
        // Sync checklist changes to server
        Task {
            await syncChecklistToServer()
        }
    }
    
    // MARK: - Public Computed Properties for the View
    
    var primaryActionText: String {
        switch task.status {
        case .pending: return "Start Picking"
        case .picking: return "Complete Picking"
        case .picked: return "Start Packing"
        case .packed: return "Quick Inspection Pass"
        case .inspecting: return "Quick Inspection Pass"
        case .correctionNeeded: return "Start Correction"
        case .correcting: return "Complete Correction"
        case .completed: return "Task Completed"
        case .paused: return "Resume Picking"
        case .cancelled: return "Task Cancelled"
        }
    }
    
    var canPerformPrimaryAction: Bool {
        guard currentOperator != nil else { return false }
        
        switch task.status {
        case .pending, .paused:
            return true
        case .picking:
            // Can only complete if all items are checked off
            return checklistItems.allSatisfy { $0.is_completed }
        case .picked:
            // Can start packing if weight/dimensions entered
            return !weightInput.isEmpty && !dimensionsInput.isEmpty
        case .packed:
            return true
        case .inspecting:
            return true // Can complete inspection (pass) via main button
        case .correctionNeeded:
            return true
        case .correcting:
            return true
        case .completed, .cancelled:
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
        switch task.status {
        case .pending, .paused:
            await startPicking()
        case .picking:
            await completePicking()
        case .picked:
            await startPacking()
        case .packed:
            await startInspection()
        case .inspecting:
            await completeInspection()
        case .correctionNeeded:
            await startCorrection()
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
        // For MVP, we simulate pausing locally
        // In production, this would call a pause API endpoint
        self.task.status = .paused
        print("DEBUG: Task paused locally")
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
        
        do {
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            self.checklistItems = try decoder.decode([ChecklistItem].self, from: data)
        } catch {
            print("Error parsing checklist JSON: \(error)")
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
        } catch {
            print("Error syncing checklist: \(error)")
            // Don't show error to user for checklist sync - it's background operation
            // The offline service will handle queuing for later sync
        }
    }
    
}
