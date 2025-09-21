import Foundation
import Combine

@MainActor
class StaffManager: ObservableObject {
    
    // MARK: - Published Properties
    
    @Published var currentOperator: StaffMember?
    @Published var availableStaff: [StaffMember] = []
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    
    // MARK: - Private Properties

    private let offlineAPIService = OfflineAPIService.shared
    private let currentOperatorKey = "CapiCar_CurrentOperator"
    
    // MARK: - Initialization
    
    init(apiService: APIService = APIService.shared) {
        // Keep the apiService parameter for compatibility, but use OfflineAPIService
        loadCurrentOperator()

        // Ensure we always have someone selected by loading staff list
        Task {
            await fetchAvailableStaff()
            if currentOperator == nil && !availableStaff.isEmpty {
                selectOperator(availableStaff.first!)
                print("🔧 Auto-selected \(availableStaff.first!.name) on app launch")
            }
        }
    }
    
    // MARK: - Public Methods
    
    func fetchAvailableStaff() async {
        isLoading = true
        errorMessage = nil

        do {
            availableStaff = try await offlineAPIService.fetchAllStaff()
            // Validate that current operator still exists in the updated staff list
            validateCurrentOperator()
        } catch {
            errorMessage = "Failed to load staff list. Please check your connection."
            print("Error fetching staff: \(error)")
        }

        isLoading = false
    }
    
    func checkInOperator(_ staff: StaffMember) async -> Bool {
        isLoading = true
        errorMessage = nil
        
        do {
            let result = try await offlineAPIService.checkInStaff(
                staffId: staff.id,
                action: .checkIn
            )
            
            // Update current operator
            currentOperator = result.staff
            saveCurrentOperator()
            
            print("✅ \(staff.name) checked in successfully")
            isLoading = false
            return true
            
        } catch {
            errorMessage = "Failed to check in \(staff.name). Please try again."
            print("Check-in error: \(error)")
            isLoading = false
            return false
        }
    }
    
    func checkOutCurrentOperator() async -> Bool {
        guard let staffMember = currentOperator else {
            errorMessage = "No operator is currently checked in."
            return false
        }
        
        isLoading = true
        errorMessage = nil
        
        do {
            _ = try await offlineAPIService.checkInStaff(
                staffId: staffMember.id,
                action: .checkOut
            )
            
            // Clear current operator
            currentOperator = nil
            clearCurrentOperator()
            
            print("✅ \(staffMember.name) checked out successfully")
            isLoading = false
            return true
            
        } catch {
            // For development, allow offline check-out
            currentOperator = nil
            clearCurrentOperator()
            print("✅ \(staffMember.name) checked out offline")
            isLoading = false
            return true
        }
    }
    
    func selectOperator(_ staff: StaffMember) {
        currentOperator = staff
        saveCurrentOperator()
    }
    
    func clearOperator() {
        currentOperator = nil
        clearCurrentOperator()
    }
    
    // MARK: - Computed Properties
    
    var isOperatorCheckedIn: Bool {
        return currentOperator != nil
    }
    
    var currentOperatorName: String {
        return currentOperator?.name ?? "No Operator"
    }
    
    // MARK: - Private Methods
    
    private func loadCurrentOperator() {
        guard let operatorData = UserDefaults.standard.data(forKey: currentOperatorKey),
              let staffMember = try? JSONDecoder().decode(StaffMember.self, from: operatorData) else {
            return
        }

        currentOperator = staffMember
    }

    private func validateCurrentOperator() {
        guard let currentOp = currentOperator else { return }

        // Check if current operator still exists in the available staff list
        if !availableStaff.contains(where: { $0.id == currentOp.id }) {
            print("⚠️ Current operator \(currentOp.name) (ID: \(currentOp.id)) no longer exists in staff list. Clearing cached operator.")
            currentOperator = nil
            clearCurrentOperator()
        }
    }
    
    private func saveCurrentOperator() {
        guard let staffMember = currentOperator,
              let operatorData = try? JSONEncoder().encode(staffMember) else {
            return
        }
        
        UserDefaults.standard.set(operatorData, forKey: currentOperatorKey)
    }
    
    private func clearCurrentOperator() {
        UserDefaults.standard.removeObject(forKey: currentOperatorKey)
    }
    
}
