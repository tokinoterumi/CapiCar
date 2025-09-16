import SwiftUI

struct BarcodeSearchView: View {
    @Binding var isPresented: Bool
    let checklistItems: [ChecklistItem]
    let onItemFound: (ChecklistItem) -> Void
    let onItemNotFound: (String) -> Void
    
    @State private var showingScanner = false
    @State private var searchText = ""
    @State private var scannedBarcode: String?
    @State private var searchResults: [ChecklistItem] = []
    @State private var isSearching = false
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Search header
                searchHeaderView
                
                // Search results or empty state
                if isSearching {
                    searchingView
                } else if searchResults.isEmpty && !searchText.isEmpty {
                    noResultsView
                } else if searchResults.isEmpty {
                    emptyStateView
                } else {
                    searchResultsList
                }
            }
            .navigationTitle("Find Item")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        isPresented = false
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        showingScanner = true
                    }) {
                        Image(systemName: "barcode.viewfinder")
                            .font(.title3)
                    }
                }
            }
        }
        .sheet(isPresented: $showingScanner) {
            CameraScannerView(
                onScanResult: { barcode in
                    handleScannedBarcode(barcode)
                },
                onScanError: { error in
                    // Handle scan errors by dismissing scanner and showing in search
                    showingScanner = false
                    searchText = "Error: \(error)"
                }
            )
        }
        .onAppear {
            // Initialize with all items
            searchResults = checklistItems
        }
    }
    
    // MARK: - Subviews
    
    private var searchHeaderView: some View {
        VStack(spacing: 16) {
            // Search field
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                
                TextField("Search by SKU, name, or scan barcode", text: $searchText)
                    .textFieldStyle(.plain)
                    .onChange(of: searchText) { _, newValue in
                        performSearch(query: newValue)
                    }
                
                if !searchText.isEmpty {
                    Button(action: {
                        searchText = ""
                        searchResults = checklistItems
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding()
            .background(Color(.secondarySystemGroupedBackground))
            .cornerRadius(10)
            
            // Scanned barcode indicator
            if let barcode = scannedBarcode {
                HStack {
                    Image(systemName: "barcode")
                        .foregroundColor(.blue)
                    Text("Scanned: \(barcode)")
                        .font(.subheadline)
                        .foregroundColor(.blue)
                    Spacer()
                    Button("Clear") {
                        scannedBarcode = nil
                        searchText = ""
                        searchResults = checklistItems
                    }
                    .font(.subheadline)
                    .foregroundColor(.blue)
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(Color.blue.opacity(0.1))
                .cornerRadius(8)
            }
            
            // Quick actions
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    quickActionButton(title: "Scan Barcode", icon: "barcode.viewfinder") {
                        showingScanner = true
                    }
                    
                    quickActionButton(title: "View All", icon: "list.bullet") {
                        searchText = ""
                        scannedBarcode = nil
                        searchResults = checklistItems
                    }
                    
                    quickActionButton(title: "Pending Only", icon: "clock") {
                        filterPendingItems()
                    }
                }
                .padding(.horizontal)
            }
        }
        .padding()
        .background(Color(.systemGroupedBackground))
    }
    
    private var searchingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.2)
            Text("Searching...")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var noResultsView: some View {
        VStack(spacing: 20) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            
            Text("No items found")
                .font(.title2)
                .fontWeight(.medium)
            
            Text("Try searching with a different SKU or product name")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            
            Button("Report Missing Item") {
                onItemNotFound(searchText.isEmpty ? scannedBarcode ?? "" : searchText)
                isPresented = false
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Image(systemName: "barcode.viewfinder")
                .font(.system(size: 48))
                .foregroundColor(.blue)
            
            Text("Find Items Quickly")
                .font(.title2)
                .fontWeight(.medium)
            
            Text("Search by SKU or product name, or tap the barcode button to scan")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            
            Button("Scan Barcode") {
                showingScanner = true
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var searchResultsList: some View {
        List {
            ForEach(searchResults) { item in
                ItemSearchResultRow(
                    item: item,
                    searchQuery: searchText.isEmpty ? scannedBarcode ?? "" : searchText
                ) {
                    onItemFound(item)
                    isPresented = false
                }
            }
        }
        .listStyle(.insetGrouped)
    }
    
    // MARK: - Helper Views
    
    private func quickActionButton(title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.caption)
                Text(title)
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
    
    // MARK: - Actions
    
    private func handleScannedBarcode(_ barcode: String) {
        showingScanner = false
        scannedBarcode = barcode
        searchText = barcode
        performSearch(query: barcode)
    }
    
    private func performSearch(query: String) {
        guard !query.isEmpty else {
            searchResults = checklistItems
            return
        }
        
        isSearching = true
        
        // Simulate search delay for better UX
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            let lowercaseQuery = query.lowercased()
            
            searchResults = checklistItems.filter { item in
                item.sku.lowercased().contains(lowercaseQuery) ||
                item.name.lowercased().contains(lowercaseQuery) ||
                item.variant_title.lowercased().contains(lowercaseQuery)
            }
            
            isSearching = false
        }
    }
    
    private func filterPendingItems() {
        searchText = ""
        scannedBarcode = nil
        searchResults = checklistItems.filter { !$0.is_completed }
    }
}

// MARK: - Item Search Result Row

struct ItemSearchResultRow: View {
    let item: ChecklistItem
    let searchQuery: String
    let onSelect: () -> Void
    
    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 16) {
                // Item image placeholder
                Image(systemName: item.is_completed ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundColor(item.is_completed ? .green : .secondary)
                    .frame(width: 24, height: 24)
                
                VStack(alignment: .leading, spacing: 4) {
                    // Item name with highlighting
                    Text(highlightedText(item.name, query: searchQuery))
                        .font(.body)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    
                    // SKU with highlighting
                    Text(highlightedText(item.sku, query: searchQuery))
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    // Variant
                    if !item.variant_title.isEmpty {
                        Text(item.variant_title)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 2) {
                    // Quantity info
                    Text("\(item.quantity_picked)/\(item.quantity_required)")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(item.is_completed ? .green : .primary)
                    
                    // Status
                    Text(item.is_completed ? "Complete" : "Pending")
                        .font(.caption)
                        .foregroundColor(item.is_completed ? .green : .orange)
                }
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
    }
    
    private func highlightedText(_ text: String, query: String) -> AttributedString {
        var attributedString = AttributedString(text)
        
        if !query.isEmpty {
            let range = text.lowercased().range(of: query.lowercased())
            if let range = range {
                let nsRange = NSRange(range, in: text)
                if let attributedRange = Range<AttributedString.Index>(nsRange, in: attributedString) {
                    attributedString[attributedRange].backgroundColor = .yellow.opacity(0.3)
                }
            }
        }
        
        return attributedString
    }
}

// MARK: - Preview

#if DEBUG
struct BarcodeSearchView_Previews: PreviewProvider {
    static var previews: some View {
        BarcodeSearchView(
            isPresented: .constant(true),
            checklistItems: [
                ChecklistItem(
                    id: 1,
                    sku: "TS-BLK-L",
                    name: "Classic T-Shirt",
                    variant_title: "Black / Large",
                    quantity_required: 2,
                    image_url: nil,
                    quantity_picked: 0,
                    is_completed: false
                ),
                ChecklistItem(
                    id: 2,
                    sku: "MUG-WHT-01",
                    name: "Company Mug",
                    variant_title: "White",
                    quantity_required: 1,
                    image_url: nil,
                    quantity_picked: 1,
                    is_completed: true
                )
            ],
            onItemFound: { _ in },
            onItemNotFound: { _ in }
        )
    }
}
#endif