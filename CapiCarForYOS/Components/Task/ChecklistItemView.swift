import SwiftUI

// MARK: - Checklist Item View

struct ChecklistItemView: View {
    
    // Use a @Binding to allow this view to modify the item from the parent ViewModel.
    @Binding var item: ChecklistItem
    
    // Use @ObservedObject to receive the ViewModel and call its methods.
    @ObservedObject var viewModel: TaskDetailViewModel

    var body: some View {
        HStack(spacing: 16) {
            // In a real app, you'd use an AsyncImage to load the URL.
            // For now, a placeholder is used.
            Image(systemName: "photo.fill")
                .resizable()
                .scaledToFit()
                .frame(width: 50, height: 50)
                .background(Color(.systemGray5))
                .cornerRadius(8)
                .opacity(item.is_completed ? 0.5 : 1.0)

            VStack(alignment: .leading, spacing: 4) {
                Text(item.name)
                    .fontWeight(.semibold)
                Text(item.variant_title)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .opacity(item.is_completed ? 0.5 : 1.0)
            
            Spacer()

            // Conditionally show a Stepper for multi-quantity items
            // or a Checkbox for single-quantity items.
            if item.quantity_required > 1 {
                multiQuantityControl
            } else {
                singleQuantityControl
            }
        }
        .padding(.vertical, 12)
        .contentShape(Rectangle()) // Make the whole Hstack tappable for accessibility
        .background(
            // Highlight effect for scanned items
            viewModel.highlightedItemId == item.id ? 
            Color.yellow.opacity(0.3) : Color.clear
        )
        .animation(.default, value: item.is_completed)
        .animation(.default, value: item.quantity_picked)
        .animation(.easeInOut(duration: 0.5), value: viewModel.highlightedItemId)
    }
    
    // MARK: - Subviews for Controls
    
    private var multiQuantityControl: some View {
        HStack(spacing: 12) {
            Button(action: { 
                Task {
                    await viewModel.decrementQuantity(for: item)
                }
            }) {
                Image(systemName: "minus.circle.fill")
            }
            
            Text("\(item.quantity_picked) / \(item.quantity_required)")
                .font(Font.system(.headline, design: .monospaced))
                .frame(minWidth: 60) // Ensure consistent width
            
            Button(action: { 
                Task {
                    await viewModel.incrementQuantity(for: item)
                }
            }) {
                Image(systemName: "plus.circle.fill")
            }
        }
        .font(.title2)
        .foregroundColor(item.is_completed ? .green : .accentColor)
    }
    
    private var singleQuantityControl: some View {
        Button(action: { viewModel.toggleCompletion(for: item) }) {
            Image(systemName: item.is_completed ? "checkmark.circle.fill" : "circle")
                .font(.title)
                .foregroundColor(item.is_completed ? .green : .secondary)
        }
    }
}

// MARK: - Preview
#if DEBUG
struct ChecklistItemView_Previews: PreviewProvider {
    
    // A simple mock ViewModel for the preview to function.
    class MockTaskDetailViewModel: TaskDetailViewModel {
        // You can override methods here for preview-specific logic if needed.
    }

    // A stateful wrapper to allow interaction with the @Binding in the preview.
    struct PreviewWrapper: View {
        @State private var singleItem = ChecklistItem.previewSingle
        @State private var multiItem = ChecklistItem.previewMulti
        
        // Create a static instance of the mock task for the VM
        private static var mockTask = FulfillmentTask.previewPicking
        
        // Create a single instance of the mock VM
        @StateObject private var viewModel = MockTaskDetailViewModel(
            task: mockTask,
            currentOperator: mockTask.currentOperator
        )
        
        var body: some View {
            List {
                Section("Single-Quantity Item") {
                    ChecklistItemView(item: $singleItem, viewModel: viewModel)
                }
                
                Section("Multi-Quantity Item") {
                    ChecklistItemView(item: $multiItem, viewModel: viewModel)
                }
            }
        }
    }

    static var previews: some View {
        PreviewWrapper()
    }
}

// Create an extension on ChecklistItem to provide sample data for the preview.
extension ChecklistItem {
    static var previewSingle: ChecklistItem {
        ChecklistItem(
            id: 1,
            sku: "TS-BLK-L",
            name: "Classic T-Shirt",
            variant_title: "Black / L",
            quantity_required: 1,
            image_url: nil,
            quantity_picked: 0,
            is_completed: false
        )
    }
    
    static var previewMulti: ChecklistItem {
        ChecklistItem(
            id: 2,
            sku: "MUG-WHT-01",
            name: "Company Mug",
            variant_title: "White",
            quantity_required: 3,
            image_url: nil,
            quantity_picked: 0,
            is_completed: false
        )
    }
}
#endif
