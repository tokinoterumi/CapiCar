import SwiftUI

struct CurrentOperatorWidget: View {
    @EnvironmentObject private var staffManager: StaffManager
    
    var body: some View {
        VStack(spacing: 12) {
            if let currentOperator = staffManager.currentOperator {
                operatorInfoSection(operator: currentOperator)
            } else {
                noOperatorSection
            }
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(12)
    }
    
    // MARK: - Subviews
    
    private func operatorInfoSection(operator staffMember: StaffMember) -> some View {
        HStack(spacing: 16) {
            // Operator avatar/icon
            Circle()
                .fill(Color.blue.gradient)
                .frame(width: 50, height: 50)
                .overlay {
                    Text(operatorInitials(staffMember.name))
                        .font(.headline)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                }
            
            VStack(alignment: .leading, spacing: 4) {
                Text("Current Operator")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                Text(staffMember.name)
                    .font(.title3)
                    .fontWeight(.semibold)
                
                Text("Checked in")
                    .font(.caption)
                    .foregroundColor(.green)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Color.green.opacity(0.1))
                    .cornerRadius(4)
            }
            
            Spacer()
            
            // Status indicator
            Circle()
                .fill(Color.green)
                .frame(width: 12, height: 12)
        }
    }
    
    private var noOperatorSection: some View {
        HStack(spacing: 16) {
            Circle()
                .fill(Color.gray.gradient)
                .frame(width: 50, height: 50)
                .overlay {
                    Image(systemName: "person.slash")
                        .font(.title3)
                        .foregroundColor(.white)
                }
            
            VStack(alignment: .leading, spacing: 4) {
                Text("No Operator")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                Text("Not checked in")
                    .font(.title3)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
                
                Text("Unavailable")
                    .font(.caption)
                    .foregroundColor(.orange)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Color.orange.opacity(0.1))
                    .cornerRadius(4)
            }
            
            Spacer()
            
            // Status indicator
            Circle()
                .fill(Color.orange)
                .frame(width: 12, height: 12)
        }
    }
    
    // MARK: - Helper Methods
    
    private func operatorInitials(_ name: String) -> String {
        let components = name.components(separatedBy: " ")
        let initials = components.compactMap { $0.first }.map { String($0) }
        return initials.prefix(2).joined().uppercased()
    }
}

// MARK: - Preview
#if DEBUG
struct CurrentOperatorWidget_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 20) {
            // Preview with operator
            CurrentOperatorWidget()
                .environmentObject({
                    let mockStaffManager = StaffManager()
                    mockStaffManager.currentOperator = StaffMember(id: "staff1", name: "Tanaka Hiroshi")
                    return mockStaffManager
                }())
            
            // Preview without operator
            CurrentOperatorWidget()
                .environmentObject(StaffManager())
        }
        .padding()
        .previewLayout(.sizeThatFits)
    }
}
#endif