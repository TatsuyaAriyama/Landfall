import SwiftUI

/// One line on the island's ToDo list. Deliberately tiny: a title and whether
/// it is done. Anything richer belongs to study items, not to this list.
struct HomeIslandTodoItem: Codable, Equatable, Identifiable {
    let id: UUID
    var title: String
    var isCompleted: Bool
    let createdAt: Date

    init(title: String) {
        id = UUID()
        self.title = title
        isCompleted = false
        createdAt = .now
    }
}

/// The list is shown from two places that are never on screen together — the
/// island and the sailing timer — so a shared store keeps them from drifting
/// apart while a voyage is running.
@MainActor
final class HomeIslandTodoStore: ObservableObject {
    static let shared = HomeIslandTodoStore()

    private static let storageKey = "homeIsland.todoItems.v1"

    @Published var items: [HomeIslandTodoItem] {
        didSet {
            guard items != oldValue else { return }
            persist()
        }
    }

    var openCount: Int {
        items.filter { !$0.isCompleted }.count
    }

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.storageKey),
           let stored = try? JSONDecoder().decode([HomeIslandTodoItem].self, from: data) {
            items = stored
        } else {
            items = []
        }
    }

    func add(_ title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        items.insert(HomeIslandTodoItem(title: String(trimmed.prefix(120))), at: 0)
    }

    func toggle(_ item: HomeIslandTodoItem) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[index].isCompleted.toggle()
    }

    func remove(_ item: HomeIslandTodoItem) {
        items.removeAll { $0.id == item.id }
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(items) else { return }
        UserDefaults.standard.set(data, forKey: Self.storageKey)
    }
}

/// The list body used inside compact floating panels. It carries no navigation
/// chrome of its own: whatever presents it owns the header and the close
/// button, which is what keeps these panels small.
struct HomeIslandTodoCompactList: View {
    @ObservedObject var store: HomeIslandTodoStore
    var ink: Color
    var maxListHeight: CGFloat = 236

    @State private var draft = ""
    @FocusState private var draftFocused: Bool

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                TextField("Add a task", text: $draft)
                    .font(LFFont.copy(13))
                    .foregroundStyle(ink)
                    .tint(ink)
                    .textInputAutocapitalization(.sentences)
                    .submitLabel(.done)
                    .focused($draftFocused)
                    .onSubmit(addDraft)

                Button(action: addDraft) {
                    Image(systemName: "plus")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 30, height: 30)
                        .background(ink, in: Circle())
                }
                .buttonStyle(LFPressableButtonStyle())
                .disabled(trimmedDraft.isEmpty)
                .opacity(trimmedDraft.isEmpty ? 0.4 : 1)
                .accessibilityLabel(Text("Add"))
            }
            .padding(.leading, 12)
            .padding(.trailing, 6)
            .frame(minHeight: 42)
            .background(ink.opacity(0.05), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .stroke(ink.opacity(0.12), lineWidth: 1)
            )

            if store.items.isEmpty {
                Text("Add a task for your next voyage.")
                    .font(LFFont.label(10))
                    .foregroundStyle(ink.opacity(0.5))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 10)
            } else {
                ScrollView {
                    VStack(spacing: 2) {
                        ForEach(store.items) { item in
                            row(item)
                        }
                    }
                }
                .frame(maxHeight: maxListHeight)
                .scrollBounceBehavior(.basedOnSize)
            }
        }
    }

    private func row(_ item: HomeIslandTodoItem) -> some View {
        HStack(spacing: 9) {
            Button {
                store.toggle(item)
                Haptics.tap(.light)
            } label: {
                HStack(spacing: 9) {
                    Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(item.isCompleted ? ink.opacity(0.62) : ink.opacity(0.38))
                    Text(verbatim: item.title)
                        .font(LFFont.copy(12))
                        .foregroundStyle(ink.opacity(item.isCompleted ? 0.42 : 0.9))
                        .strikethrough(item.isCompleted, color: ink.opacity(0.34))
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityValue(Text(item.isCompleted ? "Completed" : "Not completed"))

            Button {
                store.remove(item)
                Haptics.tap(.light)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(ink.opacity(0.42))
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Delete"))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(ink.opacity(0.04), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
    }

    private var trimmedDraft: String {
        draft.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func addDraft() {
        guard !trimmedDraft.isEmpty else { return }
        store.add(trimmedDraft)
        draft = ""
        draftFocused = true
        Haptics.tap(.light)
    }
}
