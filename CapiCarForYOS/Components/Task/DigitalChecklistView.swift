import SwiftUI

/// A view that displays a READ-ONLY list of checklist items.
/// This is used for the "Details Modal" to preview the task contents
/// without allowing interaction.
struct DigitalChecklistView: View {
    
    // MARK: - Properties
    
    /// This is now a simple array of items, not a binding,
    /// as this view does not modify the data.
    let items: [ChecklistItem]
    
    // MARK: - Body
    
    var body: some View {
        // Use a List for proper styling and scrolling.
        List {
            ForEach(items) { item in
                // We no longer call the complex ChecklistItemView.
                // Instead, we use a simple, private view for read-only display.
                readOnlyItemRow(for: item)
            }
        }
        .listStyle(.plain) // A clean style for embedding in a modal.
    }
    
    // MARK: - Private Subview
    
    /// A private helper view to display a single read-only checklist item.
    /// This keeps the main body clean and encapsulates the item's layout.
    private func readOnlyItemRow(for item: ChecklistItem) -> some View {
        HStack(spacing: 16) {
            // Placeholder for the image
            Image(systemName: "photo")
                .resizable()
                .scaledToFit()
                .frame(width: 44, height: 44)
                .background(Color(.systemGray6))
                .cornerRadius(8)

            VStack(alignment: .leading, spacing: 4) {
                Text(item.name)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                
                Text(item.variant_title)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // Display the required quantity
            Text("x\(item.quantity_required)")
                .font(Font.system(.title2, design: .monospaced).weight(.bold))
                .foregroundColor(.primary)
        }
        .padding(.vertical, 8)
    }
}

// MARK: - Preview
#if DEBUG
struct DigitalChecklistView_Previews: PreviewProvider {
    
    // Sample data for the preview.
    static let sampleItems: [ChecklistItem] = [
        ChecklistItem(
            id: 1, sku: "TS-BLK-L", name: "Classic T-Shirt",
            variant_title: "Black / L", quantity_required: 1, image_url: nil
        ),
        ChecklistItem(
            id: 2, sku: "MUG-WHT-01", name: "Company Mug",
            variant_title: "White", quantity_required: 3, image_url: nil
        ),
        ChecklistItem(
            id: 3, sku: "STCK-LOGO", name: "Logo Sticker",
            variant_title: "Standard", quantity_required: 10, image_url: nil, is_completed: true
        )
    ]
    
    static var previews: some View {
        // We embed it in a NavigationView to give it context.
        NavigationView {
            DigitalChecklistView(items: sampleItems)
                .navigationTitle("Packing Slip")
        }
    }
}
#endif
