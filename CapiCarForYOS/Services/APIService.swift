import Foundation
import Combine

// Custom error type for more specific API failures
enum APIError: Error {
    case badURL
    case offline
    case networkError
    case serverError(message: String)
    case invalidResponse
    case decodingError(error: Error)
    case unknown
}

class APIService {
    static let shared = APIService()

    private let baseURL: String
    private let urlSession: URLSession

    private init() {
        // Dynamic API URL configuration for different network environments
        self.baseURL = APIService.buildBaseURL()

        // Create custom URLSession with shorter timeouts for faster offline detection
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 8.0  // 8 seconds per request
        config.timeoutIntervalForResource = 15.0 // 15 seconds total
        config.waitsForConnectivity = false // Don't wait for connectivity
        self.urlSession = URLSession(configuration: config)

        print("🌐 APIService initialized with base URL: \(self.baseURL)")
        print("⚡ APIService configured with fast timeouts (request: 8s, resource: 15s)")
    }

    /// Update API base URL at runtime (useful for network changes)
    func updateBaseURL(_ newURL: String) {
        UserDefaults.standard.set(newURL, forKey: "api_base_url")
        print("🔄 API base URL updated to: \(newURL)")
        print("ℹ️  Restart app to apply changes")
    }

    /// Get current base URL
    var currentBaseURL: String {
        return baseURL
    }

    private static func buildBaseURL() -> String {
        // Priority order:
        // 1. Check for manual override in app settings
        // 2. Try localhost for simulator
        // 3. Auto-discover on local network

        // 1. Manual override (you can set this in iOS Settings app)
        if let manualURL = UserDefaults.standard.string(forKey: "api_base_url"), !manualURL.isEmpty {
            return manualURL
        }

        // 2. Default to production server on Render
        return "https://capicar-server.onrender.com/api"
    }
    
    let jsonDecoder: JSONDecoder = {
        let decoder = JSONDecoder()

        // Use ISO8601DateFormatter with fractional seconds support
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let dateString = try container.decode(String.self)

            if let date = formatter.date(from: dateString) {
                return date
            }

            // Fallback for dates without fractional seconds
            let fallbackFormatter = ISO8601DateFormatter()
            fallbackFormatter.formatOptions = [.withInternetDateTime]
            if let date = fallbackFormatter.date(from: dateString) {
                return date
            }

            throw DecodingError.dataCorruptedError(in: container,
                debugDescription: "Unable to parse date: \(dateString)")
        }

        return decoder
    }()
    
    // A single, reusable JSONEncoder
    private let jsonEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.keyEncodingStrategy = .convertToSnakeCase
        return encoder
    }()

    
    // MARK: - Dashboard API
    
    func fetchDashboardData() async throws -> DashboardData {
        guard let url = URL(string: "\(baseURL)/dashboard") else {
            throw APIError.badURL
        }
        
        let (data, _) = try await urlSession.data(from: url)
        let response = try jsonDecoder.decode(DashboardResponse.self, from: data)

        guard response.success, let dashboardData = response.data else {
            let errorMessage = response.error ?? "Failed to fetch dashboard data."
            throw APIError.serverError(message: errorMessage)
        }
        return dashboardData
    }
    
    func fetchDashboardTasks() async throws -> GroupedTasks {
        // Use the main dashboard data method and extract just the tasks
        let dashboardData = try await fetchDashboardData()
        return dashboardData.tasks
    }
    
    // MARK: - Task API
    
    func fetchTask(id: String) async throws -> FulfillmentTask {
        guard let url = URL(string: "\(baseURL)/tasks/\(id)") else {
            throw APIError.badURL
        }
        
        let (data, _) = try await urlSession.data(from: url)
        let response = try jsonDecoder.decode(TaskResponse.self, from: data)

        guard response.success, let taskData = response.data else {
            let errorMessage = response.error ?? "Failed to fetch task \(id)."
            throw APIError.serverError(message: errorMessage)
        }
        return taskData
    }
    
    func performTaskAction(
        taskId: String,
        action: TaskAction,
        operatorId: String,
        payload: [String: String]? = nil
    ) async throws -> FulfillmentTask {
        guard let url = URL(string: "\(baseURL)/tasks/action") else {
            throw APIError.badURL
        }
        
        let requestBody = TaskActionRequest(
            taskId: taskId,
            action: action,
            operatorId: operatorId,
            payload: payload
        )
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try jsonEncoder.encode(requestBody)
        
        let (data, _) = try await urlSession.data(for: request)
        let response = try jsonDecoder.decode(TaskResponse.self, from: data)

        guard response.success, let taskData = response.data else {
            let errorMessage = response.error ?? "Failed to perform action \(action.rawValue)."
            throw APIError.serverError(message: errorMessage)
        }
        return taskData
    }
    
    func updateTaskChecklist(
        taskId: String,
        checklist: [ChecklistItem],
        operatorId: String
    ) async throws -> FulfillmentTask {
        guard let url = URL(string: "\(baseURL)/tasks/\(taskId)/checklist") else {
            throw APIError.badURL
        }
        
        // Serialize checklist to JSON string as backend expects
        let checklistData = try jsonEncoder.encode(checklist)
        guard let checklistJson = String(data: checklistData, encoding: .utf8) else {
            throw APIError.unknown
        }

        print("DEBUG: Sending checklist update - checklistJson length: \(checklistJson.count)")
        print("DEBUG: checklistJson preview: \(String(checklistJson.prefix(200)))...")

        let requestBody = UpdateChecklistRequest(checklistJson: checklistJson, operatorId: operatorId)

        print("DEBUG: Request body - operatorId: \(operatorId)")
        
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try jsonEncoder.encode(requestBody)
        
        let (data, _) = try await urlSession.data(for: request)
        let response = try jsonDecoder.decode(TaskResponse.self, from: data)

        guard response.success, let taskData = response.data else {
            let errorMessage = response.error ?? "Failed to update checklist."
            throw APIError.serverError(message: errorMessage)
        }
        return taskData
    }
    
    // MARK: - Staff API
    
    func fetchAllStaff() async throws -> [StaffMember] {
        guard let url = URL(string: "\(baseURL)/staff") else {
            throw APIError.badURL
        }
        
        let (data, _) = try await urlSession.data(from: url)
        let response = try jsonDecoder.decode(StaffResponse.self, from: data)

        guard response.success, let staffData = response.data else {
            let errorMessage = response.error ?? "Failed to fetch staff list."
            throw APIError.serverError(message: errorMessage)
        }
        return staffData
    }
    
    func createStaff(name: String, staffId: String? = nil) async throws -> StaffMember {
        guard let url = URL(string: "\(baseURL)/staff") else {
            throw APIError.badURL
        }

        let requestBody = CreateStaffRequest(name: name, staffId: staffId)

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try jsonEncoder.encode(requestBody)

        let (data, _) = try await urlSession.data(for: request)
        let response = try jsonDecoder.decode(SingleStaffResponse.self, from: data)

        guard response.success, let newStaff = response.data else {
            let errorMessage = response.error ?? "Failed to create staff member."
            throw APIError.serverError(message: errorMessage)
        }
        return newStaff
    }

    func updateStaff(staffId: String, name: String) async throws -> StaffMember {
        guard let url = URL(string: "\(baseURL)/staff/\(staffId)") else {
            throw APIError.badURL
        }

        let requestBody = UpdateStaffRequest(name: name)

        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try jsonEncoder.encode(requestBody)

        let (data, _) = try await urlSession.data(for: request)
        let response = try jsonDecoder.decode(SingleStaffResponse.self, from: data)

        guard response.success, let staffData = response.data else {
            let errorMessage = response.error ?? "Failed to update staff member."
            throw APIError.serverError(message: errorMessage)
        }
        return staffData
    }

    func deleteStaff(staffId: String) async throws {
        guard let url = URL(string: "\(baseURL)/staff/\(staffId)") else {
            throw APIError.badURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"

        let (data, _) = try await urlSession.data(for: request)
        let response = try jsonDecoder.decode(DeleteStaffResponse.self, from: data)

        guard response.success else {
            let errorMessage = response.error ?? "Failed to delete staff member."
            throw APIError.serverError(message: errorMessage)
        }
    }

    func checkInStaff(staffId: String, action: CheckInAction) async throws -> CheckInResult {
        guard let url = URL(string: "\(baseURL)/staff/checkin") else {
            throw APIError.badURL
        }
        
        let requestBody = CheckInRequest(staffId: staffId, action: action)

        // Debug: Print what we're sending
        print("🔍 Check-in request - staffId: \(staffId), action: \(action.rawValue)")

        // Use a special encoder for check-in that doesn't convert to snake_case
        let checkInEncoder = JSONEncoder()
        checkInEncoder.dateEncodingStrategy = .iso8601
        // No key conversion strategy - keep camelCase

        let jsonData = try checkInEncoder.encode(requestBody)
        if let jsonString = String(data: jsonData, encoding: .utf8) {
            print("🔍 Check-in JSON payload: \(jsonString)")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = jsonData
        
        let (data, _) = try await urlSession.data(for: request)
        let response = try jsonDecoder.decode(CheckInResponse.self, from: data)

        guard response.success, let resultData = response.data else {
            let errorMessage = response.error ?? "Check-in action failed."
            throw APIError.serverError(message: errorMessage)
        }
        return resultData
    }

    // MARK: - Issue Reporting API

    func reportIssue(reportData: IssueReportData) async throws {
        guard let url = URL(string: "\(baseURL)/issues/report") else {
            throw APIError.badURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try jsonEncoder.encode(reportData)

        let (data, _) = try await urlSession.data(for: request)
        let response = try jsonDecoder.decode(IssueReportResponse.self, from: data)

        guard response.success else {
            let errorMessage = response.error ?? "Failed to report issue."
            throw APIError.serverError(message: errorMessage)
        }
    }

    func fetchTaskWorkHistory(taskId: String) async throws -> [WorkHistoryEntry] {
        guard let url = URL(string: "\(baseURL)/tasks/\(taskId)/history") else {
            throw APIError.badURL
        }

        let (data, _) = try await urlSession.data(from: url)
        let response = try jsonDecoder.decode(WorkHistoryResponse.self, from: data)

        guard response.success else {
            throw APIError.serverError(message: "Failed to fetch work history")
        }

        return response.data
    }

    // MARK: - Audit Log Sync API

    /// Sync audit logs to server
    func syncAuditLog(_ auditLogs: [LocalAuditLog]) async throws -> AuditLogSyncResponse {
        guard let url = URL(string: "\(baseURL)/audit-logs/sync") else {
            throw APIError.badURL
        }

        // Convert LocalAuditLog objects to the format expected by the server
        let logPayloads = auditLogs.map { log in
            let effectiveStaffId = log.staffId.isEmpty ? "unknown" : log.staffId
            if log.staffId.isEmpty {
                print("⚠️ AUDIT LOG: Using placeholder 'unknown' for missing staffId in log \(log.id)")
            }
            print("🔍 DEBUG AUDIT LOG: id=\(log.id), timestamp=\(log.timestamp), actionType='\(log.actionType)', staffId='\(effectiveStaffId)', taskId='\(log.taskId)'")
            return AuditLogPayload(
                timestamp: log.timestamp.toISOString(),
                actionType: log.actionType,
                staffId: effectiveStaffId,
                taskId: log.taskId,
                operationSequence: log.operationSequence,
                oldValue: log.oldValue,
                newValue: log.newValue,
                details: log.details,
                deletionFlag: log.deletionFlag
            )
        }

        let requestBody = AuditLogSyncRequest(logs: logPayloads)

        let jsonData = try jsonEncoder.encode(requestBody)

        // Debug: Print the JSON payload being sent
        if let jsonString = String(data: jsonData, encoding: .utf8) {
            print("🔍 DEBUG JSON PAYLOAD: \(jsonString)")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = jsonData

        let (data, response) = try await urlSession.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            if let errorData = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let errorMessage = errorData["error"] as? String {
                throw APIError.serverError(message: errorMessage)
            }
            throw APIError.serverError(message: "HTTP \(httpResponse.statusCode)")
        }

        do {
            let auditSyncResponse = try jsonDecoder.decode(AuditLogSyncResponse.self, from: data)
            print("📝 AUDIT LOG SYNC: Synced \(auditSyncResponse.syncedCount)/\(auditLogs.count) entries")
            return auditSyncResponse
        } catch {
            throw APIError.decodingError(error: error)
        }
    }
}

// MARK: - API Request & Response Models

// REQUEST Models (for POST/PUT bodies)
struct TaskActionRequest: Codable {
    let taskId: String
    let action: TaskAction
    let operatorId: String
    let payload: [String: String]?
}

struct UpdateChecklistRequest: Codable {
    let checklistJson: String
    let operatorId: String
}

struct CreateStaffRequest: Codable {
    let name: String
    let staffId: String?
}

struct UpdateStaffRequest: Codable {
    let name: String
}

struct CheckInRequest: Codable {
    let staffId: String
    let action: CheckInAction
}

struct AuditLogSyncRequest: Codable {
    let logs: [AuditLogPayload]
}

struct AuditLogPayload: Codable {
    let timestamp: String
    let actionType: String
    let staffId: String
    let taskId: String
    let operationSequence: Int
    let oldValue: String?
    let newValue: String?
    let details: String
    let deletionFlag: Bool

    private enum CodingKeys: String, CodingKey {
        case timestamp
        case actionType = "action_type"
        case staffId = "staff_id"
        case taskId = "task_id"
        case operationSequence = "operation_sequence"
        case oldValue = "old_value"
        case newValue = "new_value"
        case details
        case deletionFlag = "deletion_flag"
    }
}


// RESPONSE Models (for decoding server responses)
struct DashboardResponse: Codable {
    let success: Bool
    let data: DashboardData?
    let error: String?
}

struct DashboardData: Codable {
    let tasks: GroupedTasks
    let stats: DashboardStats
    let lastUpdated: String
}

struct DashboardStats: Codable {
    let pending: Int        // pending tasks
    let picking: Int        // picking + picked tasks
    let packed: Int         // packed tasks
    let inspecting: Int     // inspecting + correctionNeeded + correcting tasks
    let completed: Int      // completed tasks
    let paused: Int         // paused tasks
    let cancelled: Int      // cancelled tasks
    let total: Int          // total tasks across all statuses
}

struct TaskResponse: Codable {
    let success: Bool
    let data: FulfillmentTask?
    let error: String?
}

struct StaffResponse: Codable {
    let success: Bool
    let data: [StaffMember]?
    let error: String?
}

struct SingleStaffResponse: Codable {
    let success: Bool
    let data: StaffMember?
    let error: String?
}

struct DeleteStaffResponse: Codable {
    let success: Bool
    let message: String?
    let error: String?
}

struct CheckInResponse: Codable {
    let success: Bool
    let data: CheckInResult?
    let error: String?
}

struct CheckInResult: Codable {
    let staff: StaffMember
    let action: String
    let timestamp: String
    let message: String
}

struct IssueReportResponse: Codable {
    let success: Bool
    let error: String?
}

struct WorkHistoryResponse: Codable {
    let success: Bool
    let data: [WorkHistoryEntry]
}

struct AuditLogSyncResponse: Codable {
    let success: Bool
    let syncedCount: Int
    let errors: [AuditLogSyncError]

    private enum CodingKeys: String, CodingKey {
        case success
        case syncedCount = "synced_count"
        case errors
    }
}

struct AuditLogSyncError: Codable {
    let log: [String: AnyCodable]?
    let error: String

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.error = try container.decode(String.self, forKey: .error)
        self.log = try? container.decode([String: AnyCodable].self, forKey: .log)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(error, forKey: .error)
        try container.encodeIfPresent(log, forKey: .log)
    }

    private enum CodingKeys: String, CodingKey {
        case log, error
    }
}

// Helper type for decoding arbitrary JSON values
struct AnyCodable: Codable {
    let value: Any

    init(_ value: Any) {
        self.value = value
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if let intValue = try? container.decode(Int.self) {
            value = intValue
        } else if let stringValue = try? container.decode(String.self) {
            value = stringValue
        } else if let boolValue = try? container.decode(Bool.self) {
            value = boolValue
        } else if let doubleValue = try? container.decode(Double.self) {
            value = doubleValue
        } else {
            value = NSNull()
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()

        if let intValue = value as? Int {
            try container.encode(intValue)
        } else if let stringValue = value as? String {
            try container.encode(stringValue)
        } else if let boolValue = value as? Bool {
            try container.encode(boolValue)
        } else if let doubleValue = value as? Double {
            try container.encode(doubleValue)
        } else {
            try container.encodeNil()
        }
    }
}

// MARK: - Enums

enum TaskAction: String, Codable, CaseIterable {
    case startPicking = "START_PICKING"
    case startPacking = "START_PACKING"
    case startInspection = "START_INSPECTION"
    case completeInspection = "COMPLETE_INSPECTION"
    case enterCorrection = "ENTER_CORRECTION"
    case startCorrection = "START_CORRECTION"
    case resolveCorrection = "RESOLVE_CORRECTION"
    case labelCreated = "LABEL_CREATED"
    case reportException = "REPORT_EXCEPTION"
    case pauseTask = "PAUSE_TASK"
    case resumeTask = "RESUME_TASK"
    case cancelTask = "CANCEL_TASK"
}

enum CheckInAction: String, Codable {
    case checkIn = "CHECK_IN"
    case checkOut = "CHECK_OUT"
}

// MARK: - Extensions

extension Date {
    /// Convert Date to ISO8601 string format
    func toISOString() -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: self)
    }
}

