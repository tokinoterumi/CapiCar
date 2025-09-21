import SwiftUI

/// A view that handles the staff check-in process, integrated with the new StaffManager.
struct StaffCheckInView: View {
    
    // MARK: - Properties
    
    @EnvironmentObject private var authManager: AuthenticationManager
    @EnvironmentObject private var staffManager: StaffManager
    
    // MARK: - Body
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                
                // MARK: - Header Section
                VStack(spacing: 16) {
                    Image(systemName: "person.crop.circle.fill")
                        .font(.system(size: 60))
                        .foregroundColor(.blue)
                    
                    VStack(spacing: 8) {
                        Text("Select Current Operator")
                            .font(.title2)
                            .fontWeight(.bold)
                        
                        if let staff = authManager.currentStaff {
                            Text("Signed in as \(staff.name)")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                
                Spacer()
                
                // MARK: - Staff Selection
                VStack(spacing: 16) {
                    if staffManager.isLoading {
                        ProgressView("Loading staff...")
                            .progressViewStyle(.circular)
                    } else if staffManager.availableStaff.isEmpty {
                        Text("No staff members available")
                            .foregroundColor(.secondary)
                        
                        PrimaryButton(title: "Retry") {
                            Task {
                                await staffManager.fetchAvailableStaff()
                            }
                        }
                    } else {
                        staffSelectionList
                    }
                }
                
                Spacer()
                
                // MARK: - Sign Out Button
                PrimaryButton(
                    title: "Sign Out",
                    isSecondary: true,
                    isDestructive: true
                ) {
                    authManager.signOut()
                }
                
            }
            .padding()
            .navigationTitle("Check In")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                if staffManager.availableStaff.isEmpty {
                    Task {
                        await staffManager.fetchAvailableStaff()
                    }
                }
            }
            .alert("Check-In Error", isPresented: .constant(staffManager.errorMessage != nil)) {
                Button("OK") {
                    staffManager.errorMessage = nil
                }
            } message: {
                Text(staffManager.errorMessage ?? "")
            }
        }
    }
    
    // MARK: - Private Subviews
    
    private var staffSelectionList: some View {
        VStack(spacing: 0) {
            ForEach(staffManager.availableStaff) { staff in
                Button(action: {
                    Task {
                        let success = await staffManager.checkInOperator(staff)
                        if success {
                            // Navigation will happen automatically via RootView
                        }
                    }
                }) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(staff.name)
                                .font(.body)
                                .fontWeight(.medium)
                                .foregroundColor(.primary)
                            
                            Text("Tap to check in")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                        
                        Image(systemName: "chevron.right")
                            .foregroundColor(.secondary.opacity(0.6))
                    }
                    .padding()
                    .contentShape(Rectangle())
                }
                .disabled(staffManager.isLoading)
                
                if staff.id != staffManager.availableStaff.last?.id {
                    Divider()
                        .padding(.leading)
                }
            }
        }
        .background(Color(.systemBackground))
        .cornerRadius(12)
    }
}


#if DEBUG
struct StaffCheckInView_Previews: PreviewProvider {
    static var previews: some View {
        let mockAuthManager = AuthenticationManager()
        let mockStaff = StaffMember(id: "s001", name: "Preview Staff")
        mockAuthManager.currentStaff = mockStaff
        
        let mockStaffManager = StaffManager()
        
        return StaffCheckInView()
            .environmentObject(mockAuthManager)
            .environmentObject(mockStaffManager)
    }
}
#endif
