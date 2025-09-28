import SwiftUI

struct TaskGroupView: View {
    let title: String
    let tasks: [FulfillmentTask]
    let onTaskSelected: (FulfillmentTask) -> Void

    // Environment objects
    @EnvironmentObject private var staffManager: StaffManager
    
    // Get unique status colors in the group
    private var groupColors: [Color] {
        // For paused groups, always use gray regardless of underlying status
        if tasks.first?.isPaused == true {
            return [.gray]
        }

        // Get unique statuses in this group and their colors
        // Note: removed intermediate states no longer appear in UI
        let uniqueStatuses = Set(tasks.map { $0.status })
        let colors = uniqueStatuses.compactMap { status -> Color? in
            switch status {
            case .pending: return .orange
            case .picking: return .blue
            case .packed: return Color(.systemIndigo)
            case .inspecting: return .teal
            case .correctionNeeded: return .red
            case .correcting: return .pink
            case .completed: return .green
            case .cancelled: return .gray
            }
        }

        return Array(colors)
    }

    
    var body: some View {
        // Use a Section for better list styling and accessibility.
        Section {
            if tasks.isEmpty {
                emptyStateView
            } else {
                ForEach(tasks) { task in
                    TaskCardView(
                        task: task,
                        action: {
                            onTaskSelected(task)
                        }
                    )
                }
            }
        } header: {
            // Section Header
            HStack {
                // Multiple status indicators
                HStack(spacing: 2) {
                    ForEach(Array(groupColors.enumerated()), id: \.offset) { index, color in
                        Circle()
                            .fill(color)
                            .frame(width: 8, height: 8)
                    }
                }

                Text(title)
                    .font(.headline)
                    .fontWeight(.semibold)

                Text("(\(tasks.count))")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                Spacer()
            }
        }
        .padding(.vertical, 8)
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 8) {
            Image(systemName: "checkmark.circle")
                .font(.title2)
                .foregroundColor(.secondary)
            
            Text("No \(title.lowercased()) tasks")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        // Removed background and corner radius to let the List style handle it.
    }
}

// MARK: - Preview
// The preview also needs to be updated to reflect the new simplified initializer.
#if DEBUG
struct TaskGroupView_Previews: PreviewProvider {
    static var previews: some View {
        let mockStaffManager = StaffManager()
        mockStaffManager.currentOperator = StaffMember(id: "staff1", name: "Test User")
        
        return NavigationStack {
            List {
                TaskGroupView(
                    title: "Pending",
                    tasks: [FulfillmentTask.previewPending],
                    onTaskSelected: { _ in }
                )

                TaskGroupView(
                    title: "Paused",
                    tasks: [FulfillmentTask.previewPaused],
                    onTaskSelected: { _ in }
                )

                TaskGroupView(
                    title: "Completed",
                    tasks: [FulfillmentTask.previewCompleted],
                    onTaskSelected: { _ in }
                )
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Dashboard")
        }
        .environmentObject(mockStaffManager)
    }
}
#endif
