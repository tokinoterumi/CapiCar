import Foundation

// MARK: - Inspection Criteria Model

struct InspectionCriteria: Identifiable, Codable {
    let id: String
    let title: String
    let description: String
    let isRequired: Bool
    let category: InspectionCategory
    
    enum InspectionCategory: String, CaseIterable, Codable {
        case packaging = "PACKAGING"
        case labeling = "LABELING"
        case contents = "CONTENTS"
        case quality = "QUALITY"
        
        var displayName: String {
            switch self {
            case .packaging: return "Packaging"
            case .labeling: return "Labeling"
            case .contents: return "Contents"
            case .quality: return "Quality"
            }
        }
    }
}

// MARK: - Inspection Action Type

enum InspectionAction {
    case pass
    case fail
}

// MARK: - Inspection View Model

@MainActor
class InspectionViewModel: ObservableObject {
    
    // MARK: - Published Properties
    
    @Published var task: FulfillmentTask
    @Published var inspectionNotes: String = ""
    @Published var checkedCriteria: Set<String> = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var pendingAction: InspectionAction?
    
    // MARK: - Properties
    
    let currentOperator: StaffMember?
    private let offlineAPIService: OfflineAPIService
    
    // MARK: - Computed Properties
    
    let inspectionCriteria: [InspectionCriteria] = [
        InspectionCriteria(
            id: "packaging_integrity",
            title: "Package Integrity",
            description: "Box is undamaged with proper sealing",
            isRequired: true,
            category: .packaging
        ),
        InspectionCriteria(
            id: "correct_items",
            title: "Correct Items",
            description: "All items match the order checklist",
            isRequired: true,
            category: .contents
        ),
        InspectionCriteria(
            id: "item_condition",
            title: "Item Condition",
            description: "Items are undamaged and in good condition",
            isRequired: true,
            category: .quality
        ),
        InspectionCriteria(
            id: "shipping_label",
            title: "Shipping Label",
            description: "Label is properly attached and readable",
            isRequired: true,
            category: .labeling
        ),
        InspectionCriteria(
            id: "packing_materials",
            title: "Packing Materials",
            description: "Appropriate protective materials used",
            isRequired: false,
            category: .packaging
        ),
        InspectionCriteria(
            id: "weight_accuracy",
            title: "Weight Accuracy",
            description: "Package weight matches recorded weight",
            isRequired: false,
            category: .packaging
        ),
        InspectionCriteria(
            id: "documentation",
            title: "Documentation",
            description: "All required documents included",
            isRequired: false,
            category: .contents
        )
    ]
    
    var totalItemsCount: Int {
        // Parse checklist to get total items
        guard let checklistItems = parseChecklistItems() else { return 0 }
        return checklistItems.reduce(0) { $0 + $1.quantity_required }
    }
    
    var packageWeight: String {
        // In a real implementation, this would come from the task data
        return "2.3 kg" // Mock data
    }
    
    var packageDimensions: String {
        // In a real implementation, this would come from the task data
        return "30×20×15 cm" // Mock data
    }
    
    var packagedBy: String {
        // In a real implementation, this would come from the task's packing operator
        return task.currentOperator?.name ?? "Unknown"
    }
    
    var allCriteriaChecked: Bool {
        checkedCriteria.count == inspectionCriteria.count
    }
    
    var requiredCriteriaChecked: Bool {
        let requiredCriteriaIds = Set(inspectionCriteria.filter { $0.isRequired }.map { $0.id })
        return requiredCriteriaIds.isSubset(of: checkedCriteria)
    }
    
    var remainingCriteriaCount: Int {
        inspectionCriteria.count - checkedCriteria.count
    }
    
    var canPassInspection: Bool {
        guard currentOperator != nil else { return false }
        return requiredCriteriaChecked && !isLoading
    }
    
    var canFailInspection: Bool {
        guard currentOperator != nil else { return false }
        return !isLoading
    }
    
    // MARK: - Initializer
    
    init(task: FulfillmentTask, currentOperator: StaffMember?, offlineAPIService: OfflineAPIService? = nil) {
        self.task = task
        self.currentOperator = currentOperator
        self.offlineAPIService = offlineAPIService ?? OfflineAPIService.shared
    }
    
    // MARK: - Actions
    
    func toggleCriteria(_ criteriaId: String, isChecked: Bool) {
        if isChecked {
            checkedCriteria.insert(criteriaId)
        } else {
            checkedCriteria.remove(criteriaId)
        }
    }
    
    func passInspection() async {
        guard canPassInspection,
              let operatorId = currentOperator?.id else {
            errorMessage = "Cannot pass inspection at this time"
            return
        }
        
        pendingAction = .pass
        isLoading = true
        errorMessage = nil
        
        do {
            // Create inspection report
            let inspectionReport = createInspectionReport(passed: true)
            
            // Complete inspection
            let updatedTask = try await offlineAPIService.performTaskAction(
                taskId: task.id,
                action: .completeInspection,
                operatorId: operatorId,
                payload: inspectionReport
            )
            
            self.task = updatedTask
            
            // Create audit log
            let auditLog = AuditLog(
                id: UUID().uuidString,
                timestamp: Date(),
                operatorName: currentOperator?.name ?? "Unknown",
                taskOrderName: task.orderName,
                actionType: "INSPECTION_PASSED",
                details: "Inspection completed successfully. Notes: \(inspectionNotes)"
            )
            
            print("✅ Inspection passed: \(auditLog)")
            
        } catch {
            errorMessage = "Failed to complete inspection: \(error.localizedDescription)"
            print("Error completing inspection: \(error)")
        }
        
        isLoading = false
        pendingAction = nil
    }
    
    func failInspection() async {
        guard canFailInspection,
              let operatorId = currentOperator?.id else {
            errorMessage = "Cannot fail inspection at this time"
            return
        }
        
        pendingAction = .fail
        isLoading = true
        errorMessage = nil
        
        do {
            // Create inspection report
            let inspectionReport = createInspectionReport(passed: false)
            
            // Enter correction mode
            let updatedTask = try await offlineAPIService.performTaskAction(
                taskId: task.id,
                action: .enterCorrection,
                operatorId: operatorId,
                payload: inspectionReport
            )
            
            self.task = updatedTask
            
            // Create audit log
            let auditLog = AuditLog(
                id: UUID().uuidString,
                timestamp: Date(),
                operatorName: currentOperator?.name ?? "Unknown",
                taskOrderName: task.orderName,
                actionType: "INSPECTION_FAILED",
                details: "Inspection failed. Failed criteria: \(getFailedCriteria()). Notes: \(inspectionNotes)"
            )
            
            print("❌ Inspection failed: \(auditLog)")
            
        } catch {
            errorMessage = "Failed to process inspection failure: \(error.localizedDescription)"
            print("Error processing inspection failure: \(error)")
        }
        
        isLoading = false
        pendingAction = nil
    }
    
    // MARK: - Helper Methods
    
    private func createInspectionReport(passed: Bool) -> [String: String] {
        var report: [String: String] = [
            "inspectionResult": passed ? "PASSED" : "FAILED",
            "inspectorId": currentOperator?.id ?? "",
            "inspectorName": currentOperator?.name ?? "",
            "inspectionNotes": inspectionNotes,
            "checkedCriteria": Array(checkedCriteria).joined(separator: ","),
            "totalCriteria": String(inspectionCriteria.count),
            "requiredCriteriaChecked": String(requiredCriteriaChecked)
        ]
        
        if !passed {
            report["failedCriteria"] = getFailedCriteria()
            report["errorType"] = determineErrorType()
        }
        
        return report
    }
    
    private func getFailedCriteria() -> String {
        let failedCriteria = inspectionCriteria.filter { criteria in
            !checkedCriteria.contains(criteria.id)
        }.map { $0.title }
        
        return failedCriteria.joined(separator: ", ")
    }
    
    private func determineErrorType() -> String {
        // Analyze which criteria failed to determine if it's a picking or packing error
        let failedCriteriaIds = Set(inspectionCriteria.map { $0.id }).subtracting(checkedCriteria)
        let failedCriteria = inspectionCriteria.filter { failedCriteriaIds.contains($0.id) }
        
        let hasContentIssues = failedCriteria.contains { $0.category == .contents }
        let hasPackagingIssues = failedCriteria.contains { $0.category == .packaging || $0.category == .labeling }
        
        if hasContentIssues {
            return "PICKING_ERROR"
        } else if hasPackagingIssues {
            return "PACKING_ERROR"
        } else {
            return "QUALITY_ERROR"
        }
    }
    
    private func parseChecklistItems() -> [ChecklistItem]? {
        guard !task.checklistJson.isEmpty,
              let data = task.checklistJson.data(using: .utf8) else {
            return nil
        }
        
        do {
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            return try decoder.decode([ChecklistItem].self, from: data)
        } catch {
            print("Error parsing checklist: \(error)")
            return nil
        }
    }
    
    // MARK: - Inspection Report Summary
    
    func getInspectionSummary() -> String {
        let checkedCount = checkedCriteria.count
        let totalCount = inspectionCriteria.count
        let requiredCount = inspectionCriteria.filter { $0.isRequired }.count
        let requiredChecked = inspectionCriteria.filter { $0.isRequired && checkedCriteria.contains($0.id) }.count
        
        return """
        Inspection Summary:
        • Total Criteria: \(checkedCount)/\(totalCount) checked
        • Required Criteria: \(requiredChecked)/\(requiredCount) passed
        • Inspector: \(currentOperator?.name ?? "Unknown")
        • Notes: \(inspectionNotes.isEmpty ? "None" : inspectionNotes)
        """
    }
}