import SwiftUI

struct StaffSelector: View {
    @EnvironmentObject private var staffManager: StaffManager

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                // Real staff from Airtable
                ForEach(staffManager.availableStaff) { staffMember in
                    StaffButton(
                        staffMember: staffMember,
                        isSelected: staffManager.currentOperator?.id == staffMember.id,
                        onTap: {
                            staffManager.selectOperator(staffMember)
                        }
                    )
                }

                // Shared Terminal option
                StaffButton(
                    staffMember: StaffMember(id: "shared", name: "Shared Terminal"),
                    isSelected: staffManager.currentOperator?.id == "shared",
                    onTap: {
                        staffManager.selectOperator(StaffMember(id: "shared", name: "Shared Terminal"))
                    }
                )
            }
            .padding(.horizontal)
        }
        .frame(height: 60)
        .background(Color(.systemGray6))
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
        StaffSelector()
            .environmentObject(StaffManager())
    }
}
#endif