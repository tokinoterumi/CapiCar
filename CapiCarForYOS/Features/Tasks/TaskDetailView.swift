import SwiftUI

// MARK: - Task Detail View

struct TaskDetailView: View {
    
    @StateObject private var viewModel: TaskDetailViewModel
    
    // Environment property to dismiss the view (go back).
    @Environment(\.dismiss) private var dismiss
    
    // State for barcode search
    
    // State for correction flow
    @State private var showingCorrectionFlow = false

    // State for inspection flow
    @State private var showingInspectionView = false

    // State for barcode scanning
    @State private var showingBarcodeScanner = false

    // State for issue reporting
    @State private var showingReportIssueView = false
    
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
        .overlay(alignment: .bottomTrailing) {
            // Floating barcode scan button
            if viewModel.task.status == .picking || viewModel.task.status == .pending {
                floatingBarcodeScanButton
            }
        }
        .navigationTitle(viewModel.task.orderName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(content: {
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
        })
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
        // Report issue view sheet
        .sheet(isPresented: $showingReportIssueView) {
            ReportIssueView(
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
        VStack(spacing: 16) {
            // Conditionally show input fields when picked and ready for packing
            if viewModel.task.status == .picked {
                HStack(spacing: 16) {
                    TextField("Weight (kg)", text: $viewModel.weightInput)
                        .keyboardType(.decimalPad)
                    TextField("Dimensions (cm)", text: $viewModel.dimensionsInput)
                }
                .textFieldStyle(.roundedBorder)
            }

            // Status-specific secondary actions
            if viewModel.task.status == .packed || viewModel.task.status == .inspecting {
                HStack(spacing: 12) {
                    PrimaryButton(
                        title: "Detailed Inspection",
                        isSecondary: true
                    ) {
                        showingInspectionView = true
                    }

                    if viewModel.task.status == .inspecting {
                        PrimaryButton(
                            title: "Fail Inspection",
                            isSecondary: true,
                            isDestructive: true
                        ) {
                            showingCorrectionFlow = true
                        }
                    }
                }
            }

            // Secondary actions for all statuses
            HStack(spacing: 12) {
                PrimaryButton(
                    title: "Report Issue",
                    isSecondary: true,
                    isDestructive: true
                ) {
                    showingReportIssueView = true
                }

                // Pause is already in toolbar, but could add here if needed
            }

            // Main action button - only show when there's an action available
            if !viewModel.primaryActionText.isEmpty {
                PrimaryButton(
                    title: viewModel.primaryActionText,
                    isLoading: viewModel.isLoading,
                    isDisabled: !viewModel.canPerformPrimaryAction,
                    action: {
                        Task {
                            // Check if this is the "Packing Completed" action before execution
                            let shouldDismiss = viewModel.task.status == .picked && viewModel.primaryActionText == "Packing Completed"

                            await viewModel.handlePrimaryAction()

                            // Dismiss the view after "Packing Completed" action completes
                            if shouldDismiss {
                                dismiss()
                            }
                        }
                    }
                )
            }
        }
        .padding()
        .background(.regularMaterial)
    }

    private var floatingBarcodeScanButton: some View {
        Button(action: {
            showingBarcodeScanner = true
        }) {
            Image(systemName: "barcode.viewfinder")
                .font(.title2)
                .foregroundColor(.white)
                .frame(width: 56, height: 56)
                .background(Color.primaryTeal)
                .clipShape(Circle())
                .shadow(color: .black.opacity(0.2), radius: 8, x: 0, y: 4)
        }
        .padding(.trailing, 24)
        .padding(.bottom, 100) // Position above footer
        .sheet(isPresented: $showingBarcodeScanner) {
            BarcodeScannerView { scannedCode in
                handleScannedBarcode(scannedCode)
                showingBarcodeScanner = false
            }
        }
    }

    private func handleScannedBarcode(_ code: String) {
        // Find matching item by SKU
        if let matchingItem = viewModel.checklistItems.first(where: { $0.sku == code }) {
            // Auto-increment the matching item
            Task {
                await viewModel.incrementQuantity(for: matchingItem)
            }

            // Provide haptic feedback for successful match
            let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
            impactFeedback.impactOccurred()
        } else {
            // Show brief alert for no match, but don't block workflow
            viewModel.errorMessage = "No item found with barcode: \(code)"
        }
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
            createdAt: Date().ISO8601Format(),
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

