import SwiftUI

// MARK: - Task Card View

struct TaskCardView: View {
    let task: FulfillmentTask
    
    // The action to perform when the card is tapped.
    let action: () -> Void
    
    // Private computed property to determine the status color.
    private var statusColor: Color {
        switch task.status {
        case .pending: return .orange
        case .picking: return .blue
        case .packed, .inspecting: return .purple
        case .completed: return .green
        case .cancelled: return .gray
        case .paused: return .yellow
        }
    }
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                // 1. Status Indicator
                Capsule()
                    .fill(statusColor)
                    .frame(width: 5)
                
                // 2. Main Content
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(task.orderName)
                            .font(.headline)
                            .fontWeight(.bold)
                            .foregroundColor(.primary)
                        Spacer()
                        Text(task.createdAt, style: .time)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    
                    Text(task.shippingName)
                        .font(.body)
                        .foregroundColor(.secondary)
                    
                    if let operatorInfo = task.currentOperator {
                        Spacer().frame(height: 8) // Visual separation
                        HStack(spacing: 4) {
                            Image(systemName: "person.fill")
                            Text(operatorInfo.name)
                        }
                        .font(.caption)
                        .foregroundColor(statusColor)
                        .fontWeight(.medium)
                    }
                }
                
                // 3. Navigation Indicator
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundColor(.secondary.opacity(0.5))
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 16)
            .background(Color(.systemBackground))
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
    }
}


// MARK: - Preview Section

#if DEBUG

// --- Mock Data Extension for Previewing ---
// This is a common and robust pattern in SwiftUI. We extend our REAL models
// to provide static, sample instances for use only in previews.
// This avoids redeclaring the entire struct and prevents ambiguity errors.

extension FulfillmentTask {
    static let previewPending = FulfillmentTask(
        id: "1", orderName: "#YM1025", status: .pending,
        shippingName: "John Appleseed", createdAt: Date().addingTimeInterval(-3600),
        checklistJson: "[]", currentOperator: nil
    )
    
    static let previewPaused = FulfillmentTask(
        id: "2", orderName: "#YM1026", status: .paused,
        shippingName: "Yui Takahashi", createdAt: Date().addingTimeInterval(-7200),
        checklistJson: "[]", currentOperator: .previewTanaka
    )
    
    static let previewCompleted = FulfillmentTask(
        id: "3", orderName: "#YM1027", status: .completed,
        shippingName: "Emily Carter", createdAt: Date().addingTimeInterval(-10800),
        checklistJson: "[]", currentOperator: .previewSuzuki
    )
}

extension StaffMember {
    static let previewTanaka = StaffMember(id: "s001", name: "Tanaka-san")
    static let previewSuzuki = StaffMember(id: "s002", name: "Suzuki-san")
}


// --- Preview Provider ---

struct TaskCardView_Previews: PreviewProvider {
    static var previews: some View {
        List {
            TaskCardView(
                task: .previewPending,
                action: { print("Tapped Pending Task") }
            )
            
            TaskCardView(
                task: .previewPaused,
                action: { print("Tapped Paused Task") }
            )
            
            TaskCardView(
                task: .previewCompleted,
                action: { print("Tapped Completed Task") }
            )
        }
        .listStyle(PlainListStyle())
        .navigationTitle("Task List")
    }
}
#endif

