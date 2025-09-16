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
    
    private let apiService: APIService
    private let currentOperatorKey = "CapiCar_CurrentOperator"
    
    // MARK: - Initialization
    
    init(apiService: APIService = APIService.shared) {
        self.apiService = apiService
        loadCurrentOperator()
    }
    
    // MARK: - Public Methods
    
    func fetchAvailableStaff() async {
        isLoading = true
        errorMessage = nil
        
        do {
            availableStaff = try await apiService.fetchAllStaff()
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
            let result = try await apiService.checkInStaff(
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
            _ = try await apiService.checkInStaff(
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
    
    // MARK: - Mock Data (Remove in production)
    
    func loadMockStaff() {
        availableStaff = [
            StaffMember(id: "staff_001", name: "Alex Johnson"),
            StaffMember(id: "staff_002", name: "Maria Garcia"),
            StaffMember(id: "staff_003", name: "David Chen"),
            StaffMember(id: "staff_004", name: "Sarah Wilson"),
            StaffMember(id: "staff_005", name: "Mike Rodriguez")
        ]
    }
}
