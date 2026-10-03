import Foundation
import CryptoKit

enum AppFileAccess {
    static func isTemporaryDenial(_ error: Error) -> Bool {
        let value = error as NSError
        if value.domain == NSCocoaErrorDomain && [NSFileReadNoPermissionError, NSFileWriteNoPermissionError].contains(value.code) { return true }
        if value.domain == NSPOSIXErrorDomain && [1, 13].contains(value.code) { return true }
        if let underlying = value.userInfo[NSUnderlyingErrorKey] as? NSError { return isTemporaryDenial(underlying) }
        return false
    }
}

enum AppFileStorage {
    static func root(applicationSupport: URL, documents: URL, folder: String) throws -> URL {
        let target = documents.appendingPathComponent(folder == "Therapie" ? "Therapiedaten" : folder, isDirectory: true)
        let old = applicationSupport.appendingPathComponent(folder, isDirectory: true)
        let fm = FileManager.default
        try BackupArchive.recoverInterruptedRestore(root: old)
        try BackupArchive.recoverInterruptedRestore(root: target)
        try fm.createDirectory(at: documents, withIntermediateDirectories: true)
        if fm.fileExists(atPath: old.appendingPathComponent("therapy-data.json").path), fm.fileExists(atPath: target.path), !fm.fileExists(atPath: target.appendingPathComponent("therapy-data.json").path) {
            throw BackupArchiveError.invalid("Der Zielordner Therapiedaten ist bereits belegt. Die bisherigen App-Daten bleiben unverändert erhalten.")
        }
        if !fm.fileExists(atPath: target.path), fm.fileExists(atPath: old.path) {
            try fm.moveItem(at: old, to: target)
        }
        let oldRecovery = BackupArchive.recoveryURL(old), newRecovery = BackupArchive.recoveryURL(target)
        if fm.fileExists(atPath: oldRecovery.path), !fm.fileExists(atPath: newRecovery.path) { try fm.moveItem(at: oldRecovery, to: newRecovery) }
        return target
    }
}

enum ReadableBackup {
    static func relativePath(_ file: URL, in root: URL) throws -> String {
        let prefix = root.resolvingSymlinksInPath().path + "/"
        let path = file.resolvingSymlinksInPath().path
        guard path.hasPrefix(prefix) else { throw BackupArchiveError.invalid("Eine Datei liegt außerhalb des Sicherungsordners.") }
        return String(path.dropFirst(prefix.count))
    }
    static let labels: [String: String] = [
        "impactConfirmed": "Akku-Wirkung bestaetigt", "answeredStep": "Beantwortetes Check-in-Modul", "accentTheme": "Hauptfarbe", "wellbeingPreferences": "Befinden-Einstellungen", "estimateBattery": "Akku-Schaetzung aktiviert", "hourlyDecline": "Prozentpunkte je Stunde", "satisfaction": "Selbstberichtete Zufriedenheit", "memory": "Kurze Gespraechsnotiz", "quickReplies": "Passende Antwortvorschlaege", "speakReplies": "Antworten automatisch vorlesen", "conversationTranscript": "Vollstaendiges Gespraech", "conversationID": "Gespraech-ID", "percent": "Akku in Prozent",
        "editorDrafts": "Gespeicherte Entwuerfe", "draftText": "Noch nicht gesendeter Text", "weeklyReviewEnabled": "Automatischer Wochenrueckblick", "lastWeeklyReview": "Letzter Wochenrueckblick", "repeatEveryWeeks": "Alle x Wochen", "endsAt": "Enddatum", "recurrenceAnchor": "Wiederholung ab",
        "aiConversations": "KI-Chats", "hashtagCatalog": "Hashtags", "aiSettings": "KI-Einstellungen", "aiMessages": "KI-Gespraeche", "therapyDiscussionAcknowledgedIDs": "Besprochene Gespraechspunkte",
        "recurrence": "Therapie-Rhythmus", "extraAppointments": "Einzelne Zusatztermine", "additionalWeeklySlots": "Weitere Wochentermine", "unit": "Intervall-Einheit", "interval": "Intervall", "anchor": "Startdatum", "exactTime": "Absage gilt nur fuer diese Uhrzeit",
        "allowMultipleCheckInsPerSlot": "Zusaetzliche Check-ins pro Zeitfenster erlauben", "alarmShowsActualTitles": "Echte Routine-Titel in AlarmKit",
        "model": "KI-Modell", "transcriptionModel": "Transkriptionsmodell", "contextDays": "Standard-Kontext in Tagen", "automaticRange": "Zeitraum aus Frage erkennen", "includeJournal": "Tagebuch einbeziehen", "allowPhotoUploads": "Ausgewaehlte Foto-Uploads erlauben", "allowVoiceUploads": "Sprachnachrichten-Uploads erlauben", "contextStart": "Kontext ab", "contextEnd": "Kontext bis", "inputTokens": "Eingabetokens der letzten Antwort", "outputTokens": "Ausgabetokens der letzten Antwort", "appliedActionIDs": "Bereits gespeicherte Vorschlaege", "savedNoteID": "Gespeicherter Rueckblick", "reply": "KI-Antwort", "sections": "Abschnitte", "heading": "Ueberschrift", "actions": "Native App-Vorschlaege", "suggestedDays": "Vorgeschlagener Kontext in Tagen", "role": "Gesprächsrolle",

        "dashboard": "Heute-Einstellungen", "archivePreferences": "Archiv-Einstellungen", "cardOrder": "Kartenreihenfolge", "hiddenCards": "Ausgeblendete Karten", "pinnedCards": "Oben angepinnte Karten", "pinnedRecordIDs": "Angepinnte Archiveintraege", "compactCards": "Kompakte Abstaende", "showWidgetTitles": "Titel in Widgets anzeigen", "grouping": "Zeitliche Gruppierung", "oldestFirst": "Aelteste zuerst",
        "cancellations": "Therapie-Absagen", "therapyVacations": "Therapiepausen", "therapyAlarmsEnabled": "Therapie-Wecker aktiv", "restoredAt": "Wiederhergestellt am", "endedAt": "Beendet am", "sessionPhaseAlarmsEnabled": "Wecker nach jedem Abschnitt", "checkInReminders": "Check-in-Erinnerungen", "corrections": "Korrekturen", "routineTitle": "Routinenname", "timeTitle": "Terminname", "reason": "Grund", "previousOutcome": "Vorheriger-Status", "previousNote": "Vorherige-Notiz",
        "guidedCheckIns": "Gefuehrte-Check-ins", "routines": "Alltagsroutinen", "routineCompletions": "Routine-Protokoll", "routineSnoozes": "Verschobene-Routinen", "companionSettings": "Alltags-Einstellungen",
        "batteryPercent": "Akku in Prozent", "isDraft": "Entwurf", "scheduledAt": "Geplant fuer", "recordedAt": "Bestaetigt am", "outcome": "Ergebnis", "times": "Uhrzeiten", "pauseOnVacation": "Urlaubspause", "retryMinutes": "Erneut erinnern nach Minuten",
        "weeklyTasks": "Wochenaufgaben", "notes": "Notizen", "energyEntries": "Energie-Checks", "media": "Materialien",
        "entryLocations": "Eintrags-Standorte", "buddySuggestions": "Persoenliche KI-Impulse", "captureEntryLocation": "Standorte fuer neue Eintraege", "suggestionsEnabled": "KI-Impulse aktiviert", "mediaIDs": "Verknuepfte Anhaenge", "draftMediaIDs": "Entwurfs-Anhaenge", "repeatUntilDone": "Erneut bis erledigt",
        "reflections": "Therapie-Rueckblicke", "moodCheckIns": "Stimmungs-Check-ins", "batteryPoints": "Akku-Punkte",
        "weekReviews": "Wochenrueckblicke", "therapyFolders": "Therapieordner", "therapyTopics": "Therapiethemen",
        "therapyGoals": "Therapieziele", "sessionTemplates": "Stundenplaene", "sessionHistory": "Therapiestunden",
        "weeklyEnergyReviews": "Wochen-Energie", "title": "Titel", "text": "Text", "note": "Notiz",
        "date": "Datum", "createdAt": "Erstellt", "completedAt": "Erledigt am", "completed": "Erledigt", "details": "Beschreibung",
        "smallStep": "Kleinster Schritt", "support": "Unterstuetzung", "progress": "Fortschritt", "dueDate": "Faelligkeit",
        "givesEnergy": "Gibt Energie", "takesEnergy": "Nimmt Energie", "gives": "Gibt Energie", "takes": "Nimmt Energie",
        "energy": "Energie", "level": "Energie", "battery": "Akku", "impact": "Einfluss", "direction": "Richtung", "category": "Kategorie",
        "summary": "Zusammenfassung", "nextStep": "Naechster Schritt", "whatHelped": "Was geholfen hat", "whatWasHard": "Was schwer war",
        "smallWin": "Kleiner Erfolg", "therapyQuestion": "Frage fuer die Therapie", "nextFocus": "Naechster Schwerpunkt",
        "mood": "Stimmung", "emotions": "Gefuehle", "stress": "Stress", "sensoryLoad": "Reizbelastung", "sleepHours": "Schlafstunden",
        "author": "Verfasst von", "isImportant": "Wichtig", "tags": "Tags", "status": "Stand", "relativePath": "Anhangspfad",
        "attachmentOmitted": "Anhang ausgelassen", "periodEnd": "Rueckblick bis", "periodStart": "Rueckblick ab", "namedLiveActivity": "Echte Abschnittsnamen in Live-Aktivitaet", "reminder": "Erinnerung", "moodPercent": "Stimmungsbarometer 0-100", "energyPoints": "Einzelne Akku-Stichwoerter", "mediaIDs": "Verknuepfte Anhaenge", "updatedAt": "Zuletzt bearbeitet", "dayCheckInSlots": "Tages-Check-in-Zeitfenster", "daySlotID": "Tagesfenster", "customTitle": "Eigener Check-in-Name", "taskAlarmsEnabled": "Aufgaben als AlarmKit-Wecker", "sessionAlarmsEnabled": "Therapietimer als AlarmKit-Wecker", "wellnessAlarmEnabled": "Stimmung als AlarmKit-Wecker", "energyReviewAlarm": "Wochenenergie als AlarmKit-Wecker", "alarmEnabled": "AlarmKit-Wecker aktiv", "slotID": "Tagesfenster-ID", "startHour": "Beginn Stunde", "endHour": "Ende Stunde"
    ]
    static func description(_ value: Any, indent: String = "") -> String {
        if let object = value as? [String: Any] {
            return object.keys.sorted().map { key in indent + (labels[key] ?? key) + ":\n" + description(object[key]!, indent: indent + "  ") }.joined(separator: "\n")
        }
        if let array = value as? [Any] { return array.isEmpty ? indent + "(keine)" : array.map { indent + "•\n" + description($0, indent: indent + "  ") }.joined(separator: "\n") }
        if value is NSNull { return indent + "(nicht angegeben)" }
        return String(describing: value).components(separatedBy: .newlines).map { indent + $0 }.joined(separator: "\n")
    }
    static func writeText(_ text: String, to url: URL) throws {
        let raw = Data(text.utf8)
        if let previous = try? Data(contentsOf: url), previous == raw { return }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try raw.write(to: url, options: .atomic); try BackupArchive.protect(url)
    }
    static func writeEntries(data: AppData, root: URL, preferences: PortablePreferences = PortablePreferences()) throws {
        let fm = FileManager.default
        var object = try JSONSerialization.jsonObject(with: BackupArchive.encoder().encode(data.portableSnapshot)) as! [String: Any]
        object["appearancePreferences"] = try JSONSerialization.jsonObject(with: BackupArchive.encoder().encode(preferences))
        try BackupArchive.encoder().encode(preferences).write(to: root.appendingPathComponent("appearance-preferences.json"), options: .atomic)
        try BackupArchive.protect(root.appendingPathComponent("appearance-preferences.json"))
        let base = root.appendingPathComponent("Eintraege", isDirectory: true)
        try fm.createDirectory(at: base, withIntermediateDirectories: true)
        var keep = Set<String>(), index = "# Deine Therapiedaten\n\nStand: \(ISO8601DateFormatter().string(from: Date()))\n\n"
        for key in object.keys.sorted() {
            let group = labels[key] ?? key
            if let records = object[key] as? [[String: Any]] {
                index += "## \(group) (\(records.count))\n\n"
                for (number, record) in records.enumerated() {
                    let id = (record["id"] as? String).flatMap(UUID.init(uuidString:))?.uuidString ?? String(number)
                    let title = record["title"] as? String ?? record["summary"] as? String ?? group
                    let relative = key + "/" + id + ".txt"
                    keep.insert(relative)
                    var context = ""
                    if let folder = (record["folderID"] as? String).flatMap(UUID.init(uuidString:)) {
                        context += "Therapieordner: " + TherapyHierarchy.path(for: folder, folders: data.therapyFolders) + "\n"
                    }
                    if let topic = (record["topicID"] as? String).flatMap(UUID.init(uuidString:)), let item = data.therapyTopics.first(where: { $0.id == topic }) { context += "Therapiethema: " + item.title + "\n" }
                    var readable = record
                    if key == "editorDrafts", let payload = record["payload"] as? String, let bytes = Data(base64Encoded: payload), let fields = try? JSONSerialization.jsonObject(with: bytes) {
                        readable["payload"] = fields
                    }
                    try writeText(title + "\n\n" + context + "\n" + description(readable) + "\n", to: base.appendingPathComponent(relative))
                    let cleanTitle = title.replacingOccurrences(of: "\n", with: " ").replacingOccurrences(of: "[", with: "(").replacingOccurrences(of: "]", with: ")")
                    index += "- [\(cleanTitle)](Eintraege/\(relative))\n"
                }
                index += "\n"
            } else {
                let relative = "Einstellungen/" + key + ".txt"
                keep.insert(relative)
                try writeText(group + "\n\n" + description(object[key]!) + "\n", to: base.appendingPathComponent(relative))
                index += "- [\(group)](Eintraege/\(relative))\n"
            }
        }
        if let enumerator = fm.enumerator(at: base, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey]) {
            for case let file as URL in enumerator {
                let values = try file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
                guard values.isSymbolicLink != true else { throw BackupArchiveError.invalid("Ein lesbarer Eintragsordner enthält einen Dateiverweis. Bitte sichere ihn in Dateien und entferne den Verweis.") }
                if values.isRegularFile == true {
                    let relative = try relativePath(file, in: base)
                    if !keep.contains(relative) { try fm.removeItem(at: file) }
                }
            }
        }
        try writeText(index, to: root.appendingPathComponent("UEBERSICHT.md"))
        try writeText("""
        THERAPIE – LESBARE DATEN

        Diese Dateien sind NICHT passwortverschlüsselt.
        UEBERSICHT.md und Eintraege/ enthalten lesbare Einzeldateien für sämtliche gespeicherten Einträge und Einstellungen.
        therapy-data.json enthält den vollständigen maschinenlesbaren Datenstand.
        appearance-preferences.json enthält Darstellung, ruhige Oberfläche, Haptik und Konfetti-Einstellung.
        Media/ und Recordings/ enthalten vorhandene Fotos, Dokumente und Sprachaufnahmen.
        Therapieordner und Themenzuordnungen stehen in den Einzeldateien; IDs erhalten die Beziehungen eindeutig.

        Du findest den laufenden Datenordner unter Dateien > Auf meinem iPhone > Therapie > Therapiedaten.
        Kopiere diesen Ordner an einen anderen Speicherort, wenn die App nicht mehr startet.
        Der Ordner wird beim Löschen der App ebenfalls gelöscht. Vor einer Deinstallation extern sichern!
        Bearbeite oder entferne Dateien des laufenden Datenordners nicht, während die App benutzt wird.
        Die lesbaren Dateien werden nach Änderungen automatisch aktualisiert; die JSON-Datei ist maßgeblich.

        Ein exportiertes Klartext-ZIP kann ohne diese App entpackt und gelesen werden.
        Originale ZIP-Sicherungen dieses Updates können außerdem in der App unter Export & Import wiederhergestellt werden.
        Anhänge, die du im Export ausgelassen hast, bleiben als Metadateneinträge mit attachmentOmitted erhalten.
        Erinnerungen und Berechtigungen werden auf dem Zielgerät neu eingerichtet.
        """, to: root.appendingPathComponent("LIES-MICH.txt"))
    }

    static func export(data: AppData, root: URL, preferences: PortablePreferences, options: BackupOptions, version: String, progress: (Double) -> Void = { _ in }) throws -> URL {
        BackupDiskAccess.lock.lock(); defer { BackupDiskAccess.lock.unlock() }
        let staged = try BackupArchive.privateDirectory(), outputDirectory = try BackupArchive.privateDirectory()
        defer { try? FileManager.default.removeItem(at: staged) }
        var success = false
        defer { if !success { try? FileManager.default.removeItem(at: outputDirectory) } }
        var snapshot = data.portableSnapshot, attachments: [BackupManifest.Attachment] = [], seen = Set<String>(), sources: [(String, URL)] = []
        for folder in ["Media", "Recordings"] { try FileManager.default.createDirectory(at: staged.appendingPathComponent(folder), withIntermediateDirectories: true) }
        for i in snapshot.media.indices {
            let item = snapshot.media[i]; try BackupArchive.validatePath(item.relativePath)
            guard seen.insert(item.relativePath).inserted else { throw BackupArchiveError.invalid("Mehrere Materialien verwenden denselben Anhangspfad.") }
            if !options.includes(item.kind) || item.attachmentOmitted == true { snapshot.media[i].attachmentOmitted = true; continue }
            let source = try BackupArchive.sourceURL(item.relativePath, root: root)
            let (bytes, sha) = try BackupArchive.fingerprint(source)
            sources.append((item.relativePath, source))
            attachments.append(.init(path: item.relativePath, bytes: bytes, sha256: sha))
            snapshot.media[i].attachmentOmitted = nil
        }
        let manifest = BackupManifest(appVersion: version, data: snapshot, preferences: preferences, attachments: attachments, omittedAttachments: snapshot.media.filter { $0.attachmentOmitted == true }.count)
        let rawData = try BackupArchive.encoder().encode(snapshot), rawManifest = try BackupArchive.encoder().encode(manifest)
        guard rawData.count <= BackupArchive.manifestLimit, rawManifest.count <= BackupArchive.manifestLimit else { throw BackupArchiveError.invalid("Die Eintragsdaten überschreiten die sichere Grenze von 64 MB. Anhänge zählen nicht dazu.") }
        try rawData.write(to: staged.appendingPathComponent("therapy-data.json"), options: .atomic)
        try rawManifest.write(to: staged.appendingPathComponent("manifest.json"), options: .atomic)
        try writeEntries(data: snapshot, root: staged, preferences: preferences)
        let url = outputDirectory.appendingPathComponent("Therapie-Klartext-\(Int(Date().timeIntervalSince1970)).zip")
        let fingerprints = try StoredZIP.write(directory: staged, output: url, additionalFiles: sources, progress: progress)
        for attachment in attachments {
            guard let fingerprint = fingerprints[attachment.path], fingerprint.0 == attachment.bytes, fingerprint.1 == attachment.sha256 else { throw BackupArchiveError.invalid("Ein Anhang hat sich beim Export verändert. Bitte erneut sichern.") }
        }
        try BackupArchive.protect(url); success = true; return url
    }

    static func prepareImport(url: URL) throws -> PreparedBackup {
        let staged = try BackupArchive.privateDirectory(); var success = false
        defer { if !success { try? FileManager.default.removeItem(at: staged) } }
        try StoredZIP.extract(archive: url, destination: staged)
        let manifestURL = staged.appendingPathComponent("manifest.json")
        let size = try manifestURL.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? Int.max
        guard size <= BackupArchive.manifestLimit else { throw BackupArchiveError.invalid("Das ZIP enthält zu große Eintragsdaten.") }
        let manifest = try BackupArchive.decoder().decode(BackupManifest.self, from: Data(contentsOf: manifestURL))
        guard manifest.formatVersion == 1 else { throw BackupArchiveError.invalid("Diese Sicherung benötigt eine neuere App-Version.") }
        let dataURL = staged.appendingPathComponent("therapy-data.json")
        guard (try dataURL.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? Int.max) <= BackupArchive.manifestLimit else { throw BackupArchiveError.invalid("Die ZIP-Datendatei ist zu groß.") }
        let saved = try BackupArchive.decoder().decode(AppData.self, from: Data(contentsOf: dataURL))
        guard saved == manifest.data else { throw BackupArchiveError.invalid("ZIP-Manifest und Datendatei stimmen nicht überein.") }
        var paths = Set<String>()
        for attachment in manifest.attachments {
            try BackupArchive.validatePath(attachment.path)
            guard paths.insert(attachment.path).inserted else { throw BackupArchiveError.invalid("Doppelter Anhang im ZIP.") }
            let file = try BackupArchive.sourceURL(attachment.path, root: staged)
            let (bytes, hash) = try BackupArchive.fingerprint(file)
            guard bytes == attachment.bytes, hash == attachment.sha256 else { throw BackupArchiveError.invalid("Ein ZIP-Anhang fehlt oder ist beschädigt.") }
        }
        guard paths == Set(saved.media.filter { $0.attachmentOmitted != true }.map(\.relativePath)),
              Set(saved.media.map(\.relativePath)).count == saved.media.count,
              manifest.omittedAttachments == saved.media.filter({ $0.attachmentOmitted == true }).count else { throw BackupArchiveError.invalid("Die ZIP-Anhänge passen nicht zu den Einträgen.") }
        for item in saved.media { try BackupArchive.validatePath(item.relativePath) }
        for folder in ["Media", "Recordings"] { try FileManager.default.createDirectory(at: staged.appendingPathComponent(folder), withIntermediateDirectories: true) }
        success = true; return PreparedBackup(directory: staged, manifest: manifest)
    }
}

/// Streaming, uncompressed ZIP64. Standard tools can read it without this app.
/// ZIP64 supports large attachments; CRC32 detects transport corruption.
enum StoredZIP {
    struct Entry { var name: String; var bytes: UInt64; var offset: UInt64; var crc: UInt32 }
    static let flags: UInt16 = 0x0808
    static let crcTable: [UInt32] = (0..<256).map { value in
        var crc = UInt32(value)
        for _ in 0..<8 { crc = (crc & 1) != 0 ? 0xedb88320 ^ (crc >> 1) : crc >> 1 }
        return crc
    }
    static func crc(_ bytes: Data, state: inout UInt32) { for byte in bytes { state = crcTable[Int((state ^ UInt32(byte)) & 255)] ^ (state >> 8) } }
    static func u(_ value: UInt64, _ count: Int) -> Data { Data((0..<count).map { UInt8(truncatingIfNeeded: value >> ($0 * 8)) }) }
    static func fields(_ values: [(UInt64, Int)]) -> Data {
        var bytes = Data()
        for (value, width) in values { bytes.append(u(value, width)) }
        return bytes
    }
    static func n(_ data: Data, _ start: Int, _ count: Int) -> UInt64 { data[start..<start + count].enumerated().reduce(0) { $0 | UInt64($1.element) << ($1.offset * 8) } }
    static func path(_ name: String) throws {
        let parts = name.split(separator: "/", omittingEmptySubsequences: false)
        guard !parts.isEmpty, parts.count <= 32, name.utf8.count <= 1024, !name.contains("\\"), !name.contains("\0"),
              parts.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else { throw BackupArchiveError.invalid("Das ZIP enthält einen unsicheren Dateipfad.") }
    }
    @discardableResult
    static func write(directory: URL, output: URL, additionalFiles: [(String, URL)] = [], progress: (Double) -> Void) throws -> [String: (UInt64, Data)] {
        let fm = FileManager.default
        var sources: [(String, URL)] = []
        if let iterator = fm.enumerator(at: directory, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey]) {
            for case let url as URL in iterator {
                let value = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
                guard value.isSymbolicLink != true else { throw BackupArchiveError.invalid("Dateiverweise sind in ZIP-Sicherungen nicht erlaubt.") }
                if value.isRegularFile == true {
                    let relative = try ReadableBackup.relativePath(url, in: directory); try path(relative); sources.append((relative, url))
                }
            }
        }
        sources += additionalFiles
        for source in sources { try path(source.0) }
        guard Set(sources.map { $0.0 }).count == sources.count else { throw BackupArchiveError.invalid("Doppelte ZIP-Dateien.") }
        sources.sort { $0.0 < $1.0 }
        guard fm.createFile(atPath: output.path, contents: nil) else { throw BackupArchiveError.invalid("ZIP-Datei konnte nicht angelegt werden.") }
        let file = try FileHandle(forWritingTo: output); defer { try? file.close() }
        var entries: [Entry] = [], fingerprints: [String: (UInt64, Data)] = [:]
        for (index, source) in sources.enumerated() {
            let offset = try file.offset(), name = Data(source.0.utf8)
            let extra = u(1, 2) + u(16, 2) + Data(repeating: 0, count: 16)
            let header = fields([(0x04034b50, 4), (45, 2), (UInt64(flags), 2), (0, 2), (0, 2), (33, 2),
                                 (0, 4), (0xffffffff, 4), (0xffffffff, 4), (UInt64(name.count), 2), (UInt64(extra.count), 2)])
            try file.write(contentsOf: header + name + extra)
            let input = try FileHandle(forReadingFrom: source.1); defer { try? input.close() }
            var bytes: UInt64 = 0, state: UInt32 = 0xffffffff, hash = SHA256()
            while let chunk = try input.read(upToCount: BackupArchive.chunkSize), !chunk.isEmpty { crc(chunk, state: &state); hash.update(data: chunk); bytes += UInt64(chunk.count); try file.write(contentsOf: chunk) }
            fingerprints[source.0] = (bytes, Data(hash.finalize()))
            let checksum = state ^ 0xffffffff
            try file.write(contentsOf: fields([(0x08074b50, 4), (UInt64(checksum), 4), (bytes, 8), (bytes, 8)]))
            entries.append(.init(name: source.0, bytes: bytes, offset: offset, crc: checksum))
            progress(Double(index + 1) / Double(max(1, sources.count)))
        }
        let centralStart = try file.offset()
        for entry in entries {
            let name = Data(entry.name.utf8), extra = fields([(1, 2), (24, 2), (entry.bytes, 8), (entry.bytes, 8), (entry.offset, 8)])
            let header = fields([(0x02014b50, 4), (45, 2), (45, 2), (UInt64(flags), 2), (0, 2), (0, 2), (33, 2),
                                 (UInt64(entry.crc), 4), (0xffffffff, 4), (0xffffffff, 4), (UInt64(name.count), 2), (UInt64(extra.count), 2),
                                 (0, 2), (0, 2), (0, 2), (0, 4), (0xffffffff, 4)])
            try file.write(contentsOf: header + name + extra)
        }
        let centralEnd = try file.offset(), count = UInt64(entries.count)
        try file.write(contentsOf: fields([(0x06064b50, 4), (44, 8), (45, 2), (45, 2), (0, 4), (0, 4), (count, 8), (count, 8), (centralEnd - centralStart, 8), (centralStart, 8)]))
        try file.write(contentsOf: fields([(0x07064b50, 4), (0, 4), (centralEnd, 8), (1, 4)]))
        try file.write(contentsOf: fields([(0x06054b50, 4), (0, 2), (0, 2), (0xffff, 2), (0xffff, 2), (0xffffffff, 4), (0xffffffff, 4), (0, 2)]))
        try file.synchronize()
        return fingerprints
    }
    static func extract(archive: URL, destination: URL) throws {
        let file = try FileHandle(forReadingFrom: archive); defer { try? file.close() }
        let size = try file.seekToEnd()
        guard size >= 98 else { throw BackupArchiveError.invalid("Die ZIP-Datei ist unvollständig.") }
        try file.seek(toOffset: size - 98)
        let tail = try BackupArchive.exact(file, count: 98)
        guard n(tail, 0, 4) == 0x06064b50, n(tail, 4, 8) == 44, n(tail, 56, 4) == 0x07064b50, n(tail, 76, 4) == 0x06054b50,
              n(tail, 96, 2) == 0, n(tail, 16, 4) == 0, n(tail, 20, 4) == 0,
              n(tail, 24, 8) == n(tail, 32, 8), n(tail, 64, 8) == size - 98, n(tail, 72, 4) == 1 else { throw BackupArchiveError.invalid("Bitte wähle eine unveränderte ZIP-Sicherung aus dieser App. Andere ZIP-Formate werden nicht importiert.") }
        let count = n(tail, 32, 8), start = n(tail, 48, 8), length = n(tail, 40, 8)
        guard count <= 200_000, start <= size - 98, length == size - 98 - start else { throw BackupArchiveError.invalid("Ungültiges ZIP-Verzeichnis.") }
        try file.seek(toOffset: start)
        var entries: [Entry] = [], names = Set<String>(), total: UInt64 = 0
        for _ in 0..<count {
            let header = try BackupArchive.exact(file, count: 46)
            guard n(header, 0, 4) == 0x02014b50, n(header, 8, 2) == UInt64(flags), n(header, 10, 2) == 0,
                  n(header, 30, 2) == 28, n(header, 32, 2) == 0, n(header, 34, 2) == 0, n(header, 28, 2) <= 1024 else { throw BackupArchiveError.invalid("Nicht unterstützter ZIP-Eintrag.") }
            let rawName = try BackupArchive.exact(file, count: Int(n(header, 28, 2)))
            guard let name = String(data: rawName, encoding: .utf8) else { throw BackupArchiveError.invalid("Ungültiger ZIP-Dateiname.") }
            try path(name)
            guard names.insert(name.precomposedStringWithCanonicalMapping.lowercased()).inserted else { throw BackupArchiveError.invalid("Doppelte ZIP-Dateinamen.") }
            let extra = try BackupArchive.exact(file, count: 28)
            guard n(extra, 0, 2) == 1, n(extra, 2, 2) == 24, n(extra, 4, 8) == n(extra, 12, 8) else { throw BackupArchiveError.invalid("Ungültige ZIP64-Daten.") }
            let bytes = n(extra, 4, 8), offset = n(extra, 20, 8)
            guard total <= size, bytes <= size - total, offset < start else { throw BackupArchiveError.invalid("Ungültige ZIP-Dateigröße.") }
            total += bytes; entries.append(.init(name: name, bytes: bytes, offset: offset, crc: UInt32(n(header, 16, 4))))
        }
        guard try file.offset() == start + length else { throw BackupArchiveError.invalid("Unvollständiges ZIP-Verzeichnis.") }
        for entry in entries {
            try file.seek(toOffset: entry.offset)
            let header = try BackupArchive.exact(file, count: 30)
            guard n(header, 0, 4) == 0x04034b50, n(header, 6, 2) == UInt64(flags), n(header, 8, 2) == 0,
                  n(header, 26, 2) <= 1024, n(header, 28, 2) == 20 else { throw BackupArchiveError.invalid("Beschädigter ZIP-Dateikopf.") }
            let rawName = try BackupArchive.exact(file, count: Int(n(header, 26, 2)))
            guard String(data: rawName, encoding: .utf8) == entry.name else { throw BackupArchiveError.invalid("ZIP-Dateinamen stimmen nicht überein.") }
            _ = try BackupArchive.exact(file, count: 20)
            let dataStart = try file.offset()
            guard dataStart <= start, entry.bytes <= start - dataStart, start - dataStart - entry.bytes >= 24 else { throw BackupArchiveError.invalid("ZIP-Dateidaten fehlen.") }
            let target = destination.appendingPathComponent(entry.name)
            try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            guard FileManager.default.createFile(atPath: target.path, contents: nil) else { throw BackupArchiveError.invalid("Nicht genug Speicher für den ZIP-Import.") }
            try BackupArchive.protect(target)
            let output = try FileHandle(forWritingTo: target); defer { try? output.close() }
            var remaining = entry.bytes, state: UInt32 = 0xffffffff
            while remaining > 0 {
                let chunk = try BackupArchive.exact(file, count: Int(min(remaining, UInt64(BackupArchive.chunkSize))))
                crc(chunk, state: &state); try output.write(contentsOf: chunk); remaining -= UInt64(chunk.count)
            }
            let descriptor = try BackupArchive.exact(file, count: 24)
            guard state ^ 0xffffffff == entry.crc, n(descriptor, 0, 4) == 0x08074b50, n(descriptor, 4, 4) == UInt64(entry.crc), n(descriptor, 8, 8) == entry.bytes, n(descriptor, 16, 8) == entry.bytes else { throw BackupArchiveError.invalid("ZIP-Prüfsumme falsch. Deine Daten wurden nicht verändert.") }
            try output.synchronize()
        }
    }
}
