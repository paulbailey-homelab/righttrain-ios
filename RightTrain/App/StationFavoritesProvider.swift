import Foundation

enum StationFavouriteSource: String, Equatable {
    case homeDefault
    case workDefault
    case commuteRoutine
    case explicitFutureFavourite
}

enum StationFavouriteSortGroup: Int, Comparable {
    case defaults = 0
    case routines = 1
    case futureExplicit = 2

    static func < (lhs: StationFavouriteSortGroup, rhs: StationFavouriteSortGroup) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

struct StationFavourite: Identifiable, Equatable {
    var source: StationFavouriteSource
    var crs: String
    var displayLabel: String
    var candidate: StationSuggestion
    var sortGroup: StationFavouriteSortGroup
    var unavailableReason: String? = nil

    var id: String { crs }
}

struct StationFavoritesProvider {
    static func favourites(
        homeStationCRS: String?,
        workStationCRS: String?,
        routines: [CommuteRoutine],
        stationResolver: (String) -> StationSuggestion?
    ) -> [StationFavourite] {
        var favourites: [StationFavourite] = []
        var seenCRS = Set<String>()

        func append(
            crs rawCRS: String?,
            source: StationFavouriteSource,
            label: String,
            group: StationFavouriteSortGroup
        ) {
            guard let crs = normalizedCRS(rawCRS), !seenCRS.contains(crs) else {
                return
            }
            seenCRS.insert(crs)
            let candidate = stationResolver(crs) ?? StationSuggestion(crs: crs, name: crs, tpl: crs, toc: nil)
            favourites.append(StationFavourite(
                source: source,
                crs: crs,
                displayLabel: label,
                candidate: candidate,
                sortGroup: group
            ))
        }

        append(crs: homeStationCRS, source: .homeDefault, label: "Home", group: .defaults)
        append(crs: workStationCRS, source: .workDefault, label: "Work", group: .defaults)

        for routine in routines.sorted(by: { left, right in
            left.name.localizedCaseInsensitiveCompare(right.name) == .orderedAscending
        }) {
            append(crs: routine.originCrs, source: .commuteRoutine, label: routine.name, group: .routines)
            append(crs: routine.destinationCrs, source: .commuteRoutine, label: routine.name, group: .routines)
        }

        return favourites.sorted { left, right in
            if left.sortGroup != right.sortGroup {
                return left.sortGroup < right.sortGroup
            }
            if left.displayLabel != right.displayLabel {
                return left.displayLabel.localizedCaseInsensitiveCompare(right.displayLabel) == .orderedAscending
            }
            return left.crs < right.crs
        }
    }

    private static func normalizedCRS(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        return trimmed.isEmpty ? nil : trimmed
    }
}
