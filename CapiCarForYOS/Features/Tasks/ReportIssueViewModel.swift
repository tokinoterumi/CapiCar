import Foundation

@MainActor
class ReportIssueViewModel: ObservableObject {

    // MARK: - Published Properties

    @Published var selectedIssueType: IssueType?
    @Published var issueDescription: String = ""
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var showingSuccessAlert = false

    // MARK: - Properties

    let task: FulfillmentTask
    let currentOperator: StaffMember?
    private let apiService: APIService

    // MARK: - Computed Properties

    var currentTimestamp: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        formatter.timeZone = TimeZone.current
        return formatter.string(from: Date())
    }

    var canSubmitReport: Bool {
        selectedIssueType != nil && !issueDescription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // MARK: - Initializer

    init(task: FulfillmentTask, currentOperator: StaffMember?, apiService: APIService = APIService.shared) {
        self.task = task
        self.currentOperator = currentOperator
        self.apiService = apiService
    }

    // MARK: - Actions

    func submitIssueReport() async {
        print("🔍 ReportIssueViewModel: submitIssueReport called")

        guard let issueType = selectedIssueType,
              let operatorId = currentOperator?.id else {
            print("🔍 ReportIssueViewModel: Missing required information - issueType: \(selectedIssueType?.rawValue ?? "nil"), operatorId: \(currentOperator?.id ?? "nil")")
            errorMessage = "Missing required information"
            return
        }

        print("🔍 ReportIssueViewModel: Starting API call with issueType: \(issueType.rawValue)")
        isLoading = true
        errorMessage = nil

        do {
            let reportData = IssueReportData(
                taskId: task.id,
                operatorId: operatorId,
                operatorName: currentOperator?.name ?? "Unknown",
                issueType: issueType.rawValue,
                description: issueDescription.trimmingCharacters(in: .whitespacesAndNewlines),
                timestamp: Date().ISO8601Format(),
                taskStatus: task.status.rawValue,
                orderName: task.orderName
            )

            print("🔍 ReportIssueViewModel: Calling API service...")
            try await apiService.reportIssue(reportData: reportData)
            print("🔍 ReportIssueViewModel: API call completed successfully")

            // Show success alert
            showingSuccessAlert = true
            print("🔍 ReportIssueViewModel: Success alert set to true")

            print("✅ Issue reported successfully for task \(task.orderName)")

        } catch {
            print("❌ Failed to report issue: \(error)")
            print("🔍 ReportIssueViewModel: Error details: \(error.localizedDescription)")

            if let apiError = error as? APIError {
                switch apiError {
                case .badURL:
                    errorMessage = "Invalid API URL. Please contact support."
                case .offline:
                    errorMessage = "Issue report saved offline. Will be submitted when connection is restored."
                case .networkError:
                    errorMessage = "Network error. Please check your connection and try again."
                case .serverError(let message):
                    errorMessage = message
                case .invalidResponse:
                    errorMessage = "Invalid response from server. Please try again."
                case .decodingError:
                    errorMessage = "Failed to process response. Please try again."
                case .unknown:
                    errorMessage = "Unknown error occurred. Please try again."
                }
            } else {
                errorMessage = "Failed to submit issue report. Please try again."
            }
        }

        isLoading = false
        print("🔍 ReportIssueViewModel: submitIssueReport completed, isLoading = false")
    }
}

// MARK: - Issue Report Data Model

struct IssueReportData: Codable {
    let taskId: String
    let operatorId: String
    let operatorName: String
    let issueType: String
    let description: String
    let timestamp: String
    let taskStatus: String
    let orderName: String
}