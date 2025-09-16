import Foundation
import Combine

@MainActor
class StaffSessionManager: ObservableObject {
    static let shared = StaffSessionManager()
    
    // MARK: - Published Properties
    
    @Published var currentStaff: StaffMember?
    @Published var isLoggedIn: Bool = false
    
    // MARK: - Private Properties
    
    private let userDefaults = UserDefaults.standard
    private let currentStaffKey = "currentStaff"
    
    // MARK: - Initialization
    
    private init() {
        loadSavedStaff()
    }
    
    // MARK: - Public Methods
    
    /// Log in with a selected staff member
    func login(staff: StaffMember) {
        currentStaff = staff
        isLoggedIn = true
        saveStaff()
        
        print("✅ Staff logged in: \(staff.name) (ID: \(staff.id))")
    }
    
    /// Log out current staff member
    func logout() {
        currentStaff = nil
        isLoggedIn = false
        clearSavedStaff()
        
        print("👋 Staff logged out")
    }
    
    /// Switch to a different staff member
    func switchUser(to staff: StaffMember) {
        logout()
        login(staff: staff)
    }
    
    /// Get current staff ID for API calls
    var currentStaffId: String? {
        return currentStaff?.id
    }
    
    /// Check if user is logged in and return staff ID, otherwise throw error
    func requireStaffId() throws -> String {
        guard let staffId = currentStaffId else {
            throw StaffSessionError.notLoggedIn
        }
        return staffId
    }
    
    // MARK: - Private Methods
    
    private func saveStaff() {
        guard let staff = currentStaff else { return }
        
        if let encoded = try? JSONEncoder().encode(staff) {
            userDefaults.set(encoded, forKey: currentStaffKey)
        }
    }
    
    private func loadSavedStaff() {
        guard let data = userDefaults.data(forKey: currentStaffKey),
              let staff = try? JSONDecoder().decode(StaffMember.self, from: data) else {
            return
        }
        
        currentStaff = staff
        isLoggedIn = true
        
        print("🔄 Restored staff session: \(staff.name)")
    }
    
    private func clearSavedStaff() {
        userDefaults.removeObject(forKey: currentStaffKey)
    }
}

// MARK: - Session Errors

enum StaffSessionError: LocalizedError {
    case notLoggedIn
    
    var errorDescription: String? {
        switch self {
        case .notLoggedIn:
            return "Please log in to perform this action"
        }
    }
}