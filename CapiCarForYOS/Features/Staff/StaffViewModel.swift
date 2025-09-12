import Foundation

@MainActor
class StaffViewModel: ObservableObject {
    
    // MARK: - Published Properties
    
    @Published var allStaff: [StaffMember] = []
    @Published var currentOperator: StaffMember?
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var checkInMessage: String?
    @Published var isCheckedIn = false
    
    // MARK: - Private Properties
    
    private let apiService: APIService
    
    // MARK: - Initializer
    
    init(apiService: APIService = .shared) {
        self.apiService = apiService
        // When the app starts, immediately try to restore any existing session.
        restoreSession()
    }
    
    // MARK: - Data Loading
    
    func loadAllStaff() {
        guard !isLoading else { return }
        
        isLoading = true
        errorMessage = nil
        
        Task {
            do {
                let staff = try await apiService.fetchAllStaff()
                self.allStaff = staff
                
            } catch {
                self.errorMessage = "Failed to load staff list. Please try again."
                print("Error loading staff: \(error)")
            }
            
            self.isLoading = false
        }
    }
    
    // MARK: - Check-In/Check-Out Operations
    
    func checkIn(staffMember: StaffMember) async {
        isLoading = true
        errorMessage = nil
        checkInMessage = nil
        
        do {
            let result = try await apiService.checkInStaff(
                staffId: staffMember.id,
                action: .checkIn
            )
            
            self.currentOperator = staffMember
            self.isCheckedIn = true
            self.checkInMessage = result.message
            
            // Store check-in state.
            saveSession(staffMember: staffMember)
            
        } catch {
            self.errorMessage = "Check-in failed. Please try again."
            print("Error checking in: \(error)")
        }
        
        self.isLoading = false
    }
    
    func checkOut() async {
        guard let staffToLogOut = currentOperator else {
            errorMessage = "No operator currently checked in"
            return
        }
        
        isLoading = true
        errorMessage = nil
        checkInMessage = nil
        
        do {
            let result = try await apiService.checkInStaff(
                staffId: staffToLogOut.id,
                action: .checkOut
            )
            
            // Clear local state and stored session data.
            clearSession()
            self.checkInMessage = result.message
            
        } catch {
            self.errorMessage = "Check-out failed. Please try again."
            print("Error checking out: \(error)")
        }
        
        self.isLoading = false
    }
    
    // MARK: - Session Management
    
    func restoreSession() {
        // Restore check-in state from UserDefaults when app launches.
        // NOTE: For production, this should read from the secure Keychain.
        let isCheckedIn = UserDefaults.standard.bool(forKey: "isCheckedIn")
        
        if isCheckedIn,
           let operatorId = UserDefaults.standard.string(forKey: "currentOperatorId"),
           let operatorName = UserDefaults.standard.string(forKey: "currentOperatorName") {
            
            self.currentOperator = StaffMember(id: operatorId, name: operatorName)
            self.isCheckedIn = true
        }
    }
    
    private func saveSession(staffMember: StaffMember) {
        // NOTE: For production, this should save to the secure Keychain.
        UserDefaults.standard.set(staffMember.id, forKey: "currentOperatorId")
        UserDefaults.standard.set(staffMember.name, forKey: "currentOperatorName")
        UserDefaults.standard.set(true, forKey: "isCheckedIn")
    }
    
    func clearSession() {
        // Clear session without an API call (for logout or app reset)
        self.currentOperator = nil
        self.isCheckedIn = false
        
        // NOTE: For production, this should clear from the secure Keychain.
        UserDefaults.standard.removeObject(forKey: "currentOperatorId")
        UserDefaults.standard.removeObject(forKey: "currentOperatorName")
        UserDefaults.standard.removeObject(forKey: "isCheckedIn")
    }

    // MARK: - Computed Properties
    
    var currentOperatorName: String {
        currentOperator?.name ?? "No operator selected"
    }
}
