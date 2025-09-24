import SwiftUI

/// A simplified view for managing staff members (CRUD operations)
struct StaffManagementView: View {

    // MARK: - Properties

    @EnvironmentObject private var staffManager: StaffManager
    @EnvironmentObject private var syncManager: SyncManager
    @State private var showingAddStaff = false
    @State private var showingEditStaff = false
    @State private var editingStaff: StaffMember?
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var staffToDelete: StaffMember?
    @State private var showingDeleteConfirmation = false

    // MARK: - Body

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {

                // MARK: - Staff List
                if isLoading || staffManager.isLoading {
                    Spacer()
                    ProgressView("Loading staff...")
                        .progressViewStyle(.circular)
                    Spacer()
                } else if staffManager.availableStaff.isEmpty {
                    Spacer()
                    VStack(spacing: 16) {
                        Image(systemName: "person.2.slash")
                            .font(.system(size: 60))
                            .foregroundColor(.secondary)

                        Text("No Staff Members")
                            .font(.title2)
                            .fontWeight(.medium)

                        Text("Add your first staff member to get started")
                            .font(.body)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    Spacer()
                } else {
                    List {
                        ForEach(staffManager.availableStaff, id: \.id) { staff in
                            StaffRow(
                                staff: staff,
                                isEditing: false, // Remove inline editing state
                                onEdit: {
                                    editingStaff = staff
                                    showingEditStaff = true
                                },
                                onDelete: {
                                    staffToDelete = staff
                                    showingDeleteConfirmation = true
                                }
                            )
                        }

                        // Add Staff Button as last list item
                        Button(action: { showingAddStaff = true }) {
                            HStack(spacing: 12) {
                                Image(systemName: "plus.circle.fill")
                                    .font(.title2)
                                    .foregroundColor(.blue)

                                Text("Add Staff Member")
                                    .font(.headline)
                                    .foregroundColor(.blue)

                                Spacer()
                            }
                            .padding(.vertical, 8)
                        }
                        .listRowBackground(Color(.secondarySystemGroupedBackground))
                    }
                }
            }
            .navigationTitle("Staff Management")
            .navigationBarTitleDisplayMode(.automatic)
            .onAppear {
                Task {
                    await staffManager.fetchAvailableStaffIfNeeded()
                }
            }
            .alert("Error", isPresented: .constant(errorMessage != nil)) {
                Button("OK") {
                    errorMessage = nil
                }
            } message: {
                Text(errorMessage ?? "")
            }
        }
        .sheet(isPresented: $showingAddStaff) {
            AddStaffSheet { staffNames in
                Task {
                    // Add all staff members
                    for name in staffNames {
                        let success = await addStaff(name: name)
                        if !success {
                            print("⚠️ Failed to add staff member: \(name)")
                        }
                    }
                    showingAddStaff = false
                }
            }
        }
        .sheet(isPresented: $showingEditStaff) {
            if let staff = editingStaff {
                EditStaffSheet(staff: staff) { updatedName in
                    Task {
                        let success = await updateStaffMember(id: staff.id, name: updatedName)
                        if success {
                            showingEditStaff = false
                            editingStaff = nil
                        }
                    }
                }
            }
        }
        .alert("Delete Staff Member", isPresented: $showingDeleteConfirmation) {
            Button("Cancel", role: .cancel) {
                staffToDelete = nil
            }
            Button("Delete", role: .destructive) {
                if let staff = staffToDelete {
                    deleteStaff(staff)
                }
                staffToDelete = nil
            }
        } message: {
            if let staff = staffToDelete {
                Text("Are you sure you want to delete \"\(staff.name)\"? This action cannot be undone.")
            }
        }
    }

    // MARK: - Private Methods

    private func deleteStaff(_ staff: StaffMember) {
        print("🚨 deleteStaff function called for: \(staff.name) (ID: \(staff.id))")
        Task {
            let success = await deleteStaffMember(id: staff.id)
            if !success {
                print("Failed to delete staff: \(staff.name)")
            } else {
                print("✅ Successfully deleted staff: \(staff.name)")
            }
        }
    }


    // MARK: - Staff API Methods

    private func loadAllStaff() {
        guard !isLoading else { return }

        isLoading = true
        errorMessage = nil

        Task {
            await staffManager.fetchAvailableStaff()
            self.isLoading = false
        }
    }

    private func addStaff(name: String) async -> Bool {
        print("🚀 Starting addStaff for: \(name)")
        isLoading = true
        errorMessage = nil

        do {
            // Suppress all sync operations to prevent sync flood
            syncManager.suppressSyncTemporarily()

            print("📡 Calling APIService.createStaff...")
            let newStaff = try await APIService.shared.createStaff(name: name)
            print("✅ API returned new staff: \(newStaff.name) (ID: \(newStaff.id))")

            print("🔄 Refreshing staff list...")
            // Mark that staff data has changed and refresh
            staffManager.markDataChangesPending()
            await staffManager.fetchAvailableStaff()
            print("✅ Staff list refreshed")

            isLoading = false
            print("✅ Created staff member: \(newStaff.name)")
            return true

        } catch {
            errorMessage = "Failed to create staff member. Please try again."
            print("❌ Error creating staff: \(error)")
            isLoading = false
            return false
        }
    }

    private func updateStaffMember(id: String, name: String) async -> Bool {
        print("🚀 Starting updateStaffMember for ID: \(id), new name: \(name)")
        isLoading = true
        errorMessage = nil

        do {
            // Suppress all sync operations to prevent sync flood
            syncManager.suppressSyncTemporarily()

            print("📡 Calling APIService.updateStaff...")
            let updatedStaff = try await APIService.shared.updateStaff(staffId: id, name: name)
            print("✅ API returned updated staff: \(updatedStaff.name) (ID: \(updatedStaff.id))")

            print("🔄 Refreshing staff list after update...")
            // Mark that staff data has changed and refresh
            staffManager.markDataChangesPending()
            await staffManager.fetchAvailableStaff()
            print("✅ Staff list refreshed after update")

            isLoading = false
            print("✅ Updated staff member: \(updatedStaff.name)")
            return true

        } catch {
            errorMessage = "Failed to update staff member. Please try again."
            print("❌ Error updating staff: \(error)")
            print("❌ Error type: \(type(of: error))")
            if let apiError = error as? APIError {
                print("❌ API Error details: \(apiError)")
            }
            isLoading = false
            return false
        }
    }

    private func deleteStaffMember(id: String) async -> Bool {
        print("🚀 Starting deleteStaffMember for ID: \(id)")
        isLoading = true
        errorMessage = nil

        do {
            // Suppress all sync operations to prevent sync flood
            syncManager.suppressSyncTemporarily()

            print("📡 Calling APIService.deleteStaff...")
            try await APIService.shared.deleteStaff(staffId: id)
            print("✅ API delete call completed successfully")

            print("🔄 Refreshing staff list after deletion...")
            // Mark that staff data has changed and refresh
            staffManager.markDataChangesPending()
            await staffManager.fetchAvailableStaff()
            print("✅ Staff list refreshed after deletion")

            isLoading = false
            print("✅ Deleted staff member with ID: \(id)")
            return true

        } catch {
            errorMessage = "Failed to delete staff member. Please try again."
            print("❌ Error deleting staff: \(error)")
            print("❌ Error type: \(type(of: error))")
            if let apiError = error as? APIError {
                print("❌ API Error details: \(apiError)")
            }
            isLoading = false
            return false
        }
    }
}

// MARK: - Staff Row Component

struct StaffRow: View {
    let staff: StaffMember
    let isEditing: Bool // Keep for compatibility but not used
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack {
            // Staff icon and info
            HStack(spacing: 12) {
                Image(systemName: "person.circle.fill")
                    .font(.title2)
                    .foregroundColor(.blue)

                VStack(alignment: .leading, spacing: 2) {
                    Text(staff.name)
                        .font(.body)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)

                    Text("ID: \(staff.id)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            // Action buttons
            HStack(spacing: 16) {
                Button {
                    print("🔵 Edit button PRESSED for: \(staff.name)")
                    onEdit()
                } label: {
                    Text("Edit")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Color.blue)
                        .cornerRadius(8)
                }
                .buttonStyle(.plain)

                Button {
                    print("🔴 Delete button PRESSED for: \(staff.name)")
                    onDelete()
                } label: {
                    Text("Delete")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Color.red)
                        .cornerRadius(8)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 4)
        .background(Color.clear)
        .cornerRadius(8)
    }
}

// MARK: - Edit Staff Sheet

struct EditStaffSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var staffName: String
    @State private var isUpdating = false
    let staff: StaffMember
    let onUpdate: (String) -> Void

    init(staff: StaffMember, onUpdate: @escaping (String) -> Void) {
        self.staff = staff
        self.onUpdate = onUpdate
        self._staffName = State(initialValue: staff.name)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                // Staff Icon and Current Name
                VStack(spacing: 16) {
                    Image(systemName: "person.circle.fill")
                        .font(.system(size: 80))
                        .foregroundColor(.blue)

                    VStack(spacing: 4) {
                        Text("Editing Staff Member")
                            .font(.headline)
                            .foregroundColor(.secondary)

                        Text("ID: \(staff.id)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                // Edit Field
                VStack(alignment: .leading, spacing: 8) {
                    Text("Staff Name")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)

                    TextField("Enter staff name", text: $staffName)
                        .textFieldStyle(.roundedBorder)
                        .font(.body)
                        .disabled(isUpdating)
                }
                .padding(.horizontal)

                Spacer()
            }
            .padding()
            .navigationTitle("Edit Staff")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .disabled(isUpdating)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        updateStaff()
                    }
                    .disabled(staffName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isUpdating)
                    .fontWeight(.semibold)
                }
            }
        }
    }

    private func updateStaff() {
        let trimmedName = staffName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }

        isUpdating = true
        onUpdate(trimmedName)

        // Brief delay then dismiss (the parent will handle dismissal on success)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            if isUpdating {
                dismiss() // Fallback dismiss if parent doesn't handle it
            }
        }
    }
}

// MARK: - Add Staff Sheet

struct AddStaffSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var staffNames: [String] = [""]
    @State private var isAdding = false
    let onAdd: ([String]) -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                ScrollView {
                    VStack(spacing: 12) {
                        ForEach(staffNames.indices, id: \.self) { index in
                            HStack {
                                TextField("Staff Name \(index + 1)", text: $staffNames[index])
                                    .textFieldStyle(.roundedBorder)
                                    .font(.body)

                                // Remove button (only show if more than 1 field)
                                if staffNames.count > 1 {
                                    Button(action: { removeField(at: index) }) {
                                        Image(systemName: "minus.circle.fill")
                                            .foregroundColor(.red)
                                    }
                                }
                            }
                        }

                        // Add more field button
                        Button(action: addField) {
                            HStack {
                                Image(systemName: "plus.circle.fill")
                                Text("Add More")
                            }
                            .foregroundColor(.blue)
                        }
                        .padding(.top, 8)
                    }
                    .padding()
                }

                Spacer()
            }
            .navigationTitle("Add Staff Members")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Add") {
                        addAllStaff()
                    }
                    .disabled(allFieldsEmpty || isAdding)
                }
            }
        }
    }

    private var allFieldsEmpty: Bool {
        staffNames.allSatisfy { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    private func addField() {
        staffNames.append("")
    }

    private func removeField(at index: Int) {
        staffNames.remove(at: index)
    }

    private func addAllStaff() {
        let validNames = staffNames
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard !validNames.isEmpty else { return }

        isAdding = true
        onAdd(validNames)

        // Brief delay then dismiss
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            dismiss()
        }
    }
}

// NOTE: Inline editing is now used instead of a separate sheet

#if DEBUG
struct StaffManagementView_Previews: PreviewProvider {
    static var previews: some View {
        StaffManagementView()
            .environmentObject(StaffManager())
    }
}
#endif
