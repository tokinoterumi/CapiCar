import SwiftUI

struct TaskGroupView: View {
    let title: String
    let tasks: [FulfillmentTask]
    
    // A private computed property to determine the group's color based on the first task.
    private var groupColor: Color {
        switch tasks.first?.status {
        case .pending: return .orange
        case .picking: return .blue
        case .packed, .inspecting: return .purple
        case .completed: return .green
        case .cancelled: return .gray
        case .paused: return .yellow
        case .none: return .gray
        }
    }
    
    var body: some View {
        // Use a Section for better list styling and accessibility.
        Section {
            if tasks.isEmpty {
                emptyStateView
            } else {
                ForEach(tasks) { task in

                    NavigationLink(value: task) {
                        TaskCardView(
                            task: task,
                            action: {}
                        )
                    }
                }
            }
        } header: {
            // Section Header
            HStack {
                Circle()
                    .fill(groupColor)
                    .frame(width: 8, height: 8)
                
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
        List {
            TaskGroupView(
                title: "Pending",
                tasks: [FulfillmentTask.previewPending]
            )
            
            TaskGroupView(
                title: "Paused",
                tasks: [FulfillmentTask.previewPaused]
            )
            
            TaskGroupView(
                title: "Empty Group",
                tasks: []
            )
        }
        .listStyle(.insetGrouped) // Use a style that supports headers well.
        .navigationTitle("Dashboard")
    }
}
#endif
