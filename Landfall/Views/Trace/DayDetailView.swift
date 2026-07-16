import SwiftUI
import SwiftData

/// ある日の記録の詳細。その日に刻んだ全項目のセッションを見て、編集・削除できる。
struct DayDetailView: View {
    let day: Date

    @Environment(\.dismiss) private var dismiss
    @Query private var allSessions: [StudySession]
    @State private var editingSession: StudySession?

    private var sessions: [StudySession] {
        let calendar = Calendar.current
        return allSessions
            .filter { calendar.isDate($0.date, inSameDayAs: day) }
            .sorted { $0.date < $1.date }
    }

    private var totalMinutes: Int {
        sessions.reduce(0) { $0 + $1.minutes }
    }

    var body: some View {
        ZStack {
            LFColor.paper.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text(LF.dayWithWeekday(day))
                        .font(LFFont.copy(24))
                        .foregroundStyle(LFColor.ink)

                    if !sessions.isEmpty {
                        Text("\(LF.duration(minutes: totalMinutes)) · \(itemCount) items this day")
                            .font(LFFont.label(14))
                            .foregroundStyle(LFColor.ink.opacity(0.5))
                            .padding(.top, 8)
                    }

                    if sessions.isEmpty {
                        Text("No records left for this day.")
                            .font(LFFont.copy(16))
                            .foregroundStyle(LFColor.ink.opacity(0.5))
                            .padding(.top, 28)
                    } else {
                        VStack(spacing: 0) {
                            ForEach(Array(sessions.enumerated()), id: \.element.persistentModelID) { index, session in
                                if index > 0 {
                                    Rectangle()
                                        .fill(LFColor.ink.opacity(0.08))
                                        .frame(height: 1)
                                }
                                sessionRow(session)
                            }
                        }
                        .padding(.top, 24)
                    }
                }
                .padding(LFMetrics.cardPadding)
            }
        }
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    dismiss()
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "chevron.left")
                        Text("Trace")
                    }
                    .font(LFFont.label(16))
                    .foregroundStyle(LFColor.ink)
                }
            }
        }
        .toolbarBackground(LFColor.paper, for: .navigationBar)
        .sheet(item: $editingSession) { session in
            SessionEditSheet(session: session)
        }
        // 最後の記録を消したら詳細を閉じる。
        .onChange(of: sessions.isEmpty) { _, empty in
            if empty { dismiss() }
        }
    }

    private func sessionRow(_ session: StudySession) -> some View {
        Button {
            editingSession = session
        } label: {
            HStack(spacing: 14) {
                if let item = session.item {
                    ItemTileArt(item: item)
                        .frame(width: 44, height: 44)
                }
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        // 項目名はユーザーデータ(verbatim)、無い場合のみ言語追従の代替語。
                        Group {
                            if let name = session.item?.name {
                                Text(verbatim: name)
                            } else {
                                Text("No item")
                            }
                        }
                            .font(LFFont.copy(16))
                            .foregroundStyle(LFColor.ink)
                        Text(LF.duration(minutes: session.minutes))
                            .font(LFFont.label(14))
                            .monospacedDigit()
                            .foregroundStyle(LFColor.ink.opacity(0.55))
                    }
                    if let note = session.note, !note.isEmpty {
                        Text(note)
                            .font(LFFont.label(15))
                            .foregroundStyle(LFColor.ink.opacity(0.65))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(LFColor.ink.opacity(0.25))
            }
            .padding(.vertical, 14)
        }
        .buttonStyle(.plain)
    }

    private var itemCount: Int {
        Set(sessions.compactMap { $0.item?.persistentModelID }).count
    }

}
