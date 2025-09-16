import SwiftUI

struct LoginView: View {
    @StateObject private var viewModel = StaffLoginViewModel()
    @ObservedObject private var sessionManager = StaffSessionManager.shared
    
    var body: some View {
        VStack(spacing: 24) {
            // MARK: - App Logo & Title
            VStack(spacing: 16) {
                // App icon
                Image("AppIcon")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 100, height: 100)
                    .clipShape(RoundedRectangle(cornerRadius: 20))
                    .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 4)
                
                VStack(spacing: 8) {
                    Text("CapiCar for YOS")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                    
                    Text("Warehouse Fulfillment System")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            // MARK: - Staff Selection Section
            VStack(spacing: 16) {
                Text("Select Your Profile")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Text("Choose your staff profile to start your shift and begin processing orders.")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            
            // MARK: - Staff List
            VStack(spacing: 16) {
                if viewModel.isLoading {
                    ProgressView("Loading staff...")
                        .frame(height: 200)
                } else if let errorMessage = viewModel.errorMessage {
                    VStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.title)
                            .foregroundColor(.red)
                        
                        Text("Unable to load staff")
                            .font(.headline)
                        
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                        
                        Button("Retry") {
                            Task {
                                await viewModel.loadStaff()
                            }
                        }
                        .buttonStyle(.bordered)
                    }
                    .frame(height: 200)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(viewModel.staffMembers) { staff in
                                StaffSelectionCard(
                                    staff: staff,
                                    isSelected: viewModel.selectedStaff?.id == staff.id,
                                    action: {
                                        viewModel.selectStaff(staff)
                                    }
                                )
                            }
                        }
                        .padding(.horizontal)
                    }
                    .frame(maxHeight: 300)
                }
            }
            
            // MARK: - Start Shift Button
            PrimaryButton(
                title: "Start Shift",
                isLoading: viewModel.isLoggingIn,
                action: {
                    viewModel.performLogin()
                }
            )
            .disabled(!viewModel.canLogin)
            .padding(.horizontal)
            
            Spacer()
        }
        .padding()
        .task {
            await viewModel.loadStaff()
        }
        .alert("Login Error", isPresented: .constant(viewModel.errorMessage != nil)) {
            Button("OK") {
                viewModel.errorMessage = nil
            }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }
}

// MARK: - Staff Selection Card

struct StaffSelectionCard: View {
    let staff: StaffMember
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                // Avatar
                Circle()
                    .fill(isSelected ? Color.blue : Color.gray.opacity(0.3))
                    .frame(width: 50, height: 50)
                    .overlay {
                        Text(String(staff.name.prefix(1).uppercased()))
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundColor(isSelected ? .white : .primary)
                    }
                
                // Staff Info
                VStack(alignment: .leading, spacing: 4) {
                    Text(staff.name)
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    Text("ID: \(staff.id)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                // Selection Indicator
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title2)
                        .foregroundColor(.blue)
                }
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(.systemBackground))
                    .stroke(
                        isSelected ? Color.blue : Color.gray.opacity(0.3),
                        lineWidth: isSelected ? 2 : 1
                    )
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

#if DEBUG
struct LoginView_Previews: PreviewProvider {
    static var previews: some View {
        LoginView()
    }
}
#endif
