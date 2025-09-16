import Foundation
import Combine

// Custom error type for more specific API failures
enum APIError: Error {
    case badURL
    case serverError(message: String)
    case decodingError(error: Error)
    case unknown
}

class APIService {
    static let shared = APIService()
    
    private let baseURL = "http://192.168.1.143:3000/api"
    
    let jsonDecoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        // This converts snake_case keys from the JSON (e.g., "order_name")
        // to camelCase properties in Swift (e.g., orderName).
        decoder.keyDecodingStrategy = .convertFromSnakeCase
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
        
        guard response.success else {
            throw APIError.serverError(message: "Failed to fetch dashboard data.")
        }
        return response.data
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
        
        guard response.success else {
            throw APIError.serverError(message: "Failed to fetch task \(id).")
        }
        return response.data
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
        
        guard response.success else {
            throw APIError.serverError(message: "Failed to perform action \(action.rawValue).")
        }
        return response.data
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
        
        let requestBody = UpdateChecklistRequest(checklistJson: checklistJson, operatorId: operatorId)
        
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try jsonEncoder.encode(requestBody)
        
        let (data, _) = try await URLSession.shared.data(for: request)
        let response = try jsonDecoder.decode(TaskResponse.self, from: data)
        
        guard response.success else {
            throw APIError.serverError(message: "Failed to update checklist.")
        }
        return response.data
    }
    
    // MARK: - Staff API
    
    func fetchAllStaff() async throws -> [StaffMember] {
        guard let url = URL(string: "\(baseURL)/staff") else {
            throw APIError.badURL
        }
        
        let (data, _) = try await URLSession.shared.data(from: url)
        let response = try jsonDecoder.decode(StaffResponse.self, from: data)
        
        guard response.success else {
            throw APIError.serverError(message: "Failed to fetch staff list.")
        }
        return response.data
    }
    
    func checkInStaff(staffId: String, action: CheckInAction) async throws -> CheckInResult {
        guard let url = URL(string: "\(baseURL)/staff/checkin") else {
            throw APIError.badURL
        }
        
        let requestBody = CheckInRequest(staffId: staffId, action: action)
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try jsonEncoder.encode(requestBody)
        
        let (data, _) = try await URLSession.shared.data(for: request)
        let response = try jsonDecoder.decode(CheckInResponse.self, from: data)
        
        guard response.success else {
            throw APIError.serverError(message: "Check-in action failed.")
        }
        return response.data
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
    let data: DashboardData
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
    let data: FulfillmentTask
}

struct StaffResponse: Codable {
    let success: Bool
    let data: [StaffMember]
}

struct CheckInResponse: Codable {
    let success: Bool
    let data: CheckInResult
}

struct CheckInResult: Codable {
    let staff: StaffMember
    let action: String
    let timestamp: String
    let message: String
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
    case cancelTask = "CANCEL_TASK"
}

enum CheckInAction: String, Codable {
    case checkIn = "CHECK_IN"
    case checkOut = "CHECK_OUT"
}

