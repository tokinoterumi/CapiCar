import Foundation
import Combine

@MainActor
class AuthenticationManager: ObservableObject {

    // MARK: - Published Properties

    @Published var isAuthenticated: Bool = false
    @Published var currentUser: User?
    @Published var currentStaff: StaffMember?

    // MARK: - Dependencies

    private let userSessionManager = UserSessionManager.shared
    private let staffSessionManager = StaffSessionManager.shared
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Initialization

    init() {
        // Observe user session changes for authentication
        userSessionManager.$isLoggedIn
            .assign(to: \.isAuthenticated, on: self)
            .store(in: &cancellables)

        userSessionManager.$currentUser
            .assign(to: \.currentUser, on: self)
            .store(in: &cancellables)

        // Observe staff session changes for current operator
        staffSessionManager.$currentStaff
            .assign(to: \.currentStaff, on: self)
            .store(in: &cancellables)
    }
    
    // MARK: - Authentication Methods

    func signOut() {
        userSessionManager.logout()
        staffSessionManager.logout()
    }

    // MARK: - Helper Methods

    /// Get current user ID for API calls
    var currentUserId: String? {
        return currentUser?.id
    }

    /// Get current staff ID for API calls
    var currentStaffId: String? {
        return currentStaff?.id
    }

    /// Check if user is logged in and return user ID, otherwise throw error
    func requireUserId() throws -> String {
        try userSessionManager.requireUserId()
    }

    /// Check if staff is checked in and return staff ID, otherwise throw error
    func requireStaffId() throws -> String {
        try staffSessionManager.requireStaffId()
    }
}