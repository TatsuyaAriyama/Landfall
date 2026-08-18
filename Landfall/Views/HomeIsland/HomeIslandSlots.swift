import Foundation
import SwiftUI

/// Which island a player is building on.
///
/// A free sailor keeps one island. The Voyage Pass opens a second, so the two
/// can be laid out for different moods without one overwriting the other.
struct HomeIslandSlot: Identifiable, Hashable {
    /// 1-based, and stable forever: it is part of the storage identity.
    let index: Int

    var id: Int { index }

    /// Everything past the first island is part of the pass.
    var requiresPass: Bool { index > 1 }

    /// The per-slot owner identity. The first island keeps the bare owner id,
    /// so islands built before slots existed keep loading from exactly the
    /// path they were written to.
    func ownerID(base: String) -> String {
        index == 1 ? base : "\(base)#slot\(index)"
    }
}

/// What the island-select screen needs to draw a slot without loading it.
struct HomeIslandSlotSummary: Identifiable {
    let slot: HomeIslandSlot
    /// nil when the island has never been saved.
    let updatedAt: Date?
    let placementCount: Int

    var id: Int { slot.index }
    var isEmpty: Bool { updatedAt == nil }
}

/// The player's islands, and which one is live.
///
/// Losing an island is unforgivable, so this type never deletes or rewrites a
/// slot's file: it only decides which owner identity the editor opens. A
/// lapsed pass therefore hides the second island rather than destroying it.
@MainActor
final class HomeIslandSlotBook: ObservableObject {
    static let maximumSlots = 2
    static let slots = (1...maximumSlots).map(HomeIslandSlot.init(index:))
    /// Posted with the base owner id when the live island changes, so the
    /// screen showing the island and the screen switching it agree without one
    /// having to own the other.
    static let didChange = Notification.Name("HomeIslandSlotDidChange")

    @Published private(set) var activeIndex: Int
    @Published private(set) var summaries: [HomeIslandSlotSummary] = []

    private(set) var baseOwnerID: String
    private let defaults: UserDefaults
    private var observer: NSObjectProtocol?

    init(baseOwnerID: String, defaults: UserDefaults = .standard) {
        self.baseOwnerID = baseOwnerID
        self.defaults = defaults
        activeIndex = Self.storedIndex(baseOwnerID: baseOwnerID, defaults: defaults)
        refresh()
        observer = NotificationCenter.default.addObserver(
            forName: Self.didChange,
            object: nil,
            queue: .main
        ) { [weak self] note in
            MainActor.assumeIsolated {
                guard let self, note.object as? String == self.baseOwnerID else { return }
                self.reload()
            }
        }
    }

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }

    /// The signed-in account changed. The book follows rather than being
    /// rebuilt, so nothing holding it has to be torn down.
    func rebase(to baseOwnerID: String) {
        guard baseOwnerID != self.baseOwnerID else { return }
        self.baseOwnerID = baseOwnerID
        reload()
    }

    private func reload() {
        activeIndex = Self.storedIndex(baseOwnerID: baseOwnerID, defaults: defaults)
        refresh()
    }

    private static func storedIndex(baseOwnerID: String, defaults: UserDefaults) -> Int {
        let stored = defaults.integer(forKey: activeSlotKey(baseOwnerID: baseOwnerID))
        return (1...maximumSlots).contains(stored) ? stored : 1
    }

    /// The owner identity the editor should open. A slot the player is no
    /// longer entitled to falls back to the first island; its own data stays
    /// on disk untouched.
    var activeOwnerID: String {
        slot(at: effectiveIndex).ownerID(base: baseOwnerID)
    }

    var effectiveIndex: Int {
        isUnlocked(index: activeIndex) ? activeIndex : 1
    }

    func slot(at index: Int) -> HomeIslandSlot {
        Self.slots.first { $0.index == index } ?? Self.slots[0]
    }

    func isUnlocked(index: Int) -> Bool {
        guard slot(at: index).requiresPass else { return true }
        return VoyagePassStore.shared.isActive
    }

    func summary(at index: Int) -> HomeIslandSlotSummary? {
        summaries.first { $0.slot.index == index }
    }

    /// The island's given name, or its number when the player has not named it.
    func name(at index: Int) -> String {
        let stored = defaults.string(forKey: Self.nameKey(baseOwnerID: baseOwnerID, index: index))
        let trimmed = stored?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? LF.format("Island %lld", Int64(index)) : trimmed
    }

    /// True when the name is the player's own rather than the fallback.
    func hasCustomName(at index: Int) -> Bool {
        let stored = defaults.string(forKey: Self.nameKey(baseOwnerID: baseOwnerID, index: index))
        return !(stored?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "").isEmpty
    }

    /// An empty name clears back to the numbered fallback rather than leaving
    /// an island with no name at all.
    func rename(index: Int, to name: String) {
        let key = Self.nameKey(baseOwnerID: baseOwnerID, index: index)
        let trimmed = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(16))
        if trimmed.isEmpty {
            defaults.removeObject(forKey: key)
        } else {
            defaults.set(trimmed, forKey: key)
        }
        objectWillChange.send()
        NotificationCenter.default.post(name: Self.didChange, object: baseOwnerID)
    }

    static func nameKey(baseOwnerID: String, index: Int) -> String {
        "homeIsland.name.\(HomeIslandPersistence.ownerKey(for: baseOwnerID)).\(index)"
    }

    /// Switches islands. Refuses a locked slot rather than silently opening
    /// the wrong one, so the caller can offer the pass instead.
    @discardableResult
    func activate(_ index: Int) -> Bool {
        guard (1...Self.maximumSlots).contains(index), isUnlocked(index: index) else { return false }
        guard index != activeIndex else { return true }
        activeIndex = index
        defaults.set(index, forKey: Self.activeSlotKey(baseOwnerID: baseOwnerID))
        refresh()
        NotificationCenter.default.post(name: Self.didChange, object: baseOwnerID)
        return true
    }

    func refresh() {
        summaries = Self.slots.map { slot in
            let ownerKey = HomeIslandPersistence.ownerKey(for: slot.ownerID(base: baseOwnerID))
            let stored = HomeIslandPersistence.summary(ownerKey: ownerKey)
            return HomeIslandSlotSummary(
                slot: slot,
                updatedAt: stored?.updatedAt,
                placementCount: stored?.placementCount ?? 0
            )
        }
    }

    static func activeSlotKey(baseOwnerID: String) -> String {
        "homeIsland.activeSlot.\(HomeIslandPersistence.ownerKey(for: baseOwnerID))"
    }
}
