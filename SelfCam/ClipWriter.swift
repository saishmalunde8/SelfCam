import Foundation

/// Commits a finished recording into `~/Movies/SelfCam/Recordings`. Pure and
/// camera-free, so it can be reasoned about (and tested) without hardware.
///
/// Ordering matters: the `.mov` is moved into place first, then the `.json`
/// sidecar is written **last**. Anything reading the folder treats a clip as
/// existing only once its sidecar does, so a partially-written take never shows
/// up as a real recording.
enum ClipWriter {
    /// The one kind of clip SelfCam records. Stored in the sidecar and used as
    /// the filename slug.
    static let tableTopicType = "table-topic"

    /// Moves `tmpMovURL` into `Recordings/` under a canonical name and writes its
    /// sidecar. Returns the final movie URL.
    static func commit(tmpMovURL: URL,
                       title: String,
                       topicText: String?,
                       createdAt: Date,
                       duration: Double) throws -> URL {
        LocalPaths.ensureExists()
        let base = uniqueBaseName(topicText: topicText, createdAt: createdAt)
        let movDest  = LocalPaths.recordings.appendingPathComponent(base + ".mov")
        let jsonDest = LocalPaths.recordings.appendingPathComponent(base + ".json")

        try FileManager.default.moveItem(at: tmpMovURL, to: movDest)

        let sidecar = RecordingSidecar(
            id: UUID().uuidString,
            type: tableTopicType,
            title: title,
            topicText: topicText,
            createdAt: createdAt,
            duration: duration
        )
        let data = try SidecarCodec.encoder.encode(sidecar)
        try data.write(to: jsonDest, options: .atomic)   // sidecar last
        return movDest
    }

    /// `2026-08-08_191205_table-topic_courage`, disambiguated with `-1`, `-2`… if
    /// two takes land in the same second.
    static func uniqueBaseName(topicText: String?, createdAt: Date) -> String {
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.dateFormat = "yyyy-MM-dd_HHmmss"
        var base = df.string(from: createdAt) + "_" + tableTopicType
        if let slug = slug(topicText) { base += "_" + slug }

        var candidate = base
        var counter = 1
        while FileManager.default.fileExists(atPath: LocalPaths.recordings.appendingPathComponent(candidate + ".mov").path) {
            candidate = base + "-\(counter)"
            counter += 1
        }
        return candidate
    }

    private static func slug(_ text: String?) -> String? {
        guard let text, !text.isEmpty else { return nil }
        let lower = text.lowercased()
        var out = ""
        var lastDash = false
        for ch in lower {
            if ch.isLetter || ch.isNumber {
                out.append(ch); lastDash = false
            } else if !lastDash {
                out.append("-"); lastDash = true
            }
            if out.count >= 24 { break }
        }
        let trimmed = out.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return trimmed.isEmpty ? nil : trimmed
    }
}
