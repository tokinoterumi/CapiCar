import SwiftUI

/// A view that handles the staff check-in process, refactored to align with the app's visual identity.
struct StaffCheckInView: View {
    
    // MARK: - Properties
    
    @ObservedObject var viewModel: StaffViewModel
    
    // MARK: - Body
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header with improved typography and consistent styling.
            Label("担当者", systemImage: "person.crop.circle")
                .font(.headline)
                .foregroundColor(.secondary)
            
            // Conditional view: show the check-in list or the current operator status.
            if let currentOperator = viewModel.currentOperator {
                checkedInView(for: currentOperator)
            } else {
                checkInListView
            }
        }
        .padding()
        // Use a background color that provides subtle contrast and works in both light/dark modes.
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(12)
        .onAppear {
            // Load staff if the list is empty when the view appears.
            if viewModel.allStaff.isEmpty {
                viewModel.loadAllStaff()
            }
        }
    }
    
    // MARK: - Private Subviews
    
    /// The view shown when a user is already checked in. Refactored for clarity and style.
    private func checkedInView(for staffMember: StaffMember) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(staffMember.name)
                    .font(.title2)
                    .fontWeight(.bold)
            }
            
            Spacer()
            
            // Use our custom Secondary Button style for the "Switch" action.
            PrimaryButton(title: "切替", isSecondary: true) {
                Task {
                    await viewModel.checkOut()
                }
            }
        }
    }
    
    /// The view shown when no user is checked in, refactored to use a list-row style for selection.
    private var checkInListView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Please select your name to begin.")
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            if viewModel.isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, alignment: .center)
            } else if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
                    .foregroundColor(.red)
                    .font(.caption)
            } else {
                // A custom list built with VStack and Dividers to mimic a native List,
                // providing a cleaner UI for selection than large buttons.
                VStack(spacing: 0) {
                    ForEach(viewModel.allStaff) { staff in
                        Button(action: {
                            Task {
                                await viewModel.checkIn(staffMember: staff)
                            }
                        }) {
                            HStack {
                                Text(staff.name)
                                    .foregroundColor(.primary)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .foregroundColor(.secondary.opacity(0.5))
                            }
                            .padding()
                            .contentShape(Rectangle()) // Ensures the whole area is tappable
                        }
                        
                        // Add a divider between items, but not after the last one.
                        if staff.id != viewModel.allStaff.last?.id {
                            Divider().padding(.leading)
                        }
                    }
                }
                .background(Color(.systemBackground)) // Use a solid background for the list container
                .cornerRadius(8)
            }
        }
    }
}


// MARK: - Preview
#if DEBUG
struct StaffCheckInView_Previews: PreviewProvider {
    
    // Preview for the "checked out" state
    static var checkedOutViewModel: StaffViewModel = {
        let vm = StaffViewModel()
        vm.allStaff = [
            StaffMember(id: "s001", name: "佐藤 恵美"),
            StaffMember(id: "s002", name: "鈴木 健太"),
            StaffMember(id: "s003", name: "高橋 陽子")
        ]
        return vm
    }()
    
    // Preview for the "checked in" state
    static var checkedInViewModel: StaffViewModel = {
        let vm = StaffViewModel()
        vm.currentOperator = StaffMember(id: "s001", name: "佐藤 恵美")
        return vm
    }()
    
    static var previews: some View {
        ScrollView {
            VStack(spacing: 30) {
                
                VStack {
                    Text("ログイン").font(.caption).foregroundColor(.secondary)
                    StaffCheckInView(viewModel: checkedOutViewModel)
                }
                
                VStack {
                    Text("作業中").font(.caption).foregroundColor(.secondary)
                    StaffCheckInView(viewModel: checkedInViewModel)
                }
                
            }
            .padding()
            .background(Color.appBackgroundPaper)
        }
    }
}
#endif

