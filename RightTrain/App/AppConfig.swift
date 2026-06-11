import Foundation

enum AppConfig {
    private static let apiBaseURLInfoKey = "RightTrainAPIBaseURL"
    private static let fallbackAPIBaseURLString = "https://clearsignal-api.lan.dreamshake.net"
    private static let fallbackAPIBaseURL: URL = {
        guard let url = URL(string: fallbackAPIBaseURLString) else {
            preconditionFailure("Invalid fallback RightTrain API base URL: \(fallbackAPIBaseURLString)")
        }
        return url
    }()

    static var apiBaseURL: URL {
        if let rawValue = Bundle.main.object(forInfoDictionaryKey: apiBaseURLInfoKey) as? String {
            let trimmedValue = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmedValue.isEmpty == false,
                  let url = URL(string: trimmedValue) else {
                return fallbackAPIBaseURL
            }
            return url
        }
        return fallbackAPIBaseURL
    }
}
