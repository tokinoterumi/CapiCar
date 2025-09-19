import SwiftUI

// MARK: - Report Issue View

struct ReportIssueView: View {
    @StateObject private var viewModel: ReportIssueViewModel
    @Environment(\.dismiss) private var dismiss

    init(task: FulfillmentTask, currentOperator: StaffMember?) {
        _viewModel = StateObject(wrappedValue: ReportIssueViewModel(task: task, currentOperator: currentOperator))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    headerSection

                    // 📝 詳細記録 / Detailed Logging
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
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(12)
    }

    // 📝 詳細記録 / Detailed Logging Section
    private var loggingInfoSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "doc.text.fill")
                    .foregroundColor(.blue)
                Text("📝 詳細記録 / Detailed Logging")
                    .font(.headline)
                    .fontWeight(.semibold)
            }

            VStack(alignment: .leading, spacing: 12) {
                // 担当者 / Operator
                HStack {
                    Image(systemName: "person.fill")
                        .foregroundColor(.green)
                        .frame(width: 20)
                    Text("担当者 / Operator:")
                        .fontWeight(.medium)
                    Spacer()
                    Text(viewModel.currentOperator?.name ?? "Unknown")
                        .foregroundColor(.secondary)
                }

                Divider()

                // 時刻 / Timestamp
                HStack {
                    Image(systemName: "clock.fill")
                        .foregroundColor(.orange)
                        .frame(width: 20)
                    Text("時刻 / Timestamp:")
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
                        .foregroundColor(.purple)
                        .frame(width: 20)
                    Text("Current Status:")
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
                    .foregroundColor(.red)
                Text("理由 / Issue Type")
                    .font(.headline)
                    .fontWeight(.semibold)
            }

            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 12) {
                ForEach(IssueType.allCases, id: \.self) { issueType in
                    Button(action: {
                        viewModel.selectedIssueType = issueType
                    }) {
                        VStack(spacing: 8) {
                            Image(systemName: issueType.iconName)
                                .font(.title2)
                                .foregroundColor(viewModel.selectedIssueType == issueType ? .white : issueType.color)

                            Text(issueType.displayName)
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundColor(viewModel.selectedIssueType == issueType ? .white : .primary)
                                .multilineTextAlignment(.center)
                        }
                        .frame(height: 80)
                        .frame(maxWidth: .infinity)
                        .background(viewModel.selectedIssueType == issueType ? issueType.color : Color(.secondarySystemGroupedBackground))
                        .cornerRadius(12)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(viewModel.selectedIssueType == issueType ? issueType.color : Color.clear, lineWidth: 2)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(12)
    }

    private var descriptionSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "text.bubble")
                    .foregroundColor(.blue)
                Text("詳細説明 / Description")
                    .font(.headline)
                    .fontWeight(.semibold)
            }

            TextField("Describe the issue in detail...", text: $viewModel.issueDescription, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(4...8)

            Text("Please provide as much detail as possible to help resolve the issue.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(12)
    }

    private var actionButtonsSection: some View {
        VStack(spacing: 16) {
            PrimaryButton(
                title: "Submit Issue Report",
                isLoading: viewModel.isLoading,
                isDisabled: !viewModel.canSubmitReport,
                action: {
                    print("🔍 ReportIssueView: Submit button tapped")
                    Task {
                        await viewModel.submitIssueReport()
                    }
                }
            )

            if !viewModel.canSubmitReport {
                Text("Please select an issue type to continue")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
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
    case systemError = "system_error"
    case equipmentFailure = "equipment_failure"
    case other = "other"

    var displayName: String {
        switch self {
        case .damagedItem: return "Damaged Item\n商品破損"
        case .missingItem: return "Missing Item\n商品不足"
        case .wrongItem: return "Wrong Item\n商品違い"
        case .qualityIssue: return "Quality Issue\n品質問題"
        case .packagingIssue: return "Packaging Issue\n梱包問題"
        case .systemError: return "System Error\nシステムエラー"
        case .equipmentFailure: return "Equipment Failure\n機器故障"
        case .other: return "Other\nその他"
        }
    }

    var iconName: String {
        switch self {
        case .damagedItem: return "exclamationmark.triangle.fill"
        case .missingItem: return "questionmark.circle.fill"
        case .wrongItem: return "xmark.circle.fill"
        case .qualityIssue: return "star.slash.fill"
        case .packagingIssue: return "shippingbox.fill"
        case .systemError: return "laptopcomputer.trianglebadge.exclamationmark"
        case .equipmentFailure: return "wrench.and.screwdriver.fill"
        case .other: return "ellipsis.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .damagedItem: return .red
        case .missingItem: return .orange
        case .wrongItem: return .red
        case .qualityIssue: return .yellow
        case .packagingIssue: return .blue
        case .systemError: return .purple
        case .equipmentFailure: return .brown
        case .other: return .gray
        }
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
    }
}
#endif