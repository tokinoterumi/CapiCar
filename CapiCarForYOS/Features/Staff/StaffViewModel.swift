import Foundation

@MainActor
class StaffViewModel: ObservableObject {

    // MARK: - Published Properties

    @Published var allStaff: [StaffMember] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    // MARK: - Private Properties

    private let apiService: APIService

    // MARK: - Initializer

    init(apiService: APIService = .shared) {
        self.apiService = apiService
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
    
    // MARK: - CRUD Operations

    func addStaff(name: String) async -> Bool {
        isLoading = true
        errorMessage = nil

        do {
            let newStaff = try await apiService.createStaff(name: name)

            // Add to local list
            allStaff.append(newStaff)
            print("✅ Created staff member: \(newStaff.name)")
            isLoading = false
            return true

        } catch {
            errorMessage = "Failed to create staff member. Please try again."
            print("Error creating staff: \(error)")
            isLoading = false
            return false
        }
    }

    func updateStaff(id: String, name: String) async -> Bool {
        isLoading = true
        errorMessage = nil

        do {
            let updatedStaff = try await apiService.updateStaff(staffId: id, name: name)

            // Update local list
            if let index = allStaff.firstIndex(where: { $0.id == id }) {
                allStaff[index] = updatedStaff
            }
            print("✅ Updated staff member: \(updatedStaff.name)")
            isLoading = false
            return true

        } catch {
            errorMessage = "Failed to update staff member. Please try again."
            print("Error updating staff: \(error)")
            isLoading = false
            return false
        }
    }

    func deleteStaff(id: String) async -> Bool {
        isLoading = true
        errorMessage = nil

        do {
            try await apiService.deleteStaff(staffId: id)

            // Remove from local list
            allStaff.removeAll { $0.id == id }
            print("✅ Deleted staff member with ID: \(id)")
            isLoading = false
            return true

        } catch {
            errorMessage = "Failed to delete staff member. Please try again."
            print("Error deleting staff: \(error)")
            isLoading = false
            return false
        }
    }
}
