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

    private static let fallbackBundleIdentifier = "com.righttrain.ios"

    /// The private CloudKit container, derived from the bundle identifier so a
    /// beta bundle built with a different `RIGHTTRAIN_BUNDLE_IDENTIFIER` gets
    /// its own container rather than sharing the release one. This must match
    /// the identifier in RightTrain.entitlements.
    static var cloudKitContainerIdentifier: String {
        "iCloud." + (Bundle.main.bundleIdentifier ?? fallbackBundleIdentifier)
    }

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
