import SwiftUI

// MARK: - Inspection View

struct InspectionView: View {
    @StateObject private var viewModel: InspectionViewModel
    @Environment(\.dismiss) private var dismiss
    
    init(task: FulfillmentTask, currentOperator: StaffMember?) {
        _viewModel = StateObject(wrappedValue: InspectionViewModel(task: task, currentOperator: currentOperator))
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Main inspection content
                ScrollView {
                    VStack(spacing: 24) {
                        inspectionHeaderSection
                        packageInfoSection
                        inspectionCriteriaSection
                        inspectionNotesSection
                    }
                    .padding()
                }
                
                // Footer with Pass/Fail actions
                inspectionActionsFooter
            }
        }
        .navigationTitle("Quality Inspection")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button("Back") {
                    dismiss()
                }
            }
        }
        .overlay {
            if viewModel.isLoading {
                Color.black.opacity(0.4).ignoresSafeArea()
                ProgressView("Processing...")
                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    .scaleEffect(1.5)
                    .foregroundColor(.white)
            }
        }
        .alert("Error", isPresented: .constant(viewModel.errorMessage != nil)) {
            Button("OK") { viewModel.errorMessage = nil }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }
    
    // MARK: - Subviews
    
    private var inspectionHeaderSection: some View {
        VStack(spacing: 16) {
            // Inspection icon and title
            Image(systemName: "magnifyingglass.circle.fill")
                .font(.system(size: 60))
                .foregroundColor(.blue)
            
            VStack(spacing: 8) {
                Text("Quality Inspection")
                    .font(.title2)
                    .fontWeight(.bold)
                
                Text("Order: \(viewModel.task.orderName)")
                    .font(.headline)
                    .foregroundColor(.secondary)
                
                Text("Customer: \(viewModel.task.shippingName)")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            // Inspector info
            if let inspector = viewModel.currentOperator {
                HStack {
                    Image(systemName: "person.badge.shield.checkmark")
                        .foregroundColor(.blue)
                    Text("Inspector: \(inspector.name)")
                        .font(.subheadline)
                        .fontWeight(.medium)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color.blue.opacity(0.1))
                .cornerRadius(20)
            }
        }
    }
    
    private var packageInfoSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Package Information")
                .font(.headline)
                .fontWeight(.semibold)
            
            VStack(spacing: 12) {
                InfoRow(title: "Items Count", value: "\(viewModel.totalItemsCount)")
                InfoRow(title: "Package Weight", value: viewModel.packageWeight)
                InfoRow(title: "Package Dimensions", value: viewModel.packageDimensions)
                InfoRow(title: "Packed By", value: viewModel.packagedBy)
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(12)
    }
    
    private var inspectionCriteriaSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Inspection Checklist")
                .font(.headline)
                .fontWeight(.semibold)
            
            VStack(spacing: 12) {
                ForEach(viewModel.inspectionCriteria, id: \.title) { criteria in
                    InspectionCriteriaRow(
                        criteria: criteria,
                        isChecked: viewModel.checkedCriteria.contains(criteria.id),
                        onToggle: { isChecked in
                            viewModel.toggleCriteria(criteria.id, isChecked: isChecked)
                        }
                    )
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(12)
    }
    
    private var inspectionNotesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Inspection Notes")
                .font(.headline)
                .fontWeight(.semibold)
            
            TextField("Add any observations or comments...", text: $viewModel.inspectionNotes, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(3...6)
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(12)
    }
    
    private var inspectionActionsFooter: some View {
        VStack(spacing: 16) {
            // Pass/Fail buttons
            HStack(spacing: 16) {
                // Fail Inspection Button
                PrimaryButton(
                    title: "Fail Inspection",
                    color: .red,
                    isLoading: viewModel.isLoading && viewModel.pendingAction == .fail,
                    isDisabled: !viewModel.canFailInspection,
                    isSecondary: true,
                    isDestructive: true
                ) {
                    Task {
                        await viewModel.failInspection()
                        dismiss()
                    }
                }
                
                // Pass Inspection Button
                PrimaryButton(
                    title: "Pass Inspection",
                    color: .green,
                    isLoading: viewModel.isLoading && viewModel.pendingAction == .pass,
                    isDisabled: !viewModel.canPassInspection
                ) {
                    Task {
                        await viewModel.passInspection()
                        dismiss()
                    }
                }
            }
            
            // Inspection status indicator
            if viewModel.allCriteriaChecked {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text("All criteria reviewed")
                        .font(.caption)
                        .foregroundColor(.green)
                }
            } else {
                HStack {
                    Image(systemName: "clock.circle")
                        .foregroundColor(.orange)
                    Text("\(viewModel.remainingCriteriaCount) criteria remaining")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
            }
        }
        .padding()
        .background(.regularMaterial)
    }
}

// MARK: - Info Row Component

struct InfoRow: View {
    let title: String
    let value: String
    
    var body: some View {
        HStack {
            Text(title)
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            Spacer()
            
            Text(value)
                .font(.subheadline)
                .fontWeight(.medium)
        }
    }
}

// MARK: - Inspection Criteria Row Component

struct InspectionCriteriaRow: View {
    let criteria: InspectionCriteria
    let isChecked: Bool
    let onToggle: (Bool) -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            // Checkbox
            Button(action: {
                onToggle(!isChecked)
            }) {
                Image(systemName: isChecked ? "checkmark.square.fill" : "square")
                    .font(.title2)
                    .foregroundColor(isChecked ? .green : .gray)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(criteria.title)
                    .font(.body)
                    .fontWeight(.medium)
                    .foregroundColor(isChecked ? .primary : .secondary)
                
                if !criteria.description.isEmpty {
                    Text(criteria.description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            // Priority indicator
            if criteria.isRequired {
                Image(systemName: "exclamationmark.circle.fill")
                    .foregroundColor(.red)
                    .font(.caption)
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture {
            onToggle(!isChecked)
        }
    }
}

// MARK: - Preview
#if DEBUG
struct InspectionView_Previews: PreviewProvider {
    static var previews: some View {
        InspectionView(
            task: FulfillmentTask.previewPicking,
            currentOperator: StaffMember(id: "s001", name: "Inspector Tanaka")
        )
    }
}
#endif