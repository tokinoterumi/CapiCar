import SwiftUI

// MARK: - Task Detail View

struct TaskDetailView: View {
    
    @StateObject private var viewModel: TaskDetailViewModel
    
    // Environment property to dismiss the view (go back).
    @Environment(\.dismiss) private var dismiss
    
    // State for barcode search
    
    // State for correction flow
    @State private var showingCorrectionFlow = false

    // Removed inspection flow - now handled separately through TaskPreviewSheet

    // State for barcode scanning
    @State private var showingBarcodeScanner = false

    // State for issue reporting
    @State private var showingReportIssueView = false
    
    init(task: FulfillmentTask, currentOperator: StaffMember?) {
        // Initialize the StateObject with the passed-in data. This is the correct pattern.
        _viewModel = StateObject(wrappedValue: TaskDetailViewModel(task: task, currentOperator: currentOperator))
    }

    // Only show pause button for active work statuses that can actually be paused
    private var canShowPauseButton: Bool {
        // Don't show pause button if task is already paused
        guard viewModel.task.isPaused != true else { return false }

        // Only show for active work statuses
        switch viewModel.task.status {
        case .picking, .inspecting, .correcting:
            return true
        default:
            return false
        }
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
        .overlay(alignment: .bottomLeading) {
            // Floating barcode scan button
            if viewModel.task.status == .picking || viewModel.task.status == .pending {
                floatingBarcodeScanButton
            }
        }
        .navigationTitle(viewModel.task.orderName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(content: {
            // Report Issue button (always available)
            ToolbarItem(placement: .navigationBarLeading) {
                Button(action: { showingReportIssueView = true }) {
                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.triangle")
                        Text("Report")
                    }
                    .foregroundColor(.orange)
                }
                .disabled(viewModel.isLoading)
            }

            // Toolbar button for the "Pause" escape hatch - only show for active work statuses
            if canShowPauseButton {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        Task {
                            await viewModel.pauseTask()
                            // After pausing, dismiss the view to return to the dashboard.
                            dismiss()
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "pause.circle")
                            Text("Pause")
                        }
                    }
                    .disabled(viewModel.isLoading)
                }
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

            // Real shipping address data from task
            VStack(alignment: .leading, spacing: 2) {
                if let address1 = viewModel.task.shippingAddress1, !address1.isEmpty {
                    Text(address1)
                        .font(.body)
                        .foregroundColor(.secondary)
                }

                if let address2 = viewModel.task.shippingAddress2, !address2.isEmpty {
                    Text(address2)
                        .font(.body)
                        .foregroundColor(.secondary)
                }

                // City, Province, ZIP
                let locationLine = buildLocationLine(task: viewModel.task)
                if !locationLine.isEmpty {
                    Text(locationLine)
                        .font(.body)
                        .foregroundColor(.secondary)
                }

                // Phone number if available
                if let phone = viewModel.task.shippingPhone, !phone.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "phone.fill")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(phone)
                            .font(.body)
                            .foregroundColor(.secondary)
                    }
                    .padding(.top, 2)
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(12)
    }
    
    private var checklistSection: some View {
        VStack(alignment: .leading) {
            HStack {
                Text("Packing List")
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
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(12)
    }
    
    private var footerActionView: some View {
        VStack(spacing: 16) {
            // Conditionally show input fields when picked and ready for packing, or when correcting
            if viewModel.task.status == .picked || viewModel.task.status == .correcting {
                VStack(spacing: 16) {
                    // Weight input field
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Package Weight")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(.primary)

                        HStack(spacing: 8) {
                            TextField("0.0", text: $viewModel.weightInput)
                                .keyboardType(.decimalPad)
                                .textFieldStyle(.roundedBorder)

                            Text("kg")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                    }

                    // Dimensions selection field
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Package Dimensions")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(.primary)

                        Picker("Select dimensions", selection: $viewModel.selectedDimension) {
                            ForEach(viewModel.dimensionOptions, id: \.self) { dimension in
                                Text("\(dimension) cm")
                                    .tag(dimension)
                            }
                        }
                        .pickerStyle(.menu)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color(.systemGray4), lineWidth: 1)
                        )
                    }
                }
            }

            // Status-specific secondary actions
            if viewModel.task.status == .packed || viewModel.task.status == .inspecting {
                HStack(spacing: 12) {
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


            // Main action button - only show when there's an action available
            if !viewModel.primaryActionText.isEmpty {
                PrimaryButton(
                    title: viewModel.primaryActionText,
                    isLoading: viewModel.isLoading,
                    isDisabled: !viewModel.canPerformPrimaryAction,
                    action: {
                        Task {
                            // Check if this is an action that should dismiss the view after completion
                            let shouldDismiss = (viewModel.task.status == .picked && viewModel.primaryActionText == "Packing Completed") ||
                                              (viewModel.task.status == .correcting && viewModel.primaryActionText == "Complete Correction")

                            await viewModel.handlePrimaryAction()

                            // Dismiss the view after completion
                            if shouldDismiss {
                                dismiss()
                            }
                        }
                    }
                )
            }
        }
        .padding()
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
        .padding(.leading, 24)
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

    // MARK: - Helper Methods

    private func buildLocationLine(task: FulfillmentTask) -> String {
        var components: [String] = []

        if let city = task.shippingCity, !city.isEmpty {
            components.append(city)
        }

        if let province = task.shippingProvince, !province.isEmpty {
            components.append(province)
        }

        if let zip = task.shippingZip, !zip.isEmpty {
            components.append(zip)
        }

        return components.joined(separator: ", ")
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
        
        var mockTask = FulfillmentTask(
            id: "prev_001",
            orderName: "#PREV1001",
            status: .picking,
            shippingName: "Tim Cook",
            createdAt: Date().ISO8601Format(),
            checklistJson: sampleChecklistJSON,
            currentOperator: StaffMember(id: "s001", name: "Tanaka-san")
        )

        // Add shipping address data for preview
        mockTask.shippingAddress1 = "1 Apple Park Way"
        mockTask.shippingAddress2 = "Building 4"
        mockTask.shippingCity = "Cupertino"
        mockTask.shippingProvince = "CA"
        mockTask.shippingZip = "95014"
        mockTask.shippingPhone = "+1 (408) 996-1010"

        return mockTask
    }
}

struct TaskDetailView_Previews: PreviewProvider {
    static var previews: some View {
        let mockSyncManager = SyncManager.shared
        
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

