import SwiftUI

struct HashtagChips: View {
    var tags: [String]
    var body: some View {
        if !tags.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(AppHashtags.clean(tags), id: \.self) { tag in
                        NavigationLink { HashtagEntriesView(tag: tag) } label: { Text("#" + tag).font(.caption.bold()).padding(.horizontal, 10).padding(.vertical, 7).background(Color.accentColor.opacity(0.08), in: Capsule()) }
                    }
                }
            }
        }
    }
}
struct HashtagEditor: View {
    @EnvironmentObject private var store: AppStore
    @Binding var tags: [String]
    @State private var input = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Hashtags").font(.subheadline.bold())
            ScrollView(.horizontal) { HStack { ForEach(AppHashtags.clean(tags), id: \.self) { tag in Button { tags.removeAll { AppHashtags.key($0) == AppHashtags.key(tag) } } label: { Label("#" + tag, systemImage: "xmark.circle") }.buttonStyle(.bordered).accessibilityLabel("Hashtag " + tag + " entfernen") } } }
            HStack { TextField("Hashtag hinzufügen", text: $input).submitLabel(.done).onSubmit(add); Button("Hinzufügen", action: add).disabled(input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
            ScrollView(.horizontal) { HStack { ForEach(AppHashtags.catalog(store.data).filter { known in !tags.contains { AppHashtags.key($0) == AppHashtags.key(known) } }.prefix(20), id: \.self) { tag in Button("#" + tag) { tags = AppHashtags.clean(tags + [tag], known: AppHashtags.catalog(store.data)) }.buttonStyle(.bordered) } } }
        }
    }
    private func add() { tags = AppHashtags.clean(tags + input.split(separator: ",").map(String.init), known: AppHashtags.catalog(store.data)); input = "" }
}
struct HashtagEntriesView: View {
    @EnvironmentObject private var store: AppStore
    var tag: String
    @State private var opened: ArchiveRecord?
    private var records: [ArchiveRecord] { ArchiveRecord.all(in: store.data).filter { AppHashtags.tags($0).contains { AppHashtags.key($0) == AppHashtags.key(tag) } }.sorted { $0.date > $1.date } }
    var body: some View {
        TherapyScreen {
            LazyVStack(spacing: 14) {
                Text("\(records.count) Einträge mit diesem Hashtag").font(.subheadline).foregroundStyle(.secondary)
                ForEach(records) { record in ArchiveTimelineCard(record: record, open: { opened = record }) }
                if records.isEmpty { ContentUnavailableView("Noch keine Einträge", systemImage: "number") }
            }
        }.navigationTitle("#" + tag).sheet(item: $opened) { ArchiveRecordEditor(record: $0) }
    }
}
