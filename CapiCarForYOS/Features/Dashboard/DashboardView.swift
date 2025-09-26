import SwiftUI

struct DashboardView: View {

    // MARK: - Properties

    // The single source of truth for all dashboard data and logic.
    @EnvironmentObject private var viewModel: DashboardViewModel
    let onTaskSelected: (FulfillmentTask) -> Void
    
    // A wrapper struct to make our task sections identifiable and hashable, solving ForEach issues.
    private struct IdentifiableTaskSection: Identifiable, Hashable {
        var id: DisplayStatus { displayStatus }
        let displayStatus: DisplayStatus
        let tasks: [FulfillmentTask]
    }

    // A computed property that transforms the ViewModel's data into an identifiable collection.
    private var identifiableTaskSections: [IdentifiableTaskSection] {
        viewModel.taskSections.map { section in
            IdentifiableTaskSection(displayStatus: section.displayStatus, tasks: section.tasks)
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
            // DEBUG: Temporary button to clear local data for testing
            .overlay(alignment: .topTrailing) {
                Button("🧹 CLEAR") {
                    Task {
                        await viewModel.clearAllLocalData()
                    }
                }
                .foregroundColor(.red)
                .padding()
                .background(Color.black.opacity(0.1))
                .cornerRadius(8)
                .padding()
            }
            // Navigation is now handled by TaskGroupView sheets
            // Removed onAppear auto-loading - data loads via pull-to-refresh or explicit user action
            // Smart refresh when returning to dashboard after potential data changes
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
                // Trigger proactive sync when returning to dashboard from background
                Task {
                    print("📱 DASHBOARD: App entered foreground, triggering proactive sync")
                    await SyncManager.shared.triggerSync()
                }
                // Also mark data as potentially changed for immediate UI refresh if needed
                viewModel.markDataChangesPending()
            }
        }
    }

    // MARK: - Private Subviews

    
    private var mainContentView: some View {
        // A List is the most appropriate container for our grouped tasks.
        List {
            // Sync Status Widget
            Section {
                SyncStatusWidget()
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            }
            
            // We now iterate over the identifiableTaskSections, which is fully compatible with ForEach.
            ForEach(identifiableTaskSections) { section in
                // Only show the section if it has tasks.
                if !section.tasks.isEmpty {
                    TaskGroupView(
                        title: section.displayStatus.rawValue, // e.g., "Pending", "Paused"
                        tasks: section.tasks,
                        onTaskSelected: onTaskSelected
                    )
                }
            }
        }
        .listStyle(.insetGrouped) // A modern list style that works well with sections.
        .refreshable {
            // Allows the user to pull-to-refresh.
            // Use force refresh for explicit user action
            await viewModel.forceFetchDashboardData()
        }
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
                    await viewModel.forceFetchDashboardData()
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
        let mockSyncManager = SyncManager.shared

        return DashboardView(onTaskSelected: { _ in })
            .environmentObject(mockSyncManager)
            .environmentObject(DashboardViewModel())
    }
}
#endif
