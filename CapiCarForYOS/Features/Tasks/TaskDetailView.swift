import SwiftUI

// MARK: - Task Detail View

struct TaskDetailView: View {
    
    @StateObject private var viewModel: TaskDetailViewModel
    
    // Environment property to dismiss the view (go back).
    @Environment(\.dismiss) private var dismiss
    
    // State for barcode search
    @State private var showingBarcodeSearch = false
    
    // State for correction flow
    @State private var showingCorrectionFlow = false
    
    // State for inspection flow
    @State private var showingInspectionView = false
    
    init(task: FulfillmentTask, currentOperator: StaffMember?) {
        // Initialize the StateObject with the passed-in data. This is the correct pattern.
        _viewModel = StateObject(wrappedValue: TaskDetailViewModel(task: task, currentOperator: currentOperator))
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // --- Main Content: Scrollable Checklist ---
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    customerInfoSection
                    checklistSection
                }
                .padding()
            }
            
            // --- Footer: Action Buttons and Conditional Inputs ---
            footerActionView
        }
        .navigationTitle(viewModel.task.orderName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            // Toolbar button for the "Pause" escape hatch.
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Pause") {
                    Task {
                        await viewModel.pauseTask()
                        // After pausing, dismiss the view to return to the dashboard.
                        dismiss()
                    }
                }
                .disabled(viewModel.isLoading)
            }
        }
        .overlay {
            // Show a loading spinner over the whole view when isLoading is true.
            if viewModel.isLoading {
                Color.black.opacity(0.4).ignoresSafeArea()
                ProgressView("Updating...")
                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    .scaleEffect(1.5)
                    .foregroundColor(.white)
            }
        }
        // Show an alert if an error message is set.
        .alert("Error", isPresented: .constant(viewModel.errorMessage != nil), actions: {
            Button("OK", role: .cancel) { viewModel.errorMessage = nil }
        }, message: {
            Text(viewModel.errorMessage ?? "An unknown error occurred.")
        })
        // Barcode search sheet
        .sheet(isPresented: $showingBarcodeSearch) {
            BarcodeSearchView(
                isPresented: $showingBarcodeSearch,
                checklistItems: viewModel.checklistItems,
                onItemFound: { item in
                    viewModel.highlightItem(item)
                },
                onItemNotFound: { query in
                    viewModel.reportMissingItem(query)
                }
            )
        }
        // Correction flow sheet
        .sheet(isPresented: $showingCorrectionFlow) {
            CorrectionFlowView(
                task: viewModel.task,
                currentOperator: viewModel.currentOperator
            )
        }
        // Inspection view sheet
        .sheet(isPresented: $showingInspectionView) {
            InspectionView(
                task: viewModel.task,
                currentOperator: viewModel.currentOperator
            )
        }
    }
    
    // MARK: - Subviews
    
    private var customerInfoSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Shipping To")
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            Text(viewModel.task.shippingName)
                .font(.headline)
            
            // In a real app, you would add the full address from the task model.
            Text("123 Apple Park Way, Cupertino, CA")
                .font(.body)
                .foregroundColor(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(12)
    }
    
    private var checklistSection: some View {
        VStack(alignment: .leading) {
            HStack {
                Text("Items to Pick")
                    .font(.title3.bold())
                
                Spacer()
                
                // Quick search/scan button
                Button(action: {
                    showingBarcodeSearch = true
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "barcode.viewfinder")
                            .font(.caption)
                        Text("Find Item")
                            .font(.caption)
                            .fontWeight(.medium)
                    }
                    .foregroundColor(.blue)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.blue.opacity(0.1))
                    .cornerRadius(16)
                }
            }
            .padding(.bottom, 8)
            
            // Using LazyVStack for performance with potentially long lists.
            LazyVStack(spacing: 0) {
                ForEach($viewModel.checklistItems) { $item in
                    ChecklistItemView(item: $item, viewModel: viewModel)
                    Divider()
                }
            }
        }
    }
    
    private var footerActionView: some View {
        VStack(spacing: 12) {
            // Conditionally show input fields when picked and ready for packing.
            if viewModel.task.status == .picked {
                HStack(spacing: 16) {
                    TextField("Weight (kg)", text: $viewModel.weightInput)
                        .keyboardType(.decimalPad)
                    TextField("Dimensions (cm)", text: $viewModel.dimensionsInput)
                }
                .textFieldStyle(.roundedBorder)
            }

            // Show detailed inspection interface when packed or inspecting
            if viewModel.task.status == .packed {
                PrimaryButton(
                    title: "Start Detailed Inspection",
                    color: .blue
                ) {
                    showingInspectionView = true
                }
            }
            
            // Show inspection failure button when inspecting
            if viewModel.task.status == .inspecting {
                HStack(spacing: 12) {
                    PrimaryButton(
                        title: "Detailed Inspection",
                        isSecondary: true
                    ) {
                        showingInspectionView = true
                    }
                    
                    PrimaryButton(
                        title: "Fail Inspection",
                        isSecondary: true,
                        isDestructive: true
                    ) {
                        showingCorrectionFlow = true
                    }
                }
            }
            
            // Separate action buttons for Report Issue and Cancel
            HStack(spacing: 12) {
                // Report Issue button - leads to exception handling
                PrimaryButton(
                    title: "Report Issue",
                    isSecondary: true,
                    isDestructive: true
                ) {
                    Task {
                        await viewModel.reportException(reason: "Issue reported by operator")
                        dismiss()
                    }
                }
                
                // Cancel button - leads to task cancellation
                PrimaryButton(
                    title: "Cancel",
                    isSecondary: true,
                    isDestructive: true
                ) {
                    Task {
                        await viewModel.cancelTask()
                        dismiss()
                    }
                }
            }
            
            // The main action button.
            PrimaryButton(
                title: viewModel.primaryActionText,
                isLoading: viewModel.isLoading,
                isDisabled: !viewModel.canPerformPrimaryAction,
                action: {
                    Task {
                        await viewModel.handlePrimaryAction()
                    }
                }
            )
        }
        .padding()
        .background(.regularMaterial) // A blurred background that adapts.
    }
}


// MARK: - Preview
#if DEBUG

extension FulfillmentTask {
    static var previewPicking: FulfillmentTask {
        // Create a sample JSON string that matches the structure of your ChecklistItem model.
        let sampleChecklistJSON = """
        [
            {
                "id": 1,
                "sku": "TS-BLK-L",
                "name": "Classic T-Shirt",
                "variant_title": "Black / L",
                "quantity_required": 1,
                "image_url": null,
                "quantity_picked": 0,
                "is_completed": false
            },
            {
                "id": 2,
                "sku": "MUG-WHT-01",
                "name": "Company Mug",
                "variant_title": "White",
                "quantity_required": 3,
                "image_url": null,
                "quantity_picked": 0,
                "is_completed": false
            }
        ]
        """
        
        return FulfillmentTask(
            id: "prev_001",
            orderName: "#PREV1001",
            status: .picking,
            shippingName: "Tim Cook",
            createdAt: Date(),
            checklistJson: sampleChecklistJSON,
            currentOperator: StaffMember(id: "s001", name: "Tanaka-san")
        )
    }
}

struct TaskDetailView_Previews: PreviewProvider {
    static var previews: some View {
        let mockSyncManager = SyncManager()
        
        NavigationStack {
            TaskDetailView(
                task: FulfillmentTask.previewPicking, // Use the static preview data from the model extension
                currentOperator: StaffMember(id: "s001", name: "Tanaka-san")
            )
        }
        .environmentObject(mockSyncManager)
    }
}
#endif

