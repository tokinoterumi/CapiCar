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

    private init() {
        // Dynamic API URL configuration for different network environments
        self.baseURL = APIService.buildBaseURL()
        print("🌐 APIService initialized with base URL: \(self.baseURL)")
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

        // 2. For iOS Simulator, try localhost first
        #if targetEnvironment(simulator)
        return "http://localhost:3000/api"
        #else
        // 3. For real device, try common local network ranges
        let commonIPs = [
            "192.168.1.1",   // Common router IP
            "192.168.0.1",   // Alternative router IP
            "10.0.0.1"       // Some network setups
        ]

        // In a real app, you'd implement network discovery here
        // For now, fallback to a configurable default
        return "http://192.168.1.143:3000/api"  // Original as fallback
        #endif
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
        
        let (data, _) = try await URLSession.shared.data(from: url)
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
        
        let (data, _) = try await URLSession.shared.data(from: url)
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
        
        let (data, _) = try await URLSession.shared.data(for: request)
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
        
        let (data, _) = try await URLSession.shared.data(for: request)
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
        
        let (data, _) = try await URLSession.shared.data(from: url)
        let response = try jsonDecoder.decode(StaffResponse.self, from: data)

        guard response.success, let staffData = response.data else {
            let errorMessage = response.error ?? "Failed to fetch staff list."
            throw APIError.serverError(message: errorMessage)
        }
        return staffData
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
        
        let (data, _) = try await URLSession.shared.data(for: request)
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

        let (data, _) = try await URLSession.shared.data(for: request)
        let response = try jsonDecoder.decode(IssueReportResponse.self, from: data)

        guard response.success else {
            let errorMessage = response.error ?? "Failed to report issue."
            throw APIError.serverError(message: errorMessage)
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

struct CheckInRequest: Codable {
    let staffId: String
    let action: CheckInAction
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

// MARK: - Enums

enum TaskAction: String, Codable, CaseIterable {
    case startPicking = "START_PICKING"
    case completePicking = "COMPLETE_PICKING"
    case startPacking = "START_PACKING"
    case startInspection = "START_INSPECTION"
    case completeInspection = "COMPLETE_INSPECTION"
    case enterCorrection = "ENTER_CORRECTION"
    case startCorrection = "START_CORRECTION"
    case resolveCorrection = "RESOLVE_CORRECTION"
    case reportException = "REPORT_EXCEPTION"
    case pauseTask = "PAUSE_TASK"
    case resumeTask = "RESUME_TASK"
    case cancelTask = "CANCEL_TASK"
}

enum CheckInAction: String, Codable {
    case checkIn = "CHECK_IN"
    case checkOut = "CHECK_OUT"
}

