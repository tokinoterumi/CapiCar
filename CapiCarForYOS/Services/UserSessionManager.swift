import Foundation
import Combine

@MainActor
class UserSessionManager: ObservableObject {
    static let shared = UserSessionManager()

    // MARK: - Published Properties

    @Published var currentUser: User?
    @Published var isLoggedIn: Bool = false

    // MARK: - Private Properties

    private let userDefaults = UserDefaults.standard
    private let currentUserKey = "currentUser"

    // MARK: - Initialization

    private init() {
        loadSavedUser()
    }

    // MARK: - Public Methods

    /// Log in with username and password
    func login(username: String, password: String) -> Bool {
        // Single hardcoded credential - all staff have same authorization
        guard username == "Capybara" && password == "CapiCapi" else {
            return false
        }

        let user = User(
            id: "user-capybara",
            username: username,
            role: .staff
        )

        currentUser = user
        isLoggedIn = true
        saveUser()

        print("✅ User logged in: \(user.username) (Role: \(user.role))")
        return true
    }

    /// Log out current user
    func logout() {
        currentUser = nil
        isLoggedIn = false
        clearSavedUser()

        print("👋 User logged out")
    }

    /// Get current user ID for API calls
    var currentUserId: String? {
        return currentUser?.id
    }

    /// Check if user is logged in and return user ID, otherwise throw error
    func requireUserId() throws -> String {
        guard let userId = currentUserId else {
            throw UserSessionError.notLoggedIn
        }
        return userId
    }

    // MARK: - Private Methods

    // No longer needed - single role for all users

    private func saveUser() {
        guard let user = currentUser else { return }

        if let encoded = try? JSONEncoder().encode(user) {
            userDefaults.set(encoded, forKey: currentUserKey)
        }
    }

    private func loadSavedUser() {
        guard let data = userDefaults.data(forKey: currentUserKey),
              let user = try? JSONDecoder().decode(User.self, from: data) else {
            return
        }

        currentUser = user
        isLoggedIn = true

        print("🔄 Restored user session: \(user.username)")
    }

    private func clearSavedUser() {
        userDefaults.removeObject(forKey: currentUserKey)
    }
}

// MARK: - User Model

struct User: Codable {
    let id: String
    let username: String
    let role: UserRole
}

enum UserRole: String, Codable {
    case staff = "staff"
}

// MARK: - Session Errors

enum UserSessionError: LocalizedError {
    case notLoggedIn

    var errorDescription: String? {
        switch self {
        case .notLoggedIn:
            return "Please log in to perform this action"
        }
    }
}