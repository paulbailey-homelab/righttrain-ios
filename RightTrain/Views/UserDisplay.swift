import Foundation

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
