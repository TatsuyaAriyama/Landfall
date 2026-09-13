import Foundation

@main
@MainActor
struct CatalogLogicTests {
    static func main() {
        let suite = "keelmira.catalog.test.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = HomeIslandCatalogPreferences(defaults: defaults)
        assert(preferences.favoriteIDs.isEmpty && preferences.recentIDs.isEmpty)
        preferences.toggleFavorite("desk_pink")
        preferences.toggleFavorite("palm_tree")
        preferences.toggleFavorite("desk_pink")
        preferences.toggleFavorite("")
        assert(preferences.favoriteIDs == ["palm_tree"])
        assert(HomeIslandCatalogPreferences(defaults: defaults).favoriteIDs == ["palm_tree"])
        for index in 0..<30 { preferences.recordPlacement(assetID: "asset_\(index)") }
        assert(preferences.recentIDs.count == 24)
        assert(preferences.recentIDs.first == "asset_29")
        assert(preferences.recentIDs.last == "asset_6")
        preferences.recordPlacement(assetID: "asset_15")
        preferences.recordPlacement(assetID: "")
        assert(preferences.recentIDs.first == "asset_15")
        assert(preferences.recentIDs.filter { $0 == "asset_15" }.count == 1)
        assert(preferences.recentIDs.count == 24)
        assert(HomeIslandCatalogPreferences(defaults: defaults).recentIDs == preferences.recentIDs)
        assert(HomeIslandCatalogSearch.matches(query: "  \n ", names: ["椅子"]))
        assert(HomeIslandCatalogSearch.matches(query: "ｗＨＩＴＥ　desk", names: ["White Desk"]))
        assert(HomeIslandCatalogSearch.matches(query: "ひやしんす", names: ["ヒヤシンス"]))
        assert(HomeIslandCatalogSearch.matches(query: "ﾋﾔｼﾝｽ", names: ["ヒヤシンス"]))
        assert(HomeIslandCatalogSearch.matches(query: "rose pink", names: ["Rose", "Pink"]))
        assert(!HomeIslandCatalogSearch.matches(query: "rose blue", names: ["Rose", "Pink"]))
        assert(!HomeIslandCatalogSearch.matches(query: "desk", names: []))
        print("Catalog persistence, recency bounds/deduplication, and multilingual search: passed")
    }
}
