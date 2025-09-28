import SwiftUI

// MARK: - Report Issue View

struct ReportIssueView: View {
    @StateObject private var viewModel: ReportIssueViewModel
    @Environment(\.dismiss) private var dismiss

    // Callback to dismiss all task views and return to dashboard
    let onIssueReported: (() -> Void)?

    init(task: FulfillmentTask, currentOperator: StaffMember?, onIssueReported: (() -> Void)? = nil) {
        _viewModel = StateObject(wrappedValue: ReportIssueViewModel(task: task, currentOperator: currentOperator))
        self.onIssueReported = onIssueReported
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    headerSection

                    loggingInfoSection

                    issueTypeSection

                    descriptionSection

                    actionButtonsSection
                }
                .padding()
            }
        }
        .navigationTitle("Report Issue")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(content: {
            ToolbarItem(placement: .navigationBarLeading) {
                Button("Cancel") {
                    print("🔍 ReportIssueView: Cancel button tapped")
                    dismiss()
                }
            }
        })
        .onAppear {
            print("🔍 ReportIssueView: onAppear called for task \(viewModel.task.orderName)")
        }
        .onDisappear {
            print("🔍 ReportIssueView: onDisappear called")
        }
        .alert("Error", isPresented: .constant(viewModel.errorMessage != nil)) {
            Button("OK") { viewModel.errorMessage = nil }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
        .alert("Issue Reported", isPresented: $viewModel.showingSuccessAlert) {
            Button("OK") {
                dismiss()
                // Call the callback to dismiss all task views and return to dashboard
                onIssueReported?()
            }
        } message: {
            Text("The issue has been reported successfully and logged for review.")
        }
    }

    // MARK: - Subviews

    private var headerSection: some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.circle.fill")
                .font(.system(size: 50))
                .foregroundColor(.red)

            Text("Report Issue")
                .font(.title2)
                .fontWeight(.bold)

            Text("Task: \(viewModel.task.orderName)")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical)
        .cornerRadius(12)
    }

    private var loggingInfoSection: some View {
        VStack(alignment: .leading, spacing: 16) {

            VStack(alignment: .leading, spacing: 12) {
                // 担当者 / Operator
                HStack {
                    Image(systemName: "person.fill")
                        .frame(width: 20)
                    Text("Operator")
                        .fontWeight(.medium)
                    Spacer()
                    Text(viewModel.currentOperator?.name ?? "Unknown")
                        .foregroundColor(.secondary)
                }

                Divider()

                // 時刻 / Timestamp
                HStack {
                    Image(systemName: "clock.fill")
                        .frame(width: 20)
                    Text("Time")
                        .fontWeight(.medium)
                    Spacer()
                    Text(viewModel.currentTimestamp)
                        .foregroundColor(.secondary)
                        .font(.caption)
                }

                Divider()

                // Task Status
                HStack {
                    Image(systemName: "flag.fill")
                        .frame(width: 20)
                    Text("Current Status")
                        .fontWeight(.medium)
                    Spacer()
                    Text(viewModel.task.status.rawValue)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.purple.opacity(0.1))
                        .cornerRadius(6)
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(12)
    }

    private var issueTypeSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "list.bullet")
                Text("Issue Type")
                    .font(.headline)
                    .fontWeight(.semibold)
            }

            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 12) {
                ForEach(IssueType.allCases, id: \.self) { issueType in
                    IssueTypeButton(
                        issueType: issueType,
                        isSelected: viewModel.selectedIssueType == issueType,
                        onTap: {
                            viewModel.selectedIssueType = issueType
                        }
                    )
                }
            }
        }
        .padding()
        .cornerRadius(12)
    }

    private var descriptionSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "text.bubble")
                    .foregroundColor(.blue)
                Text("Description")
                    .font(.headline)
                    .fontWeight(.semibold)
            }

            TextField("Describe the issue in detail...", text: $viewModel.issueDescription, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(4...8)
        }
        .padding()
        .cornerRadius(12)
    }

    private var actionButtonsSection: some View {
        VStack(spacing: 16) {
            PrimaryButton(
                title: "Submit",
                isLoading: viewModel.isLoading,
                isDisabled: !viewModel.canSubmitReport,
                action: {
                    print("🔍 ReportIssueView: Submit button tapped")
                    Task {
                        await viewModel.submitIssueReport()
                    }
                }
            )
        }
    }
}

// MARK: - Issue Type Enum

enum IssueType: String, CaseIterable {
    case damagedItem = "damaged_item"
    case missingItem = "missing_item"
    case wrongItem = "wrong_item"
    case qualityIssue = "quality_issue"
    case packagingIssue = "packaging_issue"
    case other = "other"

    var displayName: String {
        switch self {
        case .damagedItem: return "Damaged Item"
        case .missingItem: return "Missing Item"
        case .wrongItem: return "Wrong Item"
        case .qualityIssue: return "Quality Issue"
        case .packagingIssue: return "Packaging Issue"
        case .other: return "Other"
        }
    }

    var iconName: String {
        switch self {
        case .damagedItem: return "exclamationmark.triangle.fill"
        case .missingItem: return "questionmark.circle.fill"
        case .wrongItem: return "xmark.circle.fill"
        case .qualityIssue: return "star.slash.fill"
        case .packagingIssue: return "shippingbox.fill"
        case .other: return "ellipsis.circle.fill"
        }
    }
}

// MARK: - Issue Type Button Component

struct IssueTypeButton: View {
    let issueType: IssueType
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 8) {
                Image(systemName: issueType.iconName)
                    .font(.title2)
                    .foregroundColor(isSelected ? .white : .primary)

                Text(issueType.displayName)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(isSelected ? .white : .primary)
                    .multilineTextAlignment(.center)
            }
            .frame(height: 80)
            .frame(maxWidth: .infinity)
            .background(isSelected ? Color.blue : Color(.secondarySystemGroupedBackground))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? Color.blue : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Preview

#if DEBUG
struct ReportIssueView_Previews: PreviewProvider {
    static var previews: some View {
        let mockTask = FulfillmentTask(
            id: "mock_001",
            orderName: "#MOCK1001",
            status: .picking,
            shippingName: "Test Customer",
            createdAt: Date().ISO8601Format(),
            checklistJson: "[]",
            currentOperator: nil
        )

        let mockStaffManager = StaffManager()
        mockStaffManager.currentOperator = StaffMember(id: "staff1", name: "Test Operator")

        return NavigationStack {
            ReportIssueView(
                task: mockTask,
                currentOperator: mockStaffManager.currentOperator
            )
        }
        .environmentObject(DashboardViewModel())
    }
}
#endif
