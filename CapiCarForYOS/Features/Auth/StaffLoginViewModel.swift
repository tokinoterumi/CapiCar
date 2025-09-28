import Foundation
import Combine

@MainActor
class StaffLoginViewModel: ObservableObject {
    @Published var username = ""
    @Published var password = ""
    @Published var isLoggingIn = false
    @Published var errorMessage: String?
    @Published var showErrorAlert = false
    
    private var cancellables = Set<AnyCancellable>()
    
    // --- Hardcoded User Credentials ---
    private let correctUsername = "Capybara"
    private let correctPassword = "CapiCapi"
    
    var canLogin: Bool {
        !username.trimmingCharacters(in: .whitespaces).isEmpty &&
        !password.trimmingCharacters(in: .whitespaces).isEmpty &&
        !isLoggingIn
    }
    
    init() {
        // This publisher automatically sets showErrorAlert when errorMessage changes.
        $errorMessage
            .map { $0 != nil }
            .assign(to: \.showErrorAlert, on: self)
            .store(in: &cancellables)
    }
    
    func performLogin() {
        guard canLogin else { return }
        
        isLoggingIn = true
        errorMessage = nil
        
        // Simulate a 1-second network delay for realism
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            // Use UserSessionManager for actual user authentication
            let loginSuccess = UserSessionManager.shared.login(username: self.username, password: self.password)

            if loginSuccess {
                // --- SUCCESS ---
                // User authentication successful
                // They will now proceed to StaffCheckInView to select a staff member to operate as
                print("✅ User authentication successful: \(self.username)")
            } else {
                // --- FAILURE ---
                self.errorMessage = "Invalid username or password. Please try again."
            }
            self.isLoggingIn = false
        }
    }
}
