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
    
    // This is passed in during initialization
    let currentOperator: StaffMember?
    
    // MARK: - Private Properties
    
    private let apiService: APIService
    
    // MARK: - Initializer
    
    init(task: FulfillmentTask, currentOperator: StaffMember?, apiService: APIService = APIService()) {
        self.task = task
        self.currentOperator = currentOperator
        self.apiService = apiService
        
        parseChecklist(from: task.checklistJson)
    }
    
    // MARK: - Checklist Interaction Methods
    
    /// Increments the picked quantity for a specific checklist item.
    func incrementQuantity(for item: ChecklistItem) {
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
    }
    
    /// Decrements the picked quantity for a specific checklist item.
    func decrementQuantity(for item: ChecklistItem) {
        guard let index = checklistItems.firstIndex(where: { $0.id == item.id }) else { return }
        
        var updatedItem = checklistItems[index]
        if updatedItem.quantity_picked > 0 {
            updatedItem.quantity_picked -= 1
            // Always un-mark as completed if quantity is adjusted down.
            updatedItem.is_completed = false
            checklistItems[index] = updatedItem
        }
    }

    /// Toggles the completion status for a single-quantity item.
    func toggleCompletion(for item: ChecklistItem) {
        guard let index = checklistItems.firstIndex(where: { $0.id == item.id }),
              item.quantity_required == 1 else { return }

        var updatedItem = checklistItems[index]
        updatedItem.is_completed.toggle()
        updatedItem.quantity_picked = updatedItem.is_completed ? 1 : 0
        checklistItems[index] = updatedItem
    }
    
    // MARK: - Public Computed Properties for the View
    
    var primaryActionText: String {
        // ... (same as your original implementation)
        switch task.status {
        case .pending: return "Start Picking"
        case .picking: return "Complete Picking"
        case .packed: return "Start Inspection"
        case .inspecting: return "Complete Inspection"
        case .completed: return "Task Completed"
        case .paused: return "Resume Picking"
        case .cancelled: return "Task Cancelled"
        }
    }
    
    var canPerformPrimaryAction: Bool {
        // The logic for enabling/disabling the primary action button.
        switch task.status {
        case .pending, .paused:
            return currentOperator != nil
        case .picking:
            // Can only complete if all items are checked off.
            return currentOperator != nil && checklistItems.allSatisfy { $0.is_completed }
        case .packed, .inspecting:
            return currentOperator != nil
        case .completed, .cancelled:
            return false
        }
    }
    
    // MARK: - Task Actions (Happy Path & Escape Hatches)
    
    func handlePrimaryAction() async {
        // CORRECTED: Added explicit `TaskAction` type to resolve ambiguity.
        switch task.status {
        case .pending, .paused:
            await performTaskAction(TaskAction.startPicking)
        case .picking:
            await performTaskAction(TaskAction.completePicking, payload: ["weight": weightInput, "dimensions": dimensionsInput])
        case .packed:
            await performTaskAction(TaskAction.startInspection)
        case .inspecting:
            await performTaskAction(TaskAction.completeInspection)
        default:
            break
        }
    }

    /// Handles the "Pause Task" escape hatch.
    func pauseTask() async {
        // This would call a new endpoint in your APIService
        // await performTaskAction(.pause)
        print("DEBUG: Pausing task...")
        // For the MVP, we can simulate this locally or assume the action succeeds.
        self.task.status = .paused
    }
    
    /// Handles the "Report Exception" escape hatch.
    func reportException(reason: String) async {
        // This would call a new endpoint
        // await performTaskAction(.reportException, payload: ["reason": reason])
        print("DEBUG: Reporting exception: \(reason)...")
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
            let updatedTask = try await apiService.performTaskAction(
                taskId: task.id,
                action: action,
                operatorId: operatorId,
                payload: payload
            )
            self.task = updatedTask
        } catch {
            self.errorMessage = "Failed to perform task action. Please try again."
            print("Error performing task action: \(error)")
        }
        
        isLoading = false
    }
    
    private func parseChecklist(from jsonString: String) {
        // ... (same as your original implementation)
        guard !jsonString.isEmpty, let data = jsonString.data(using: .utf8) else {
            self.checklistItems = []
            return
        }
        
        do {
            self.checklistItems = try apiService.jsonDecoder.decode([ChecklistItem].self, from: data)
        } catch {
            print("Error parsing checklist JSON: \(error)")
            self.checklistItems = []
            self.errorMessage = "Could not read checklist data."
        }
    }
}
