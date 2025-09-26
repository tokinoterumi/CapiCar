import Foundation

/// Manages operation-level offline-first sessions to ensure consistency during network transitions
/// Once an operation starts offline, it remains offline until completion at a stable checkpoint
@MainActor
class TaskOperationSession: ObservableObject {

    // MARK: - Published Properties

    @Published private(set) var activeSessions: [String: OperationSession] = [:]

    // MARK: - Private Properties

    private let syncManager: SyncManager

    // MARK: - Session Data

    struct OperationSession {
        let taskId: String
        let isOfflineSession: Bool
        let startTime: Date
        let initialStatus: TaskStatus

        init(taskId: String, isOffline: Bool, initialStatus: TaskStatus) {
            self.taskId = taskId
            self.isOfflineSession = isOffline
            self.startTime = Date()
            self.initialStatus = initialStatus
        }
    }

    // MARK: - Initialization

    init(syncManager: SyncManager = SyncManager.shared) {
        self.syncManager = syncManager
    }

    // MARK: - Session Management

    /// Start an operation session for a task
    /// Once started, the task will use offline mode until reaching a stable checkpoint
    func startOperationSession(for taskId: String, currentStatus: TaskStatus) {
        let isCurrentlyOffline = !syncManager.isOnline
        let session = OperationSession(
            taskId: taskId,
            isOffline: isCurrentlyOffline,
            initialStatus: currentStatus
        )

        activeSessions[taskId] = session

        print("🔒 OPERATION SESSION: Started for task \(taskId)")
        print("🔒 SESSION INFO: offline=\(isCurrentlyOffline), initialStatus=\(currentStatus)")
    }

    /// Check if a task should use offline mode (either truly offline or in an offline session)
    func shouldUseOfflineMode(for taskId: String) -> Bool {
        // Always respect true offline state
        if !syncManager.isOnline {
            return true
        }

        // Check if task has an active offline session
        if let session = activeSessions[taskId] {
            print("🔒 OPERATION SESSION: Task \(taskId) in offline session, forcing offline mode")
            return session.isOfflineSession
        }

        return false
    }

    /// Complete an operation session when reaching a stable checkpoint
    func completeOperationSession(for taskId: String, finalStatus: TaskStatus) {
        guard let session = activeSessions[taskId] else {
            print("⚠️ OPERATION SESSION: No active session found for task \(taskId)")
            return
        }

        // Remove the session
        activeSessions.removeValue(forKey: taskId)

        print("✅ OPERATION SESSION: Completed for task \(taskId)")
        print("✅ SESSION SUMMARY: \(session.initialStatus) → \(finalStatus), duration: \(Date().timeIntervalSince(session.startTime))s")

        // Trigger sync if we were in an offline session but are now online
        if session.isOfflineSession && syncManager.isOnline {
            print("🔄 OPERATION SESSION: Session completed, triggering sync for offline changes")
            Task {
                await syncManager.triggerSync()
            }
        }
    }

    /// Force complete all sessions (for debugging or reset scenarios)
    func completeAllSessions() {
        let sessionCount = activeSessions.count
        activeSessions.removeAll()
        print("🧹 OPERATION SESSION: Force completed \(sessionCount) sessions")
    }

    /// Check if a task has an active operation session
    func hasActiveSession(for taskId: String) -> Bool {
        return activeSessions[taskId] != nil
    }

    /// Get session info for debugging
    func getSessionInfo(for taskId: String) -> OperationSession? {
        return activeSessions[taskId]
    }

    // MARK: - Stable Checkpoint Detection

    /// Determine if a status represents a stable checkpoint where sync is safe
    private func isStableCheckpoint(_ status: TaskStatus) -> Bool {
        switch status {
        case .pending, .packed, .completed, .cancelled:
            return true
        case .picking, .inspecting, .correcting, .correctionNeeded:
            return false
        }
    }

    /// Check if transitioning to a new status should complete the session
    func shouldCompleteSession(for taskId: String, newStatus: TaskStatus) -> Bool {
        guard let session = activeSessions[taskId] else { return false }

        // Complete session when reaching a stable checkpoint
        if isStableCheckpoint(newStatus) {
            return true
        }

        return false
    }
}

// MARK: - Singleton Access

extension TaskOperationSession {
    static let shared = TaskOperationSession()
}