import Foundation

/// Fetches and caches the HearthstoneJSON card database.
/// Used to resolve agent card IDs to full card data with images.
class CardDatabase: ObservableObject {
    static let shared = CardDatabase()

    @Published var cards: [HSCard] = []
    @Published var isLoading = false
    @Published var error: String?

    private var cardById: [String: HSCard] = [:]
    private var cardByDbfId: [Int: HSCard] = [:]
    private var cardsByClass: [String: [HSCard]] = [:]

    private let cacheUrl: URL = {
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
            .appendingPathComponent("DeckManager")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("cards.json")
    }()

    private let apiUrl = URL(string: "https://api.hearthstonejson.com/v1/latest/enUS/cards.collectible.json")!

    /// Load cards from cache or fetch from API
    func loadCards() async {
        await MainActor.run { isLoading = true; error = nil }

        // Try cache first (valid for 7 days)
        if let cached = loadFromCache() {
            await processCards(cached)
            await MainActor.run { isLoading = false }
            return
        }

        // Fetch from API
        do {
            let (data, _) = try await URLSession.shared.data(from: apiUrl)
            let decoded = try JSONDecoder().decode([HSCard].self, from: data)

            // Save to cache
            try? data.write(to: cacheUrl)

            await processCards(decoded)
        } catch {
            await MainActor.run {
                self.error = "Failed to load card database: \(error.localizedDescription)"
            }
        }

        await MainActor.run { isLoading = false }
    }

    private func processCards(_ cards: [HSCard]) async {
        var byId: [String: HSCard] = [:]
        var byDbfId: [Int: HSCard] = [:]
        var byClass: [String: [HSCard]] = [:]

        for card in cards {
            byId[card.id] = card
            byDbfId[card.dbfId] = card
            byClass[card.safeCardClass, default: []].append(card)
        }

        await MainActor.run {
            self.cards = cards
            self.cardById = byId
            self.cardByDbfId = byDbfId
            self.cardsByClass = byClass
        }
    }

    /// Look up a card by its string ID (e.g., "EX1_055")
    func card(byId id: String) -> HSCard? {
        cardById[id]
    }

    /// Look up a card by its dbfId (integer ID used in deck codes)
    func card(byDbfId dbfId: Int) -> HSCard? {
        cardByDbfId[dbfId]
    }

    /// Get all cards for a class
    func cards(forClass cls: String) -> [HSCard] {
        cardsByClass[cls] ?? []
    }

    /// Resolve an agent collection to OwnedCard objects.
    /// trialCardIds: set of card IDs identified as trial/Core grants (from timestamp analysis).
    /// A card is trial only if every entry for that card name is in the trial set.
    func resolveCollection(_ agentCards: [CollectionCard], trialCardIds: Set<String> = []) -> [OwnedCard] {
        // Group by card name to merge normal + golden
        var byName: [String: (card: HSCard, normal: Int, golden: Int, allTrial: Bool, anyNonTrial: Bool)] = [:]

        for ac in agentCards {
            guard let card = cardById[ac.cardId] else { continue }
            let key = card.name
            var entry = byName[key] ?? (card: card, normal: 0, golden: 0, allTrial: true, anyNonTrial: false)
            if ac.premium == 1 {
                entry.golden += ac.count
            } else {
                entry.normal += ac.count
            }
            if trialCardIds.contains(ac.cardId) {
                // This entry is a trial grant
            } else {
                entry.anyNonTrial = true
            }
            entry.card = card
            byName[key] = entry
        }

        return byName.values.map { entry in
            // Cap counts — a card appears in multiple sets but you can only use
            // 2 copies in a deck (1 for legendaries). Show the usable count.
            let maxCopies = entry.card.safeRarity == "LEGENDARY" ? 1 : 2
            let normal = min(entry.normal, maxCopies)
            let golden = min(entry.golden, maxCopies)
            return OwnedCard(
                card: entry.card,
                normalCount: normal,
                goldenCount: golden,
                hasGolden: entry.golden > 0,
                isTrial: !entry.anyNonTrial && !trialCardIds.isEmpty
            )
        }
    }

    /// Calculate per-class ownership (by unique card name)
    func calculateClassOwnership(owned: [OwnedCard]) -> [ClassOwnership] {
        // Total unique card names per class
        var totalByClass: [String: Set<String>] = [:]
        for card in cards {
            let cls = card.safeCardClass
            guard !cls.isEmpty else { continue }
            totalByClass[cls, default: Set()].insert(card.name)
        }

        // Owned unique card names per class
        var ownedByClass: [String: Set<String>] = [:]
        for oc in owned {
            ownedByClass[oc.card.safeCardClass, default: Set()].insert(oc.card.name)
        }

        var results: [ClassOwnership] = []

        for cls in HS_CLASSES {
            let total = totalByClass[cls] ?? Set()
            let owned = ownedByClass[cls] ?? Set()
            results.append(ClassOwnership(
                className: cls,
                ownedUnique: owned.count,
                totalUnique: total.count
            ))
        }

        // Add Neutral
        let neutralTotal = totalByClass["NEUTRAL"] ?? Set()
        let neutralOwned = ownedByClass["NEUTRAL"] ?? Set()
        results.append(ClassOwnership(
            className: "NEUTRAL",
            ownedUnique: neutralOwned.count,
            totalUnique: neutralTotal.count
        ))

        return results
    }

    // MARK: - Cache

    private func loadFromCache() -> [HSCard]? {
        guard FileManager.default.fileExists(atPath: cacheUrl.path) else { return nil }

        // Check age (7 days)
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: cacheUrl.path),
              let modified = attrs[.modificationDate] as? Date,
              Date().timeIntervalSince(modified) < 7 * 24 * 60 * 60 else {
            return nil
        }

        guard let data = try? Data(contentsOf: cacheUrl),
              let cards = try? JSONDecoder().decode([HSCard].self, from: data) else {
            return nil
        }

        return cards
    }
}
