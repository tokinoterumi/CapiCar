import SwiftUI

// MARK: - Details Modal View

/// A view presented as a modal sheet to show a read-only summary of a task.
struct DetailsModalView: View {
    
    /// The task to be displayed in the modal.
    let task: FulfillmentTask
    
    /// A private state property to hold the checklist items after parsing the JSON.
    @State private var checklistItems: [ChecklistItem] = []
    
    /// The dismiss action is retrieved from the environment to allow the view to close itself.
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        // Wrap the content in a NavigationView to get a title bar and toolbar.
        NavigationView {
            VStack(alignment: .leading, spacing: 0) {
                // Header section with customer and order information.
                headerView
                
                // The list of checklist items.
                List(checklistItems) { item in
                    ChecklistItemRowView(item: item)
                }
                .listStyle(.plain)
            }
            .navigationTitle("Task Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // A standard "Done" button to dismiss the modal.
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .onAppear(perform: parseChecklist)
        }
    }
    
    /// A helper subview for the header content.
    private var headerView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(task.orderName)
                .font(.title2).bold()
            
            HStack {
                Image(systemName: "person.fill")
                Text(task.shippingName)
            }
            .font(.subheadline)
            .foregroundColor(.secondary)
            
            Divider()
        }
        .padding()
    }
    
    /// Parses the `checklistJson` string from the task into an array of `ChecklistItem` objects.
    private func parseChecklist() {
        guard let data = task.checklistJson.data(using: .utf8) else {
            print("Error: Could not convert checklist JSON string to data.")
            return
        }
        
        do {
            // Use the shared JSON decoder from APIService for consistency.
            self.checklistItems = try APIService.shared.jsonDecoder.decode([ChecklistItem].self, from: data)
        } catch {
            print("Error decoding checklist JSON: \(error)")
            // If decoding fails, ensure the list is empty.
            self.checklistItems = []
        }
    }
}

// MARK: - Checklist Item Row View

/// A small, reusable view to display a single item from the checklist in a read-only format.
struct ChecklistItemRowView: View {
    let item: ChecklistItem
    
    var body: some View {
        HStack(spacing: 12) {
            // Asynchronously load the product image from the URL.
            AsyncImage(url: URL(string: item.image_url ?? "")) { image in
                image.resizable()
                    .aspectRatio(contentMode: .fill)
            } placeholder: {
                // A simple gray placeholder with an icon for missing images.
                ZStack {
                    Color(.systemGray5)
                    Image(systemName: "photo")
                        .foregroundColor(.secondary)
                }
            }
            .frame(width: 60, height: 60)
            .cornerRadius(8)
            
            VStack(alignment: .leading) {
                Text(item.name)
                    .font(.headline)
                    .lineLimit(2)
                Text(item.variant_title)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text("SKU: \(item.sku)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // Display the required quantity.
            Text("x\(item.quantity_required)")
                .font(.title3)
                .fontWeight(.bold)
        }
        .padding(.vertical, 8)
    }
}


// MARK: - Preview

struct DetailsModalView_Previews: PreviewProvider {
    
    // A detailed mock task for a realistic preview.
    static let mockTask = FulfillmentTask(
        id: "task_003",
        orderName: "#YM1027",
        status: .picking,
        shippingName: "Takahashi Yui",
        createdAt: Date(),
        checklistJson: """
        [
            {
                "id": 12345,
                "sku": "TEE-WHT-APL-XL",
                "name": "Yamanouchi Original T-Shirt With A Very Long Name For Testing Text Wrapping",
                "variant_title": "Apple / XL",
                "quantity_required": 1,
                "image_url": "https://placehold.co/120x120/a9a9a9/ffffff?text=Image1"
            },
            {
                "id": 67890,
                "sku": "STCK-RET-ONS-SM",
                "name": "Yamanouchi Sticker",
                "variant_title": "Retro / Onsen",
                "quantity_required": 2,
                "image_url": null
            }
        ]
        """,
        currentOperator: StaffMember(id: "s001", name: "Tanaka-san")
    )
    
    static var previews: some View {
        DetailsModalView(task: mockTask)
    }
}
