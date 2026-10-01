import Foundation
import CryptoKit
import CommonCrypto
import Security

// All disk-based backup operations use the same lock, including the older folder backup.
enum BackupDiskAccess {
    static let lock = NSRecursiveLock()
}

struct PortablePreferences: Codable, Equatable {
    var appearance: String = "system"
    var calmInterface = true
    var haptics = true
    var confetti = true

    static func capture(_ defaults: UserDefaults = .standard) -> Self {
        var result = Self()
        result.appearance = defaults.string(forKey: "therapy.appearance") ?? "system"
        for (key, path) in [("calmInterface", \Self.calmInterface), ("haptics", \Self.haptics), ("confetti", \Self.confetti)] {
            if defaults.object(forKey: "therapy." + key) != nil { result[keyPath: path] = defaults.bool(forKey: "therapy." + key) }
        }
        return result
    }

    func apply(_ defaults: UserDefaults = .standard) {
        defaults.set(["system", "light", "dark"].contains(appearance) ? appearance : "system", forKey: "therapy.appearance")
        defaults.set(calmInterface, forKey: "therapy.calmInterface")
        defaults.set(haptics, forKey: "therapy.haptics")
        defaults.set(confetti, forKey: "therapy.confetti")
    }
}

struct BackupOptions {
    var includePhotos = true
    var includeAudio = true
    var includeDocuments = true
    func includes(_ kind: MediaKind) -> Bool {
        switch kind { case .photo: includePhotos; case .audio: includeAudio; case .document: includeDocuments }
    }
}

struct BackupManifest: Codable {
    struct Attachment: Codable {
        var path: String
        var bytes: UInt64
        var sha256: Data
    }
    var formatVersion = 1
    var createdAt = Date()
    var appVersion: String
    // Encode the complete model rather than maintaining a second list of domain fields.
    var data: AppData
    var preferences: PortablePreferences
    var attachments: [Attachment]
    var omittedAttachments: Int

    var attachmentBytes: UInt64 { attachments.reduce(0) { $0 + $1.bytes } }
    var entryCount: Int {
        data.weeklyTasks.count + data.notes.count + data.energyEntries.count + data.media.count + data.reflections.count
        + data.moodCheckIns.count + data.batteryPoints.count + data.weekReviews.count + data.therapyFolders.count
        + data.therapyTopics.count + data.therapyGoals.count + data.sessionTemplates.count + data.sessionHistory.count
        + data.weeklyEnergyReviews.count + (data.currentSession == nil ? 0 : 1)
    }
}

struct PreparedBackup: Identifiable {
    let id = UUID()
    let directory: URL
    let manifest: BackupManifest
    func discard() { try? FileManager.default.removeItem(at: directory) }
}

enum BackupArchiveError: LocalizedError {
    case invalid(String)
    case authentication
    var errorDescription: String? {
        switch self {
        case .invalid(let text): text
        case .authentication: "Das Passwort ist falsch oder die Sicherungsdatei ist beschädigt. Deine aktuellen Daten wurden nicht verändert."
        }
    }
}

/// Container v1: fixed header (magic, PBKDF2 rounds, salt), then length-prefixed
/// AES-256-GCM frames. Header and sequence are authenticated for every frame.
/// The encrypted manifest defines the exact order/size/hash of the streamed files;
/// an authenticated end marker and EOF check reject truncation, reorder and append.
enum BackupArchive {
    static let magic = Data("THRPBK01".utf8)
    static let rounds: UInt32 = 600_000
    static let chunkSize = 256 * 1024
    static let manifestLimit = 64 * 1024 * 1024
    static let endMarker = Data("THERAPIE-BACKUP-COMPLETE-V1".utf8)

    static func encoder() -> JSONEncoder {
        let result = JSONEncoder()
        result.dateEncodingStrategy = .iso8601
        result.outputFormatting = [.sortedKeys]
        return result
    }
    static func decoder() -> JSONDecoder {
        let result = JSONDecoder(); result.dateDecodingStrategy = .iso8601; return result
    }

    static func privateDirectory(in parent: URL = FileManager.default.temporaryDirectory) throws -> URL {
        let url = parent.appendingPathComponent("TherapieTransfer-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        try protect(url)
        return url
    }
    static func protect(_ url: URL) throws {
        #if os(iOS)
        try FileManager.default.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: url.path)
        #endif
    }
    static func validatePath(_ path: String) throws {
        let parts = path.split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count == 2, ["Media", "Recordings"].contains(String(parts[0])),
              !parts[1].isEmpty, parts[1] != ".", parts[1] != "..", !path.contains("\\"),
              !path.contains("\0"), path.utf8.count <= 1024 else {
            throw BackupArchiveError.invalid("Die Sicherung enthält einen ungültigen Dateipfad.")
        }
    }
    static func sourceURL(_ path: String, root: URL) throws -> URL {
        try validatePath(path)
        let url = root.appendingPathComponent(path)
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true,
              url.resolvingSymlinksInPath().path.hasPrefix(root.resolvingSymlinksInPath().path + "/") else {
            throw BackupArchiveError.invalid("Ein Anhang fehlt oder ist keine reguläre Datei: " + path)
        }
        return url
    }
    static func fingerprint(_ url: URL) throws -> (UInt64, Data) {
        let input = try FileHandle(forReadingFrom: url); defer { try? input.close() }
        var hash = SHA256(); var size: UInt64 = 0
        while let bytes = try input.read(upToCount: chunkSize), !bytes.isEmpty {
            size += UInt64(bytes.count); hash.update(data: bytes)
        }
        return (size, Data(hash.finalize()))
    }
    static func deriveKey(password: String, salt: Data, iterations: UInt32) throws -> SymmetricKey {
        guard !password.isEmpty, password.utf8.count <= 4096 else { throw BackupArchiveError.invalid("Bitte gib ein Passwort mit höchstens 4096 UTF-8-Bytes ein.") }
        var passwordBytes = Array(password.utf8)
        var keyBytes = [UInt8](repeating: 0, count: 32)
        defer { for i in passwordBytes.indices { passwordBytes[i] = 0 }; for i in keyBytes.indices { keyBytes[i] = 0 } }
        let status = passwordBytes.withUnsafeBytes { pass in
            salt.withUnsafeBytes { saltBytes in
                CCKeyDerivationPBKDF(CCPBKDFAlgorithm(kCCPBKDF2), pass.baseAddress!.assumingMemoryBound(to: Int8.self), pass.count,
                                    saltBytes.baseAddress!.assumingMemoryBound(to: UInt8.self), salt.count,
                                    CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256), iterations, &keyBytes, 32)
            }
        }
        guard status == kCCSuccess else { throw BackupArchiveError.invalid("Die Passwortverschlüsselung konnte nicht vorbereitet werden.") }
        return SymmetricKey(data: keyBytes)
    }
    static func integer<T: FixedWidthInteger>(_ value: T) -> Data {
        var big = value.bigEndian; return withUnsafeBytes(of: &big) { Data($0) }
    }
    static func number(_ bytes: Data) -> UInt64 { bytes.reduce(0) { ($0 << 8) | UInt64($1) } }
    static func exact(_ handle: FileHandle, count: Int) throws -> Data {
        var result = Data(); result.reserveCapacity(count)
        while result.count < count {
            guard let part = try handle.read(upToCount: count - result.count), !part.isEmpty else { throw BackupArchiveError.authentication }
            result.append(part)
        }
        return result
    }
    static func seal(_ bytes: Data, to output: FileHandle, key: SymmetricKey, header: Data, sequence: inout UInt64) throws {
        let box = try AES.GCM.seal(bytes, using: key, authenticating: header + integer(sequence))
        guard let combined = box.combined else { throw BackupArchiveError.authentication }
        try output.write(contentsOf: integer(UInt32(combined.count)))
        try output.write(contentsOf: combined); sequence += 1
    }
    static func open(from input: FileHandle, key: SymmetricKey, header: Data, sequence: inout UInt64, limit: Int) throws -> Data {
        let length = number(try exact(input, count: 4))
        guard length >= 28, length <= UInt64(limit + 28) else { throw BackupArchiveError.authentication }
        let combined = try exact(input, count: Int(length))
        do {
            let bytes = try AES.GCM.open(AES.GCM.SealedBox(combined: combined), using: key, authenticating: header + integer(sequence))
            sequence += 1; return bytes
        } catch { throw BackupArchiveError.authentication }
    }

    static func export(data: AppData, root: URL, preferences: PortablePreferences, options: BackupOptions,
                       password: String, version: String, progress: (Double) -> Void = { _ in }) throws -> URL {
        BackupDiskAccess.lock.lock(); defer { BackupDiskAccess.lock.unlock() }
        guard password.count >= 8 else { throw BackupArchiveError.invalid("Das Passwort muss mindestens acht Zeichen haben.") }
        var snapshot = data.portableSnapshot
        var attachments: [BackupManifest.Attachment] = []
        var seen = Set<String>()
        for i in snapshot.media.indices {
            let item = snapshot.media[i]
            try validatePath(item.relativePath)
            guard seen.insert(item.relativePath).inserted else { throw BackupArchiveError.invalid("Mehrere Materialien verweisen auf dieselbe Datei.") }
            if !options.includes(item.kind) || item.attachmentOmitted == true {
                snapshot.media[i].attachmentOmitted = true
                continue
            }
            let url = try sourceURL(item.relativePath, root: root)
            let (size, digest) = try fingerprint(url)
            attachments.append(.init(path: item.relativePath, bytes: size, sha256: digest))
            snapshot.media[i].attachmentOmitted = nil
        }
        let manifest = BackupManifest(appVersion: version, data: snapshot, preferences: preferences, attachments: attachments,
                                      omittedAttachments: snapshot.media.filter { $0.attachmentOmitted == true }.count)
        let raw = try encoder().encode(manifest)
        guard raw.count <= manifestLimit else { throw BackupArchiveError.invalid("Die Eintragsdaten überschreiten die sichere Grenze von 64 MB. Medien werden separat ohne diese Grenze verarbeitet.") }
        let directory = try privateDirectory()
        var successful = false
        defer { if !successful { try? FileManager.default.removeItem(at: directory) } }
        let date = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let url = directory.appendingPathComponent("Therapie-" + date + ".therapiebackup")
        guard FileManager.default.createFile(atPath: url.path, contents: nil) else { throw BackupArchiveError.invalid("Die Sicherungsdatei konnte nicht angelegt werden.") }
        try protect(url)
        let output = try FileHandle(forWritingTo: url); defer { try? output.close() }
        var saltBytes = [UInt8](repeating: 0, count: 16)
        guard SecRandomCopyBytes(kSecRandomDefault, saltBytes.count, &saltBytes) == errSecSuccess else { throw BackupArchiveError.invalid("Sichere Zufallswerte sind nicht verfügbar.") }
        let salt = Data(saltBytes), header = magic + integer(rounds) + salt
        let key = try deriveKey(password: password, salt: salt, iterations: rounds)
        try output.write(contentsOf: header)
        var sequence: UInt64 = 0
        try seal(raw, to: output, key: key, header: header, sequence: &sequence)
        var processed: UInt64 = 0
        for attachment in attachments {
            let source = try sourceURL(attachment.path, root: root)
            let input = try FileHandle(forReadingFrom: source)
            defer { try? input.close() }
            var hash = SHA256(), size: UInt64 = 0
            while let bytes = try input.read(upToCount: chunkSize), !bytes.isEmpty {
                try seal(bytes, to: output, key: key, header: header, sequence: &sequence)
                hash.update(data: bytes); size += UInt64(bytes.count); processed += UInt64(bytes.count)
                progress(Double(processed) / Double(max(1, manifest.attachmentBytes)))
            }
            guard size == attachment.bytes, Data(hash.finalize()) == attachment.sha256 else {
                throw BackupArchiveError.invalid("Ein Material hat sich während der Sicherung verändert. Bitte starte den Export erneut.")
            }
        }
        try seal(endMarker, to: output, key: key, header: header, sequence: &sequence)
        try output.synchronize()
        successful = true; progress(1)
        return url
    }

    static func prepareImport(url: URL, password: String, progress: (Double) -> Void = { _ in }) throws -> PreparedBackup {
        let input = try FileHandle(forReadingFrom: url); defer { try? input.close() }
        let encryptedSize = try input.seekToEnd()
        try input.seek(toOffset: 0)
        let header = try exact(input, count: 28)
        guard header.prefix(8) == magic else { throw BackupArchiveError.invalid("Diese Datei ist keine unterstützte Therapie-Sicherung. Verwende eine .therapiebackup-Datei aus einer kompatiblen App-Version.") }
        let iterations = number(Data(header[8..<12]))
        guard iterations == UInt64(rounds) else { throw BackupArchiveError.invalid("Diese Verschlüsselungsversion wird nicht unterstützt.") }
        let key = try deriveKey(password: password, salt: Data(header.suffix(16)), iterations: UInt32(iterations))
        var sequence: UInt64 = 0
        let raw = try open(from: input, key: key, header: header, sequence: &sequence, limit: manifestLimit)
        let manifest = try decoder().decode(BackupManifest.self, from: raw)
        guard manifest.formatVersion == 1, manifest.attachments.count <= 100_000 else { throw BackupArchiveError.invalid("Die Sicherung benötigt eine neuere App-Version oder enthält zu viele Anhänge.") }
        var paths = Set<String>(), total: UInt64 = 0
        for attachment in manifest.attachments {
            try validatePath(attachment.path)
            let (sum, overflow) = total.addingReportingOverflow(attachment.bytes)
            guard !overflow, paths.insert(attachment.path).inserted, attachment.sha256.count == 32 else { throw BackupArchiveError.authentication }
            total = sum
        }
        guard total <= encryptedSize else { throw BackupArchiveError.authentication }
        guard Set(manifest.data.media.map(\.relativePath)).count == manifest.data.media.count else { throw BackupArchiveError.authentication }
        for item in manifest.data.media {
            try validatePath(item.relativePath)
            guard paths.contains(item.relativePath) == (item.attachmentOmitted != true) else { throw BackupArchiveError.authentication }
        }
        guard paths == Set(manifest.data.media.filter { $0.attachmentOmitted != true }.map(\.relativePath)),
              manifest.omittedAttachments == manifest.data.media.filter({ $0.attachmentOmitted == true }).count else { throw BackupArchiveError.authentication }
        let directory = try privateDirectory()
        var successful = false
        defer { if !successful { try? FileManager.default.removeItem(at: directory) } }
        for folder in ["Media", "Recordings"] { try FileManager.default.createDirectory(at: directory.appendingPathComponent(folder), withIntermediateDirectories: true) }
        var processed: UInt64 = 0
        for attachment in manifest.attachments {
            let target = directory.appendingPathComponent(attachment.path)
            guard FileManager.default.createFile(atPath: target.path, contents: nil) else { throw BackupArchiveError.invalid("Nicht genug Speicherplatz für den Import.") }
            try protect(target)
            let output = try FileHandle(forWritingTo: target); defer { try? output.close() }
            var remaining = attachment.bytes, hash = SHA256()
            while remaining > 0 {
                let bytes = try open(from: input, key: key, header: header, sequence: &sequence, limit: chunkSize)
                guard bytes.count == Int(min(UInt64(chunkSize), remaining)) else { throw BackupArchiveError.authentication }
                try output.write(contentsOf: bytes); hash.update(data: bytes)
                remaining -= UInt64(bytes.count); processed += UInt64(bytes.count)
                progress(Double(processed) / Double(max(1, total)))
            }
            guard Data(hash.finalize()) == attachment.sha256 else { throw BackupArchiveError.authentication }
            try output.synchronize()
        }
        guard try open(from: input, key: key, header: header, sequence: &sequence, limit: chunkSize) == endMarker,
              (try input.read(upToCount: 1))?.isEmpty != false else { throw BackupArchiveError.authentication }
        // Re-encoding through AppData applies all supported data migrations.
        try encoder().encode(manifest.data).write(to: directory.appendingPathComponent("therapy-data.json"), options: .atomic)
        try protect(directory.appendingPathComponent("therapy-data.json"))
        successful = true; progress(1)
        return PreparedBackup(directory: directory, manifest: manifest)
    }

    // Two renames with an on-disk recovery marker. Before installation, all files
    // are prepared on the same volume. A failed rename rolls back immediately;
    // an interrupted process recovers the old directory before AppStore loads.
    static func recoveryURL(_ root: URL) -> URL { root.deletingLastPathComponent().appendingPathComponent(root.lastPathComponent + ".restore-previous") }
    static func cleanAbandonedTransfers(root: URL) {
        let fm = FileManager.default
        for parent in [fm.temporaryDirectory, root.deletingLastPathComponent()] {
            guard let children = try? fm.contentsOfDirectory(at: parent, includingPropertiesForKeys: nil) else { continue }
            for child in children where child.lastPathComponent.hasPrefix("TherapieTransfer-") { try? fm.removeItem(at: child) }
        }
    }
    static func recoverInterruptedRestore(root: URL) throws {
        let fm = FileManager.default, previous = recoveryURL(root)
        if !fm.fileExists(atPath: root.path), fm.fileExists(atPath: previous.path) { try fm.moveItem(at: previous, to: root) }
    }
    static func install(directory: URL, root: URL) throws {
        BackupDiskAccess.lock.lock(); defer { BackupDiskAccess.lock.unlock() }
        let fm = FileManager.default
        // Validate before making any changes to the live directory.
        _ = try decoder().decode(AppData.self, from: Data(contentsOf: directory.appendingPathComponent("therapy-data.json")))
        let staged = try privateDirectory(in: root.deletingLastPathComponent())
        defer { try? fm.removeItem(at: staged) }
        try fm.removeItem(at: staged)
        // Both directories are private locations inside the app's container.
        // Moving avoids a second copy of potentially very large attachments.
        try fm.moveItem(at: directory, to: staged)
        let previous = recoveryURL(root)
        if fm.fileExists(atPath: previous.path) { try fm.removeItem(at: previous) }
        let existed = fm.fileExists(atPath: root.path)
        if existed { try fm.moveItem(at: root, to: previous) }
        do { try fm.moveItem(at: staged, to: root) }
        catch {
            if existed { try fm.moveItem(at: previous, to: root) }
            throw error
        }
        // Keep one protected recovery copy; it is removed by a later successful import or reset.
    }
}
