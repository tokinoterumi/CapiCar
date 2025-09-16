import Foundation
import SwiftData

@MainActor
class DatabaseManager: ObservableObject {
    static let shared = DatabaseManager()
    
    private let modelContainer: ModelContainer
    private let modelContext: ModelContext
    
    init() {
        do {
            let schema = Schema([
                LocalFulfillmentTask.self,
                LocalStaffMember.self,
                LocalChecklistItem.self,
                LocalAuditLog.self,
                LocalSyncState.self
            ])
            
            let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
            self.modelContainer = try ModelContainer(for: schema, configurations: [modelConfiguration])
            self.modelContext = ModelContext(modelContainer)
            
            // Create singleton sync state if it doesn't exist
            createSyncStateIfNeeded()
        } catch {
            fatalError("Failed to initialize database: \(error)")
        }
    }
    
    // MARK: - Task Operations
    
    func saveTasks(_ tasks: [FulfillmentTask]) throws {
        for task in tasks {
            let existingTask = try? fetchLocalTask(id: task.id)
            
            if let existing = existingTask {
                existing.update(from: task)
                existing.lastSyncedAt = Date()
                existing.needsSync = false
            } else {
                let localTask = task.asLocalTask()
                localTask.lastSyncedAt = Date()
                localTask.needsSync = false
                modelContext.insert(localTask)
            }
        }
        
        try modelContext.save()
    }
    
    func fetchAllTasks() throws -> [FulfillmentTask] {
        let descriptor = FetchDescriptor<LocalFulfillmentTask>(
            predicate: #Predicate { !$0.isDeleted },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        
        let localTasks = try modelContext.fetch(descriptor)
        return localTasks.map { $0.asFulfillmentTask }
    }
    
    func fetchTasksByStatus(_ status: TaskStatus) throws -> [FulfillmentTask] {
        let descriptor = FetchDescriptor<LocalFulfillmentTask>(
            predicate: #Predicate { task in
                task.status == status.rawValue && !task.isDeleted
            },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        
        let localTasks = try modelContext.fetch(descriptor)
        return localTasks.map { $0.asFulfillmentTask }
    }
    
    func fetchLocalTask(id: String) throws -> LocalFulfillmentTask? {
        let descriptor = FetchDescriptor<LocalFulfillmentTask>(
            predicate: #Predicate { $0.id == id }
        )
        
        return try modelContext.fetch(descriptor).first
    }
    
    func updateTask(_ task: FulfillmentTask) throws {
        if let localTask = try fetchLocalTask(id: task.id) {
            localTask.update(from: task)
            try modelContext.save()
        } else {
            let localTask = task.asLocalTask()
            localTask.needsSync = true
            modelContext.insert(localTask)
            try modelContext.save()
        }
    }
    
    func markTaskAsDeleted(id: String) throws {
        if let localTask = try fetchLocalTask(id: id) {
            localTask.isDeleted = true
            localTask.needsSync = true
            localTask.localModifiedAt = Date()
            try modelContext.save()
        }
    }
    
    // MARK: - Staff Operations
    
    func saveStaff(_ staff: [StaffMember]) throws {
        for member in staff {
            let existingStaff = try? fetchLocalStaff(id: member.id)
            
            if let existing = existingStaff {
                existing.update(from: member)
                existing.lastSyncedAt = Date()
                existing.needsSync = false
            } else {
                let localStaff = member.asLocalStaff()
                localStaff.lastSyncedAt = Date()
                localStaff.needsSync = false
                modelContext.insert(localStaff)
            }
        }
        
        try modelContext.save()
    }
    
    func fetchAllStaff() throws -> [StaffMember] {
        let descriptor = FetchDescriptor<LocalStaffMember>(
            sortBy: [SortDescriptor(\.name)]
        )
        
        let localStaff = try modelContext.fetch(descriptor)
        return localStaff.map { $0.asStaffMember }
    }
    
    func fetchLocalStaff(id: String) throws -> LocalStaffMember? {
        let descriptor = FetchDescriptor<LocalStaffMember>(
            predicate: #Predicate { $0.id == id }
        )
        
        return try modelContext.fetch(descriptor).first
    }
    
    func updateStaffCheckInStatus(staffId: String, isCheckedIn: Bool) throws {
        if let localStaff = try fetchLocalStaff(id: staffId) {
            localStaff.isCheckedIn = isCheckedIn
            localStaff.checkedInAt = isCheckedIn ? Date() : nil
            localStaff.needsSync = true
            try modelContext.save()
        }
    }
    
    // MARK: - Checklist Operations
    
    func saveChecklistItems(_ items: [ChecklistItem], forTaskId taskId: String) throws {
        // First, remove existing items for this task
        let existingDescriptor = FetchDescriptor<LocalChecklistItem>(
            predicate: #Predicate { $0.taskId == taskId }
        )
        
        let existingItems = try modelContext.fetch(existingDescriptor)
        for item in existingItems {
            modelContext.delete(item)
        }
        
        // Insert new items
        for item in items {
            let localItem = item.asLocalItem(taskId: taskId)
            localItem.lastSyncedAt = Date()
            localItem.needsSync = false
            modelContext.insert(localItem)
        }
        
        try modelContext.save()
    }
    
    func fetchChecklistItems(forTaskId taskId: String) throws -> [ChecklistItem] {
        let descriptor = FetchDescriptor<LocalChecklistItem>(
            predicate: #Predicate { $0.taskId == taskId },
            sortBy: [SortDescriptor(\.itemId)]
        )
        
        let localItems = try modelContext.fetch(descriptor)
        return localItems.map { $0.asChecklistItem }
    }
    
    func updateChecklistItem(_ item: ChecklistItem, forTaskId taskId: String) throws {
        let descriptor = FetchDescriptor<LocalChecklistItem>(
            predicate: #Predicate { checklist in
                checklist.taskId == taskId && checklist.itemId == item.id
            }
        )
        
        if let localItem = try modelContext.fetch(descriptor).first {
            localItem.update(from: item)
            try modelContext.save()
        }
    }
    
    // MARK: - Audit Log Operations
    
    func saveAuditLogs(_ logs: [AuditLog]) throws {
        for log in logs {
            let existingLog = try? fetchLocalAuditLog(id: log.id)
            
            if existingLog == nil {
                let localLog = log.asLocalLog()
                localLog.lastSyncedAt = Date()
                localLog.needsSync = false
                modelContext.insert(localLog)
            }
        }
        
        try modelContext.save()
    }
    
    func fetchLocalAuditLog(id: String) throws -> LocalAuditLog? {
        let descriptor = FetchDescriptor<LocalAuditLog>(
            predicate: #Predicate { $0.id == id }
        )
        
        return try modelContext.fetch(descriptor).first
    }
    
    func addAuditLog(_ log: AuditLog) throws {
        let localLog = log.asLocalLog()
        localLog.needsSync = true
        modelContext.insert(localLog)
        try modelContext.save()
    }
    
    // MARK: - Sync State Operations
    
    private func createSyncStateIfNeeded() {
        do {
            let descriptor = FetchDescriptor<LocalSyncState>()
            let existing = try modelContext.fetch(descriptor)
            
            if existing.isEmpty {
                let syncState = LocalSyncState()
                modelContext.insert(syncState)
                try modelContext.save()
            }
        } catch {
            print("Error creating sync state: \(error)")
        }
    }
    
    func getSyncState() throws -> LocalSyncState {
        let descriptor = FetchDescriptor<LocalSyncState>()
        let states = try modelContext.fetch(descriptor)
        
        if let state = states.first {
            return state
        } else {
            let newState = LocalSyncState()
            modelContext.insert(newState)
            try modelContext.save()
            return newState
        }
    }
    
    func updateSyncState(isOnline: Bool? = nil, lastFullSync: Date? = nil, pendingCount: Int? = nil, errorMessage: String? = nil) throws {
        let syncState = try getSyncState()
        
        if let isOnline = isOnline {
            syncState.isOnline = isOnline
        }
        
        if let lastFullSync = lastFullSync {
            syncState.lastFullSyncAt = lastFullSync
        }
        
        if let pendingCount = pendingCount {
            syncState.pendingActionCount = pendingCount
        }
        
        if let errorMessage = errorMessage {
            syncState.lastErrorMessage = errorMessage
            syncState.lastErrorAt = Date()
        }
        
        try modelContext.save()
    }
    
    // MARK: - Sync Helpers
    
    func getTasksNeedingSync() throws -> [LocalFulfillmentTask] {
        let descriptor = FetchDescriptor<LocalFulfillmentTask>(
            predicate: #Predicate { $0.needsSync }
        )
        
        return try modelContext.fetch(descriptor)
    }
    
    func getStaffNeedingSync() throws -> [LocalStaffMember] {
        let descriptor = FetchDescriptor<LocalStaffMember>(
            predicate: #Predicate { $0.needsSync }
        )
        
        return try modelContext.fetch(descriptor)
    }
    
    func getChecklistItemsNeedingSync() throws -> [LocalChecklistItem] {
        let descriptor = FetchDescriptor<LocalChecklistItem>(
            predicate: #Predicate { $0.needsSync }
        )
        
        return try modelContext.fetch(descriptor)
    }
    
    func getAuditLogsNeedingSync() throws -> [LocalAuditLog] {
        let descriptor = FetchDescriptor<LocalAuditLog>(
            predicate: #Predicate { $0.needsSync }
        )
        
        return try modelContext.fetch(descriptor)
    }
    
    func markTaskAsSynced(_ task: LocalFulfillmentTask) throws {
        task.needsSync = false
        task.lastSyncedAt = Date()
        try modelContext.save()
    }
    
    func markStaffAsSynced(_ staff: LocalStaffMember) throws {
        staff.needsSync = false
        staff.lastSyncedAt = Date()
        try modelContext.save()
    }
    
    func markChecklistItemAsSynced(_ item: LocalChecklistItem) throws {
        item.needsSync = false
        item.lastSyncedAt = Date()
        try modelContext.save()
    }
    
    func markAuditLogAsSynced(_ log: LocalAuditLog) throws {
        log.needsSync = false
        log.lastSyncedAt = Date()
        try modelContext.save()
    }
    
    // MARK: - Utility
    
    func clearAllData() throws {
        try modelContext.delete(model: LocalFulfillmentTask.self)
        try modelContext.delete(model: LocalStaffMember.self)
        try modelContext.delete(model: LocalChecklistItem.self)
        try modelContext.delete(model: LocalAuditLog.self)
        try modelContext.save()
    }
}