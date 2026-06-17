import Foundation

extension User {
    var displayNameOrFallback: String {
        guard let name = displayName?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty else {
            return "Account"
        }
        return name
    }

    var maskedEmail: String {
        guard let email = email?.trimmingCharacters(in: .whitespacesAndNewlines), !email.isEmpty else {
            return "Email not shared"
        }

        let parts = email.split(separator: "@", maxSplits: 1).map(String.init)
        guard parts.count == 2 else {
            return email
        }

        let local = parts[0]
        let domain = parts[1]
        guard let first = local.first else {
            return "***@\(domain)"
        }

        if local.count <= 2 {
            return "\(first)***@\(domain)"
        }

        return "\(first)***\(local.last!)@\(domain)"
    }
}

extension String {
    var humanizedIdentifier: String {
        split(separator: "_")
            .map { word in
                let lowercased = word.lowercased()
                return lowercased.prefix(1).uppercased() + String(lowercased.dropFirst())
            }
            .joined(separator: " ")
    }
}
