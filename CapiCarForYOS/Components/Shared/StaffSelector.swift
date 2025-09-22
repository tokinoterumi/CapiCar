import SwiftUI

struct StaffSelector: View {
    @EnvironmentObject private var staffManager: StaffManager
    @EnvironmentObject private var dashboardViewModel: DashboardViewModel
    @State private var isExpanded = false

    var body: some View {
        VStack(spacing: 0) {
            // Current operator display (always visible)
            currentOperatorHeader

            // Expandable staff selection (when expanded)
            if isExpanded {
                staffSelectionList
            }
        }
        .frame(minHeight: 60) // Ensure minimum height
        .background(Color(.systemGray6))
        .animation(.easeInOut(duration: 0.3), value: isExpanded)
        .onAppear {
            // Load real staff data from Airtable
            Task {
                await staffManager.fetchAvailableStaff()
            }
        }
        .onChange(of: staffManager.availableStaff) { _, newStaffList in
            // Always ensure someone is selected when data loads
            if staffManager.currentOperator == nil && !newStaffList.isEmpty {
                // Auto-select first staff member
                staffManager.selectOperator(newStaffList.first!)
                print("🔧 Auto-selected \(newStaffList.first!.name) as current operator")
            }
        }
    }

    // MARK: - Subviews

    private var currentOperatorHeader: some View {
        Button(action: {
            withAnimation {
                isExpanded.toggle()
            }
        }) {
            HStack(spacing: 12) {
                // Operator avatar
                if let currentOperator = staffManager.currentOperator {
                    operatorAvatar(for: currentOperator)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(currentOperator.name)
                            .font(.headline)
                            .foregroundColor(.primary)

                        Text("Current Operator")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                } else {
                    Image(systemName: "person.badge.plus")
                        .font(.title2)
                        .foregroundColor(.orange)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Select Operator")
                            .font(.headline)
                            .foregroundColor(.primary)

                        Text("Tap to choose")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()

                // Refresh button
                Button(action: {
                    Task {
                        await dashboardViewModel.fetchDashboardData()
                    }
                }) {
                    if dashboardViewModel.isLoading {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .scaleEffect(0.8)
                    } else {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.blue)
                    }
                }
                .disabled(dashboardViewModel.isLoading)
                .buttonStyle(PlainButtonStyle())
                .frame(width: 32, height: 32)
                .background(Color.white)
                .clipShape(Circle())

                // Dropdown indicator
                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.primary)
                    .rotationEffect(.degrees(isExpanded ? 180 : 0))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
    }

    private var staffSelectionList: some View {
        VStack(spacing: 0) {
            Divider()
                .padding(.horizontal, 16)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    // Real staff from Airtable
                    ForEach(staffManager.availableStaff) { staffMember in
                        StaffButton(
                            staffMember: staffMember,
                            isSelected: staffManager.currentOperator?.id == staffMember.id,
                            onTap: {
                                staffManager.selectOperator(staffMember)
                                withAnimation {
                                    isExpanded = false
                                }
                            }
                        )
                    }

                    // Shared Terminal option
                    StaffButton(
                        staffMember: StaffMember(id: "shared", name: "Shared Terminal"),
                        isSelected: staffManager.currentOperator?.id == "shared",
                        onTap: {
                            staffManager.selectOperator(StaffMember(id: "shared", name: "Shared Terminal"))
                            withAnimation {
                                isExpanded = false
                            }
                        }
                    )
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
        }
    }

    private func operatorAvatar(for staffMember: StaffMember) -> some View {
        Circle()
            .fill(Color.blue.gradient)
            .frame(width: 40, height: 40)
            .overlay {
                Text(operatorInitials(staffMember.name))
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
            }
    }

    private func operatorInitials(_ name: String) -> String {
        let components = name.split(separator: " ")
        let initials = components.prefix(2).compactMap { $0.first }.map { String($0) }
        return initials.joined().uppercased()
    }
}

struct StaffButton: View {
    let staffMember: StaffMember
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 8) {
                // Dynamic icon based on staff name or generic person icon
                Image(systemName: iconName)
                    .font(.system(size: 16, weight: .medium))

                Text(staffMember.name)
                    .font(.system(size: 14, weight: .medium))
                    .lineLimit(1)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(isSelected ? Color.blue : Color(.systemGray5))
            )
            .foregroundColor(isSelected ? .white : .primary)
        }
        .buttonStyle(PlainButtonStyle())
    }

    private var iconName: String {
        // Use generic person icon for all real staff members
        // Special cases for system entries
        switch staffMember.id {
        case "shared":
            return "terminal"
        default:
            return "person.circle.fill"
        }
    }
}

#if DEBUG
struct StaffSelector_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 20) {
            // Preview with operator
            StaffSelector()
                .environmentObject({
                    let mockStaffManager = StaffManager()
                    mockStaffManager.currentOperator = StaffMember(id: "staff1", name: "Tanaka Hiroshi")
                    return mockStaffManager
                }())
                .environmentObject(DashboardViewModel())

            // Preview without operator
            StaffSelector()
                .environmentObject(StaffManager())
                .environmentObject(DashboardViewModel())
        }
        .padding()
    }
}
#endif