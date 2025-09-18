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
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 50))
                .foregroundColor(.orange)
            
            Text("Inspection Failed")
                .font(.title2)
                .fontWeight(.bold)
            
            Text("Order: \(viewModel.task.orderName)")
                .font(.headline)
                .foregroundColor(.secondary)
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
            if viewModel.selectedErrorType != nil {
                costImpactSection
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
                    title: "Start Correction",
                    isLoading: viewModel.isLoading,
                    isDisabled: viewModel.selectedErrorType == nil || (viewModel.selectedErrorType == .packingError && viewModel.costImpact == nil)
                ) {
                    Task {
                        await viewModel.startCorrection()
                        dismiss()
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
