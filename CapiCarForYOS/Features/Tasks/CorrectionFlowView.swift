import SwiftUI

// MARK: - Correction Flow View

struct CorrectionFlowView: View {
    @StateObject private var viewModel: CorrectionFlowViewModel
    @Environment(\.dismiss) private var dismiss
    
    init(task: FulfillmentTask, currentOperator: StaffMember?) {
        _viewModel = StateObject(wrappedValue: CorrectionFlowViewModel(task: task, currentOperator: currentOperator))
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                headerSection
                
                errorTypeSection
                
                actionButtonsSection
                
                Spacer()
            }
            .padding()
        }
        .navigationTitle("Correction Required")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(content: {
            ToolbarItem(placement: .navigationBarLeading) {
                Button("Cancel") {
                    dismiss()
                }
            }
        })
        .alert("Error", isPresented: .constant(viewModel.errorMessage != nil)) {
            Button("OK") { viewModel.errorMessage = nil }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }
    
    // MARK: - Subviews
    
    private var headerSection: some View {
        VStack(spacing: 12) {
            Image(systemName: headerIcon)
                .font(.system(size: 50))
                .foregroundColor(headerColor)

            Text(headerTitle)
                .font(.title2)
                .fontWeight(.bold)

            Text("\(viewModel.task.orderName)")
                .font(.headline)
                .foregroundColor(.secondary)
        }
    }

    private var headerIcon: String {
        switch viewModel.workflowState {
        case .initial:
            return "exclamationmark.triangle.fill"
        case .correcting:
            return "gearshape.fill"
        case .completing:
            return "checkmark.circle.fill"
        }
    }

    private var headerColor: Color {
        switch viewModel.workflowState {
        case .initial:
            return .orange
        case .correcting:
            return .blue
        case .completing:
            return .green
        }
    }

    private var headerTitle: String {
        switch viewModel.workflowState {
        case .initial:
            return "Inspection Failed"
        case .correcting:
            return "Correction in Progress"
        case .completing:
            return "Ready to Complete"
        }
    }
    
    private var errorTypeSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Error Type")
                .font(.headline)
            
            VStack(spacing: 12) {
                ErrorTypeButton(
                    title: "Picking Error",
                    subtitle: "Wrong items or quantities were picked",
                    icon: "basket.fill",
                    isSelected: viewModel.selectedErrorType == .pickingError
                ) {
                    viewModel.selectedErrorType = .pickingError
                }
                
                ErrorTypeButton(
                    title: "Packing Error", 
                    subtitle: "Items were packed incorrectly",
                    icon: "shippingbox.fill",
                    isSelected: viewModel.selectedErrorType == .packingError
                ) {
                    viewModel.selectedErrorType = .packingError
                }
            }
        }
    }
    
    private var actionButtonsSection: some View {
        VStack(spacing: 16) {
            if viewModel.selectedErrorType != nil && viewModel.workflowState == .initial {
                costImpactSection
            }

            // Show workflow state dependent content
            if viewModel.workflowState == .completing {
                correctionInProgressSection
            }

            HStack(spacing: 16) {
                PrimaryButton(
                    title: "Cancel",
                    isSecondary: true,
                    isDestructive: true
                ) {
                    dismiss()
                }

                PrimaryButton(
                    title: viewModel.primaryButtonTitle,
                    isLoading: viewModel.isLoading,
                    isDisabled: !viewModel.isPrimaryButtonEnabled
                ) {
                    Task {
                        switch viewModel.workflowState {
                        case .initial:
                            if viewModel.isHappyPath {
                                // Happy path: Complete entire workflow in one action
                                await viewModel.completeHappyPathWorkflow()
                                dismiss()
                            } else {
                                // Regular path: Just start correction
                                await viewModel.startCorrection()
                                // Don't dismiss immediately for non-happy path
                                if viewModel.workflowState != .completing {
                                    dismiss()
                                }
                            }
                        case .completing:
                            await viewModel.completeCorrection()
                            dismiss()
                        case .correcting:
                            break // Should not happen
                        }
                    }
                }
            }
        }
    }
    
    private var costImpactSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            if viewModel.selectedErrorType == .packingError {
                Text("Cost Impact")
                    .font(.headline)

                VStack(spacing: 8) {
                    CostImpactButton(
                        title: "Affects Shipping Cost",
                        subtitle: "Void label and create new one",
                        isSelected: viewModel.costImpact == .affectsCost
                    ) {
                        viewModel.costImpact = .affectsCost
                    }

                    CostImpactButton(
                        title: "No Cost Impact",
                        subtitle: "Reuse existing shipping label",
                        isSelected: viewModel.costImpact == .noCostImpact
                    ) {
                        viewModel.costImpact = .noCostImpact
                    }
                }
            }
        }
    }

    private var correctionInProgressSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                    .font(.title2)

                Text("Correction Ready")
                    .font(.headline)
                    .fontWeight(.semibold)
            }

            Text("The correction has been processed and is ready to be completed.")
                .font(.body)
                .foregroundColor(.secondary)

            if let errorType = viewModel.selectedErrorType {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Completed:")
                        .font(.subheadline)
                        .fontWeight(.medium)

                    Text("✓ \(errorType.displayName) correction")
                        .font(.body)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color.green.opacity(0.1))
                        .cornerRadius(8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.green.opacity(0.3), lineWidth: 1)
                        )
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color.green.opacity(0.05))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.green.opacity(0.3), lineWidth: 1.5)
        )
    }
}

// MARK: - Error Type Button

struct ErrorTypeButton: View {
    let title: String
    let subtitle: String
    let icon: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundColor(isSelected ? .white : .blue)
                    .frame(width: 30)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.body)
                        .fontWeight(.medium)
                        .foregroundColor(isSelected ? .white : .primary)
                    
                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(isSelected ? .white.opacity(0.8) : .secondary)
                }
                
                Spacer()
                
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.white)
                }
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected ? Color.blue : Color(.systemGray6))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? Color.blue : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Cost Impact Button

struct CostImpactButton: View {
    let title: String
    let subtitle: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.body)
                        .fontWeight(.medium)
                        .foregroundColor(isSelected ? .white : .primary)
                    
                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(isSelected ? .white.opacity(0.8) : .secondary)
                }
                
                Spacer()
                
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.white)
                }
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? Color.orange : Color(.systemGray6))
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Preview
#if DEBUG
struct CorrectionFlowView_Previews: PreviewProvider {
    static var previews: some View {
        CorrectionFlowView(
            task: FulfillmentTask.previewPicking,
            currentOperator: StaffMember(id: "s001", name: "Tanaka-san")
        )
    }
}
#endif
