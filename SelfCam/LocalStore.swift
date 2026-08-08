import Foundation

// MARK: - Local storage for table-topic practice
//
// Everything Table Topics produces lives under ~/Movies/SelfCam: the recorded
// clips (each with a JSON sidecar) and the topic deck itself. Snaps keep their
// own home in ~/Pictures/SelfCam — see `SnapStore`.
//
// The on-disk formats are plain, sorted-key JSON so the folder stays readable
// and hand-editable: a deck you can tweak in a text editor, clips you can move
// around in Finder.

/// Broad theme of a table topic. Raw values are the on-disk contract — they must
/// match the `category` values in the bundled `SeedTopics.json`.
enum TopicCategory: String, Codable, CaseIterable {
    case personal, abstract, professional, hypothetical, storytelling
    case business, debate, brainteasers, ethics, future
    case hotTakes, popCulture, problemSolving, rolePlay, wouldYouRather

    var label: String {
        switch self {
        case .personal:       return "Personal"
        case .abstract:       return "Abstract"
        case .professional:   return "Professional"
        case .hypothetical:   return "Hypothetical"
        case .storytelling:   return "Storytelling"
        case .business:       return "Business"
        case .debate:         return "Debate"
        case .brainteasers:   return "Brainteasers"
        case .ethics:         return "Ethical Dilemmas"
        case .future:         return "Future"
        case .hotTakes:       return "Hot Takes"
        case .popCulture:     return "Pop Culture"
        case .problemSolving: return "Problem Solving"
        case .rolePlay:       return "Role Play"
        case .wouldYouRather: return "Would You Rather"
        }
    }
}

/// One prompt in the deck. `timesUsed` / `lastUsedAt` back the no-repeat
/// rotation in `TopicStore` — they're the only fields that change after seeding.
struct Topic: Codable, Identifiable, Equatable {
    let id: String
    var text: String
    var category: TopicCategory
    var timesUsed: Int
    var lastUsedAt: Date?
    var retired: Bool
}

/// On-disk shape of `topics.json`.
struct TopicsFile: Codable {
    var schemaVersion: Int = 1
    var topics: [Topic]
}

/// Durable metadata written as a `.json` sidecar beside each recorded `.mov`.
/// The movie's path is implied by the sidecar's own location, so it isn't stored.
struct RecordingSidecar: Codable {
    var schemaVersion: Int = 1
    var id: String
    /// Always `"table-topic"` today; kept as a field so the format can grow
    /// without breaking clips already on disk.
    var type: String
    var title: String
    var topicText: String?
    var createdAt: Date
    var duration: Double
}

/// (De)serialization config: ISO-8601 dates, pretty-printed with sorted keys, so
/// `topics.json` and the sidecars stay readable and diff-friendly.
enum SidecarCodec {
    static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }()
    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
}

/// Canonical locations for everything Table Topics writes.
enum LocalPaths {
    static var root: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Movies/SelfCam", isDirectory: true)
    }

    static var recordings: URL { root.appendingPathComponent("Recordings", isDirectory: true) }
    /// In-progress captures land here; `ClipWriter` moves them into `Recordings`
    /// once they're finalized, so a half-written file never looks like a clip.
    static var tmp:        URL { root.appendingPathComponent(".tmp", isDirectory: true) }
    static var topicsFile: URL { root.appendingPathComponent("topics.json") }

    static func ensureExists() {
        let fm = FileManager.default
        for dir in [root, recordings, tmp] {
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
    }

    /// Deletes stale in-progress recordings left behind by crashes or quits —
    /// nothing else ever cleans `.tmp`. Recent files are spared so an actively
    /// recording take is never yanked out from under the capture session.
    static func sweepStaleTmp(olderThanHours hours: Double = 24) {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(
            at: tmp, includingPropertiesForKeys: [.contentModificationDateKey]
        ) else { return }
        let cutoff = Date().addingTimeInterval(-hours * 3600)
        for file in files {
            let modified = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?
                .contentModificationDate ?? .distantPast
            if modified < cutoff { try? fm.removeItem(at: file) }
        }
    }
}
