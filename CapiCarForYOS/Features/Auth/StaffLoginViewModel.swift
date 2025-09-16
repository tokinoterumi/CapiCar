import Foundation
import Combine

@MainActor
class StaffLoginViewModel: ObservableObject {
    
    // MARK: - Published Properties
    
    @Published var staffMembers: [StaffMember] = []
    @Published var selectedStaff: StaffMember?
    @Published var isLoading: Bool = false
    @Published var isLoggingIn: Bool = false
    @Published var errorMessage: String?
    
    // MARK: - Dependencies
    
    private let apiService: APIService
    private let sessionManager = StaffSessionManager.shared
    
    // MARK: - Computed Properties
    
    var canLogin: Bool {
        selectedStaff != nil && !isLoggingIn
    }
    
    // MARK: - Initialization
    
    init(apiService: APIService = APIService.shared) {
        self.apiService = apiService
    }
    
    // MARK: - Public Methods
    
    func loadStaff() async {
        isLoading = true
        errorMessage = nil
        
        do {
            staffMembers = try await apiService.fetchAllStaff()
            
            // Auto-select if only one staff member
            if staffMembers.count == 1 {
                selectedStaff = staffMembers.first
            }
            
        } catch {
            errorMessage = "Failed to load staff: \(error.localizedDescription)"
            print("Error loading staff: \(error)")
        }
        
        isLoading = false
    }
    
    func selectStaff(_ staff: StaffMember) {
        selectedStaff = staff
        errorMessage = nil
    }
    
    func performLogin() {
        guard let staff = selectedStaff else { return }
        
        isLoggingIn = true
        errorMessage = nil
        
        // Simulate slight delay for better UX
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.sessionManager.login(staff: staff)
            self.isLoggingIn = false
        }
    }
}