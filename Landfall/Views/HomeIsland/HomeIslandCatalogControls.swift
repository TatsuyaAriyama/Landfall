import SwiftUI

struct HomeIslandCatalogSearchField: View {
    @Binding var query: String
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13, weight: .semibold))
                .accessibilityHidden(true)
            TextField("Search item names", text: $query)
                .font(LFFont.copy(13))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .focused($isFocused)
                .onSubmit { isFocused = false }
                .accessibilityLabel(Text("Search item names"))
            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(LFPressableButtonStyle())
                .accessibilityLabel(Text("Clear search"))
            }
        }
        .foregroundStyle(LFHomeFeatureStyle.ink)
        .tint(LFHomeFeatureStyle.ink)
        .padding(.leading, 12)
        .padding(.trailing, query.isEmpty ? 12 : 0)
        .frame(height: 44)
        .background(LFHomeFeatureStyle.field, in: Capsule())
        .overlay(Capsule().stroke(LFHomeFeatureStyle.outline, lineWidth: 1))
        .onAppear { isFocused = true }
    }
}

struct HomeIslandCatalogFavoriteModifier: ViewModifier {
    let assetID: String
    @ObservedObject var preferences: HomeIslandCatalogPreferences

    private var isFavorite: Bool { preferences.favoriteIDs.contains(assetID) }
    private var actionTitle: LocalizedStringKey {
        isFavorite ? "Remove from favorites" : "Add to favorites"
    }

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .topLeading) {
                if isFavorite {
                    Image(systemName: "star.fill")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(LFHomeFeatureStyle.ink)
                        .padding(4)
                        .background(LFHomeFeatureStyle.surface, in: Circle())
                        .padding(3)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
            .contextMenu {
                Button {
                    toggleFavorite()
                } label: {
                    Label(actionTitle, systemImage: isFavorite ? "star.slash" : "star")
                }
            }
            .accessibilityAction(named: Text(actionTitle)) {
                toggleFavorite()
            }
    }

    private func toggleFavorite() {
        preferences.toggleFavorite(assetID)
        Haptics.tap(.light)
    }
}
