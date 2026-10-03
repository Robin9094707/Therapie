import Foundation

extension AppStore {
    func saveChatAudio(_ source: URL, duration: TimeInterval, transcript: String) throws -> UUID {
        guard storageReady, duration > 0 else { throw AIBuddyAPIError(message: "Die Aufnahme kann gerade nicht gespeichert werden.") }
        let name = UUID().uuidString + ".m4a", destination = recordingsURL.appendingPathComponent(name)
        try FileManager.default.copyItem(at: source, to: destination)
        do { try BackupArchive.protect(destination) } catch { try? FileManager.default.removeItem(at: destination); throw error }
        let item = MediaItem(kind: .audio, title: "Chat-Sprachnachricht", note: transcript, tags: ["Chat"], relativePath: "Recordings/" + name, duration: duration, source: "KI-Chat")
        data.media.insert(item, at: 0)
        if let error = lastSaveError { throw AIBuddyAPIError(message: error) }
        return item.id
    }
    func saveChatPhoto(_ bytes: Data) throws -> UUID {
        guard storageReady else { throw AIBuddyAPIError(message: "Bitte warte, bis die Daten verfügbar sind.") }
        let previous = Set(data.media.map(\.id))
        try importPhoto(bytes: bytes, fileExtension: "jpg", title: "Chat-Bild", note: "Ausgewählter Anhang", tags: ["Chat"], location: nil)
        guard lastSaveError == nil, let item = data.media.first(where: { !previous.contains($0.id) }) else { throw AIBuddyAPIError(message: lastSaveError ?? "Das Foto konnte nicht gespeichert werden.") }
        return item.id
    }
}
