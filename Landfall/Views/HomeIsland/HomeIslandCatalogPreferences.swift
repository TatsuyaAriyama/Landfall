import Combine
import Foundation

/// Personal catalogue shortcuts are local to this device, independent of the
/// island slot. A different island should not lose the builder's favourites.
@MainActor
final class HomeIslandCatalogPreferences: ObservableObject {
    @Published private(set) var favoriteIDs: Set<String>
    @Published private(set) var recentIDs: [String]

    private let defaults: UserDefaults
    private static let favoritesKey = "homeIsland.catalog.favorites.v1"
    private static let recentKey = "homeIsland.catalog.recent.v1"
    static let recentLimit = 24

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        favoriteIDs = Set(defaults.stringArray(forKey: Self.favoritesKey) ?? [])
        recentIDs = Self.uniqueRecent(defaults.stringArray(forKey: Self.recentKey) ?? [])
    }

    func toggleFavorite(_ assetID: String) {
        guard !assetID.isEmpty else { return }
        if !favoriteIDs.insert(assetID).inserted {
            favoriteIDs.remove(assetID)
        }
        defaults.set(favoriteIDs.sorted(), forKey: Self.favoritesKey)
    }

    /// Call only after the store has accepted a placement, never when merely
    /// browsing, attempting a locked asset, or moving an existing object.
    func recordPlacement(assetID: String) {
        guard !assetID.isEmpty else { return }
        recentIDs = Self.uniqueRecent([assetID] + recentIDs)
        defaults.set(recentIDs, forKey: Self.recentKey)
    }

    private static func uniqueRecent(_ ids: [String]) -> [String] {
        var seen: Set<String> = []
        return Array(ids.filter { !$0.isEmpty && seen.insert($0).inserted }.prefix(recentLimit))
    }
}

enum HomeIslandCatalogScope: String, CaseIterable, Identifiable {
    case all, favorites, recent

    var id: Self { self }

    var titleKey: String {
        switch self {
        case .all: "All items"
        case .favorites: "Favorites"
        case .recent: "Recently used"
        }
    }

    var symbol: String {
        switch self {
        case .all: "square.grid.2x2"
        case .favorites: "star"
        case .recent: "clock.arrow.circlepath"
        }
    }
}

enum HomeIslandCatalogSearch {
    /// Match every word against names, including Japanese kana variants and
    /// full-width Latin input. Empty or whitespace-only queries show all.
    static func matches(query: String, names: [String]) -> Bool {
        let words = normalized(query).split(whereSeparator: \.isWhitespace)
        let haystack = normalized(names.joined(separator: " "))
        return words.allSatisfy { haystack.contains($0) }
    }

    private static func normalized(_ text: String) -> String {
        let folded = text.folding(
            options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
            locale: Locale(identifier: "en_US_POSIX")
        )
        return folded.applyingTransform(.hiraganaToKatakana, reverse: false) ?? folded
    }
}
