import Foundation

@MainActor
@Observable
final class AppOperationState {
    var isLoading = false
    var alertState: AppAlertState?

    @ObservationIgnored var authFailureHandler: (() async -> Void)?
    @ObservationIgnored private var authFailureTask: Task<Void, Never>?

    func withLoading(_ operation: () async throws -> Void) async {
        isLoading = true
        defer { isLoading = false }

        do {
            try await operation()
        } catch {
            handleOperationError(error)
        }
    }

    func withLoadingSilently(_ operation: () async throws -> Void) async {
        isLoading = true
        defer { isLoading = false }

        do {
            try await operation()
        } catch {
            recordSilentOperationError(error)
        }
    }

    func handleOperationError(_ error: Error) {
        if let apiError = error as? APIError {
            BetaDiagnostics.record("api_error", details: apiError.localizedDescription)
            if apiError.isEntitlementLimit {
                alertState = .upgrade(UpgradePrompt(apiError: apiError))
            } else if apiError.requiresSignIn {
                alertState = .auth(Self.expiredSessionMessage)
                notifyAuthFailure()
            } else if apiError.isMissingEndpoint {
                alertState = .backendVersion("This backend does not expose the live Pin API yet. Deploy a compatible API image.")
            } else if apiError.isEmptyWindow {
                alertState = .emptyWindow("No journeys were found in that range. Try a wider departure range.")
            } else {
                alertState = .network(apiError.localizedDescription)
            }
        } else {
            alertState = .network(error.localizedDescription)
            BetaDiagnostics.record("operation_error", details: error.localizedDescription)
        }
    }

    func recordSilentOperationError(_ error: Error) {
        BetaDiagnostics.record("silent_operation_error", details: error.localizedDescription)
    }

    static let expiredSessionMessage = "Your session has expired. Sign in again to continue."

    private func notifyAuthFailure() {
        guard let authFailureHandler, authFailureTask == nil else {
            return
        }
        authFailureTask = Task { @MainActor [weak self] in
            await authFailureHandler()
            self?.authFailureTask = nil
        }
    }
}

enum AppAlertState: Identifiable, Equatable {
    case auth(String)
    case emptyWindow(String)
    case backendVersion(String)
    case limit(String)
    case upgrade(UpgradePrompt)
    case network(String)
    case storage(String)
    case validation(String)

    var id: String { message }

    var title: String {
        switch self {
        case .auth:
            return "Sign In Required"
        case .emptyWindow:
            return "No Journey Found"
        case .backendVersion:
            return "Backend Update Required"
        case .limit:
            return "Beta Limit Reached"
        case .upgrade:
            return "Upgrade to Pro"
        case .network:
            return "Connection Issue"
        case .storage:
            return "Storage Issue"
        case .validation:
            return "Check Details"
        }
    }

    var message: String {
        switch self {
        case .auth(let message), .emptyWindow(let message), .backendVersion(let message), .limit(let message), .network(let message), .storage(let message), .validation(let message):
            return message
        case .upgrade(let prompt):
            return prompt.message
        }
    }
}

struct UpgradePrompt: Identifiable, Equatable {
    var id: String
    var message: String

    init(apiError: APIError) {
        let feature = apiError.details["feature"] ?? ""
        let paidLimit = apiError.details["paidLimit"] ?? ""
        let currentLimit = apiError.details["currentLimit"] ?? ""
        let featureLabel = feature == "commute_routine" ? "saved commutes" : "live Pins"
        if !paidLimit.isEmpty, !currentLimit.isEmpty {
            message = "Your current plan allows \(currentLimit) \(featureLabel). Upgrade to Pro for up to \(paidLimit)."
        } else {
            message = apiError.localizedDescription
        }
        id = "\(feature)-\(currentLimit)-\(paidLimit)-\(message)"
    }
}
