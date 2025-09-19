import Foundation

// MARK: - Correction Error Type

enum CorrectionErrorType: String, CaseIterable {
    case pickingError = "PICKING_ERROR"
    case packingError = "PACKING_ERROR"
    
    var displayName: String {
        switch self {
        case .pickingError: return "Picking Error"
        case .packingError: return "Packing Error"
        }
    }
}

// MARK: - Cost Impact Type

enum CostImpactType: String, CaseIterable {
    case affectsCost = "AFFECTS_COST"
    case noCostImpact = "NO_COST_IMPACT"
    
    var displayName: String {
        switch self {
        case .affectsCost: return "Affects Shipping Cost"
        case .noCostImpact: return "No Cost Impact"
        }
    }
}

// MARK: - Correction Flow ViewModel

@MainActor
class CorrectionFlowViewModel: ObservableObject {
    
    // MARK: - Published Properties
    
    @Published var task: FulfillmentTask
    @Published var selectedErrorType: CorrectionErrorType?
    @Published var costImpact: CostImpactType?
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    // MARK: - Private Properties
    
    private let currentOperator: StaffMember?
    private let offlineAPIService: OfflineAPIService
    
    // MARK: - Initializer
    
    init(task: FulfillmentTask, currentOperator: StaffMember?, offlineAPIService: OfflineAPIService? = nil) {
        self.task = task
        self.currentOperator = currentOperator
        self.offlineAPIService = offlineAPIService ?? OfflineAPIService.shared

        // Auto-start correction when user enters CorrectionFlowView from correctionNeeded state
        if task.status == .correctionNeeded {
            Task {
                await startCorrection()
            }
        }
    }
    
    // MARK: - Computed Properties
    
    var canStartCorrection: Bool {
        guard let errorType = selectedErrorType else { return false }
        
        switch errorType {
        case .pickingError:
            return true // Can always start picking correction
        case .packingError:
            return costImpact != nil // Need cost impact decision for packing errors
        }
    }
    
    var correctionPlan: String {
        guard let errorType = selectedErrorType else { return "" }
        
        switch errorType {
        case .pickingError:
            return "1. Review and re-pick incorrect items\n2. Update checklist\n3. Proceed to packing"
        case .packingError:
            if costImpact == .affectsCost {
                return "1. Void current shipping label\n2. Repack items correctly\n3. Generate new shipping label"
            } else {
                return "1. Repack items correctly\n2. Reuse existing shipping label"
            }
        }
    }
    
    // MARK: - Actions
    
    func startCorrection() async {
        guard let errorType = selectedErrorType,
              let operatorId = currentOperator?.id else {
            errorMessage = "Missing required information to start correction"
            return
        }
        
        isLoading = true
        errorMessage = nil
        
        do {
            // Prepare payload with correction details
            var payload = [
                "errorType": errorType.rawValue,
                "correctionPlan": correctionPlan
            ]
            
            if let impact = costImpact {
                payload["costImpact"] = impact.rawValue
            }
            
            // Enter correction mode
            let updatedTask = try await offlineAPIService.performTaskAction(
                taskId: task.id,
                action: .enterCorrection,
                operatorId: operatorId,
                payload: payload
            )
            
            self.task = updatedTask
            
            // Create audit log entry for correction start
            let auditLog = AuditLog(
                id: UUID().uuidString,
                timestamp: Date(),
                operatorName: currentOperator?.name ?? "Unknown",
                taskOrderName: task.orderName,
                actionType: "CORRECTION_STARTED",
                details: "Error: \(errorType.displayName), Plan: \(correctionPlan)"
            )
            
            // Log the correction start (in production, this would be saved)
            print("📝 Correction started: \(auditLog)")
            
        } catch {
            errorMessage = "Failed to start correction: \(error.localizedDescription)"
            print("Error starting correction: \(error)")
        }
        
        isLoading = false
    }
    
    func resetSelection() {
        selectedErrorType = nil
        costImpact = nil
        errorMessage = nil
    }
    
    // MARK: - Helper Methods
    
    func getNextSteps() -> [String] {
        guard let errorType = selectedErrorType else { return [] }
        
        switch errorType {
        case .pickingError:
            return [
                "Return to picking area",
                "Review original order requirements", 
                "Re-pick any incorrect items",
                "Update checklist as items are corrected",
                "Proceed to packing when complete"
            ]
        case .packingError:
            if costImpact == .affectsCost {
                return [
                    "Void current shipping label in system",
                    "Unpack and repack items correctly",
                    "Generate new shipping label",
                    "Proceed to final inspection"
                ]
            } else {
                return [
                    "Unpack and repack items correctly",
                    "Ensure existing label remains usable",
                    "Proceed to final inspection"
                ]
            }
        }
    }
    
    func getEstimatedTime() -> String {
        guard let errorType = selectedErrorType else { return "Unknown" }
        
        switch errorType {
        case .pickingError:
            return "5-15 minutes"
        case .packingError:
            return costImpact == .affectsCost ? "10-20 minutes" : "5-10 minutes"
        }
    }
}