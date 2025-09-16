import Foundation
import Combine

@MainActor
class AuthenticationManager: ObservableObject {
    
    // MARK: - Published Properties
    
    @Published var isAuthenticated: Bool = false
    @Published var currentStaff: StaffMember?
    
    // MARK: - Dependencies
    
    private let staffSessionManager = StaffSessionManager.shared
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Initialization
    
    init() {
        // Observe staff session changes
        staffSessionManager.$isLoggedIn
            .assign(to: \.isAuthenticated, on: self)
            .store(in: &cancellables)
        
        staffSessionManager.$currentStaff
            .assign(to: \.currentStaff, on: self)
            .store(in: &cancellables)
    }
    
    // MARK: - Authentication Methods
    
    func signOut() {
        staffSessionManager.logout()
    }
    
    // MARK: - Helper Methods
    
    /// Get current staff ID for API calls
    var currentStaffId: String? {
        return currentStaff?.id
    }
    
    /// Check if user is logged in and return staff ID, otherwise throw error
    func requireStaffId() throws -> String {
        try staffSessionManager.requireStaffId()
    }
}