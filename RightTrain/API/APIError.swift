import Foundation

enum APIError: LocalizedError, Equatable {
    case invalidURL
    case transport(String)
    case decoding(DecodingError)
    case server(statusCode: Int, code: String?, message: String, details: [String: String])

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "RightTrain is not configured with a valid API URL."
        case .transport:
            return "We could not reach RightTrain. Check your connection and try again."
        case .decoding:
            return "RightTrain returned a response this app could not read."
        case .server(_, let code, let message, _):
            if code == "entitlement_active_window_limit_exceeded" {
                return "Your beta account already has a live Pin. Unpin it before creating another."
            } else if code == "commute_routine_limit_exceeded" {
                return "Your current plan has reached its saved commute limit."
            }
            return message
        }
    }

    var details: [String: String] {
        if case .server(_, _, _, let details) = self {
            return details
        }
        return [:]
    }

    var statusCode: Int? {
        if case .server(let statusCode, _, _, _) = self {
            return statusCode
        }
        return nil
    }

    var isEntitlementLimit: Bool {
        if case .server(let statusCode, let code, _, _) = self {
            return statusCode == 403 ||
                code == "entitlement_active_window_limit_exceeded" ||
                code == "commute_routine_limit_exceeded"
        }
        return false
    }

    var isEmptyWindow: Bool {
        if case .server(let statusCode, _, _, _) = self {
            return statusCode == 404
        }
        return false
    }

    var isNotFound: Bool {
        if case .server(let statusCode, _, _, _) = self {
            return statusCode == 404
        }
        return false
    }

    var isMissingEndpoint: Bool {
        if case .server(let statusCode, _, let message, _) = self {
            return statusCode == 404 && message.localizedCaseInsensitiveContains("404 page not found")
        }
        return false
    }

    var isAuthFailure: Bool {
        if case .server(let statusCode, _, _, _) = self {
            return statusCode == 401 || statusCode == 403
        }
        return false
    }

    var requiresSignIn: Bool {
        if case .server(let statusCode, _, _, _) = self {
            return statusCode == 401
        }
        return false
    }

    var isConflict: Bool {
        statusCode == 409
    }

    var isClientFailure: Bool {
        guard let statusCode else { return false }
        return (400..<500).contains(statusCode)
    }

    static func == (lhs: APIError, rhs: APIError) -> Bool {
        lhs.errorDescription == rhs.errorDescription
    }

    static func from(statusCode: Int, data: Data) -> APIError {
        let fallback = HTTPURLResponse.localizedString(forStatusCode: statusCode)
        guard !data.isEmpty else {
            return .server(statusCode: statusCode, code: nil, message: fallback, details: [:])
        }

        if let payload = try? JSONDecoder().decode(ErrorResponse.self, from: data) {
            return .server(
                statusCode: statusCode,
                code: payload.code,
                message: payload.error,
                details: payload.stringDetails
            )
        }

        let text = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        return .server(statusCode: statusCode, code: nil, message: text?.isEmpty == false ? text! : fallback, details: [:])
    }
}
