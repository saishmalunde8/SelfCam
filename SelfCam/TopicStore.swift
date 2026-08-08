import Foundation

/// Owns the topic deck (`topics.json`) and drives the note's prev/shuffle/next.
///
/// Draw rule ("no repeats until the deck is exhausted"): among non-retired
/// topics (matching the category filter, if any), pick randomly from whichever
/// have the *lowest* `timesUsed` — so every topic gets shown once before any
/// repeats, and the order is randomized within each round.
///
/// `history`/`position` back prev/next: next() only draws a fresh topic when
/// you're at the end of history (otherwise it just re-shows what prev() backed
/// past); shuffle() always forces a fresh draw, discarding forward history.
@MainActor
final class TopicStore: ObservableObject {
    @Published private(set) var current: Topic?
    @Published var categoryFilter: TopicCategory? = TopicStore.loadFilter() {
        didSet {
            guard oldValue != categoryFilter else { return }
            UserDefaults.standard.set(categoryFilter?.rawValue, forKey: Self.filterKey)
            // Take effect immediately: if the shown topic doesn't match the new
            // filter, swap it — otherwise the filter looks like it does nothing.
            if let filter = categoryFilter, let cur = current, cur.category != filter {
                shuffle()
            }
        }
    }

    private var all: [Topic] = []
    private var history: [Topic] = []
    private var position = -1

    private static let filterKey = "noteCategoryFilter"
    private static func loadFilter() -> TopicCategory? {
        guard let raw = UserDefaults.standard.string(forKey: filterKey) else { return nil }
        return TopicCategory(rawValue: raw)
    }

    init() {
        load()
    }

    /// Draws the first topic on demand — the note calls this when it appears.
    /// (Drawing in `init` burned a topic's `timesUsed` on every app launch,
    /// because the store is created eagerly at startup.)
    func ensureCurrent() {
        guard current == nil, let topic = draw() else { return }
        history.append(topic)
        position = 0
        current = topic
    }

    var canGoBack: Bool { position > 0 }

    func next() {
        if position < history.count - 1 {
            position += 1
            current = history[position]
        } else if let topic = draw() {
            history.append(topic)
            position = history.count - 1
            current = topic
        }
    }

    func prev() {
        guard canGoBack else { return }
        position -= 1
        current = history[position]
    }

    /// Always forces a fresh draw, dropping any forward history past this point.
    func shuffle() {
        guard let topic = draw() else { return }
        history.removeSubrange((position + 1)...)
        history.append(topic)
        position = history.count - 1
        current = topic
    }

    // MARK: - Drawing

    private func draw() -> Topic? {
        var pool = all.filter { !$0.retired && (categoryFilter == nil || $0.category == categoryFilter) }
        guard !pool.isEmpty else { return nil }
        // Never immediately repeat the current topic when alternatives exist, so
        // Next always visibly advances and the deck loops endlessly.
        if pool.count > 1, let currentID = current?.id {
            pool.removeAll { $0.id == currentID }
        }
        let minUsed = pool.map(\.timesUsed).min() ?? 0
        let leastUsed = pool.filter { $0.timesUsed == minUsed }
        guard var chosen = leastUsed.randomElement() else { return nil }

        chosen.timesUsed += 1
        chosen.lastUsedAt = Date()
        if let i = all.firstIndex(where: { $0.id == chosen.id }) { all[i] = chosen }
        save()
        return chosen
    }

    // MARK: - Persistence

    /// Reads `topics.json`, seeding it from the bundled deck on first run. Once
    /// written, the file on disk is the source of truth — so usage counts stick,
    /// and a deck you've hand-edited is never silently overwritten by the seed.
    private func load() {
        if let data = try? Data(contentsOf: LocalPaths.topicsFile),
           let file = try? SidecarCodec.decoder.decode(TopicsFile.self, from: data) {
            all = file.topics
            return
        }
        guard let url = Bundle.main.url(forResource: "SeedTopics", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let file = try? SidecarCodec.decoder.decode(TopicsFile.self, from: data)
        else { all = []; return }
        all = file.topics
        LocalPaths.ensureExists()
        save()
    }

    private func save() {
        let file = TopicsFile(topics: all)
        guard let data = try? SidecarCodec.encoder.encode(file) else { return }
        try? data.write(to: LocalPaths.topicsFile, options: .atomic)
    }
}
