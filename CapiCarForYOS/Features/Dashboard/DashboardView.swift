import SwiftUI

struct DashboardView: View {
    
    // MARK: - Properties
    
    // The single source of truth for all dashboard data and logic.
    @StateObject private var viewModel = DashboardViewModel()
    
    // A wrapper struct to make our task sections identifiable and hashable, solving ForEach issues.
    private struct IdentifiableTaskSection: Identifiable, Hashable {
        var id: TaskStatus { status }
        let status: TaskStatus
        let tasks: [FulfillmentTask]
    }
    
    // A computed property that transforms the ViewModel's data into an identifiable collection.
    private var identifiableTaskSections: [IdentifiableTaskSection] {
        viewModel.taskSections.map { section in
            IdentifiableTaskSection(status: section.status, tasks: section.tasks)
        }
    }
    
    // MARK: - Body
    
    var body: some View {
        NavigationStack {
            ZStack {
                // Use a subtle background color that adapts to light/dark mode.
                Color(.systemGroupedBackground).ignoresSafeArea()
                
                // Switch between loading, error, and content views based on the view model's state.
                if viewModel.isLoading {
                    loadingView
                } else if let errorMessage = viewModel.errorMessage {
                    errorView(message: errorMessage)
                } else {
                    mainContentView
                }
            }
            .navigationTitle("CapiCar Dashboard")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    refreshButton
                }
            }
            // This handles the navigation when a TaskCardView (wrapped in a NavigationLink) is tapped.
            .navigationDestination(for: FulfillmentTask.self) { task in
                // In a real app, you would pass the necessary data to the detail view.
                // For now, it's a placeholder.
                Text("Task Detail for \(task.orderName)")
            }
            // Fetch initial data when the view first appears.
            .onAppear {
                // To call an async function from a non-async context, wrap it in a Task.
                Task {
                    // This 'await' assumes that fetchDashboardData() in the ViewModel is marked as 'async'.
                    await viewModel.fetchDashboardData()
                }
            }
        }
    }
    
    // MARK: - Private Subviews
    
    private var mainContentView: some View {
        // A List is the most appropriate container for our grouped tasks.
        List {
            // We now iterate over the identifiableTaskSections, which is fully compatible with ForEach.
            ForEach(identifiableTaskSections) { section in
                // Only show the section if it has tasks.
                if !section.tasks.isEmpty {
                    TaskGroupView(
                        title: section.status.rawValue, // e.g., "Pending"
                        tasks: section.tasks
                    )
                }
            }
        }
        .listStyle(.insetGrouped) // A modern list style that works well with sections.
        .refreshable {
            // Allows the user to pull-to-refresh.
            // This requires viewModel.fetchDashboardData() to be an 'async' function.
            await viewModel.fetchDashboardData()
        }
    }
    
    private var refreshButton: some View {
        Button(action: {
            // To call an async function from a button action, wrap it in a Task.
            Task {
                await viewModel.fetchDashboardData()
            }
        }) {
            if viewModel.isLoading {
                ProgressView()
                    .progressViewStyle(.circular)
                    .scaleEffect(0.8)
            } else {
                Image(systemName: "arrow.clockwise")
            }
        }
        .disabled(viewModel.isLoading)
    }
    
    private var loadingView: some View {
        ProgressView("Loading Dashboard...")
            .progressViewStyle(.circular)
            .scaleEffect(1.5)
    }
    
    private func errorView(message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.largeTitle)
                .foregroundColor(.red)
            Text("Error")
                .font(.title2).bold()
            Text(message)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            
            PrimaryButton(title: "Retry", action: {
                Task {
                    await viewModel.fetchDashboardData()
                }
            })
        }
        .padding()
    }
}

// MARK: - Preview
#if DEBUG
struct DashboardView_Previews: PreviewProvider {
    static var previews: some View {
        DashboardView()
    }
}
#endif

