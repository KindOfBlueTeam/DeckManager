import Foundation
import Combine

/// View model for the collection browser.
/// Loads collection from the extracted JSON, resolves cards, handles filtering.
class CollectionViewModel: ObservableObject {
    @Published var ownedCards: [OwnedCard] = []
    @Published var trialCards: [OwnedCard] = []   // all trial-accessible cards (full trial sets)
    @Published var classOwnership: [ClassOwnership] = []
    @Published var rawTotalCards: Int = 0              // every copy of every version ever earned
    @Published var scanDate: Date? = nil                 // when the collection was last scanned
    @Published var isLoaded = false

    // Filters
    @Published var searchText = ""
    @Published var selectedClass = "ALL"
    @Published var selectedRarity = "ALL"
    @Published var selectedCost = "ALL"
    @Published var selectedFormat = "ALL"   // "ALL", "STANDARD", "WILD"
    @Published var showHeroesOnly = false
    @Published var showFavoritesOnly = false
    @Published var showUnownedOnly = false
    @Published var unownedClass = "ALL"
    @Published var showUnownedHeroes = false
    @Published var unownedHeroClass = "ALL"
    @Published var showOwnedHeroes = false
    @Published var ownedHeroClass = "ALL"
    @Published var showFavoriteHeroes = false
    @Published var showTrialOnly = false
    @Published var trialClass = "ALL"
    @Published var showOwnedCards = false
    @Published var ownedCardClass = "ALL"
    // Skins vs Hero Cards distinction
    @Published var showOwnedSkins = false
    @Published var ownedSkinClass = "ALL"
    @Published var showUnownedSkins = false
    @Published var unownedSkinClass = "ALL"
    @Published var showOwnedHeroCards = false
    @Published var ownedHeroCardClass = "ALL"
    @Published var showUnownedHeroCards = false
    @Published var unownedHeroCardClass = "ALL"

    private let database = CardDatabase.shared

    /// Load collection from the extracted JSON file
    func loadCollection(from path: String) async {
        print("[CollectionVM] Loading from \(path)")

        // Load card database first
        await database.loadCards()
        print("[CollectionVM] Card database loaded: \(database.cards.count) cards")

        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else {
            print("[CollectionVM] Could not read collection file at \(path)")
            return
        }
        print("[CollectionVM] Read \(data.count) bytes from file")

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase

        guard let collection = try? decoder.decode(CollectionData.self, from: data) else {
            print("[CollectionVM] Could not decode collection JSON")
            // Try to see the error
            do {
                let _ = try decoder.decode(CollectionData.self, from: data)
            } catch {
                print("[CollectionVM] Decode error: \(error)")
            }
            return
        }
        print("[CollectionVM] Decoded: \(collection.cards.count) agent cards, \(collection.uniqueEntries) unique")

        // Parse scan timestamp
        let isoFormatter = ISO8601DateFormatter()
        let parsedDate = isoFormatter.date(from: collection.timestamp)

        // Sum raw counts (every copy of every version — the "all time" total)
        let rawTotal = collection.cards.reduce(0) { $0 + $1.count }

        // Detect grant batch via timestamp grouping
        let grantCardIds = Self.detectTrialCardIds(collection.cards, database: database)
        print("[CollectionVM] Detected \(grantCardIds.count) grant card IDs in batch")

        // Resolve owned collection (marks grant-batch cards as trial)
        let resolved = database.resolveCollection(collection.cards, trialCardIds: grantCardIds)
        let ownedNames = Set(resolved.map { $0.card.name })

        // Inject full trial set cards that aren't already owned
        // Trial sets grant access to ALL cards in those sets, even if not in NetCacheCollection
        var trialInjected: [OwnedCard] = []
        for card in database.cards {
            guard let set = card.set, Self.trialSets.contains(set) else { continue }
            guard card.safeType != "HERO" else { continue }
            guard !ownedNames.contains(card.name) else { continue }
            trialInjected.append(OwnedCard(
                card: card,
                normalCount: 2,
                goldenCount: 0,
                hasGolden: false,
                isTrial: true
            ))
        }
        // Deduplicate injected by name
        var seenNames = Set<String>()
        trialInjected = trialInjected.filter { seenNames.insert($0.card.name).inserted }

        print("[CollectionVM] Injected \(trialInjected.count) trial set cards not in collection")

        let allCards = resolved + trialInjected
        let ownership = database.calculateClassOwnership(owned: allCards)
        let trials = allCards.filter { $0.isTrial }
        print("[CollectionVM] Total \(allCards.count) cards (\(trials.count) trial)")

        await MainActor.run {
            self.ownedCards = allCards.sorted { $0.card.name < $1.card.name }
            self.trialCards = trials.sorted { $0.card.name < $1.card.name }
            self.classOwnership = ownership
            self.rawTotalCards = rawTotal
            self.scanDate = parsedDate
            self.isLoaded = true
        }
    }

    /// Filtered cards based on current filter state
    /// Cards the user does NOT own (non-hero), deduplicated by name
    var unownedCards: [OwnedCard] {
        unownedFiltered(filter: .nonHero)
    }

    /// Unowned hero skins (cosmetic, not playable)
    var unownedSkins: [OwnedCard] {
        unownedFiltered(filter: .skins)
    }

    /// Unowned playable hero cards
    var unownedHeroCards: [OwnedCard] {
        unownedFiltered(filter: .heroCards)
    }

    private enum HeroFilter { case nonHero, skins, heroCards }

    private func unownedFiltered(filter: HeroFilter) -> [OwnedCard] {
        let ownedNames = Set(ownedCards.map { $0.card.name })
        let allCards = database.cards

        var seen = Set<String>()
        var results: [OwnedCard] = []

        for card in allCards {
            let dominated: Bool
            switch filter {
            case .nonHero:   dominated = card.safeType != "HERO"
            case .skins:     dominated = card.isHeroSkin
            case .heroCards:  dominated = card.isPlayableHero
            }
            guard dominated else { continue }
            guard !ownedNames.contains(card.name) else { continue }
            guard !seen.contains(card.name) else { continue }
            seen.insert(card.name)
            results.append(OwnedCard(card: card, normalCount: 0, goldenCount: 0, hasGolden: false))
        }

        return results
    }

    var filteredCards: [OwnedCard] {
        var cards: [OwnedCard]

        if showOwnedCards {
            // Owned cards mode (non-hero)
            cards = ownedCards.filter { $0.card.safeType != "HERO" }
            if ownedCardClass != "ALL" {
                cards = cards.filter { $0.card.safeCardClass == ownedCardClass }
            }
        } else if showTrialOnly {
            // Trial cards mode
            cards = trialCards
            if trialClass != "ALL" {
                cards = cards.filter { $0.card.safeCardClass == trialClass }
            }
        } else if showFavoriteHeroes {
            // Favorite heroes mode (skins only — cosmetic favorites)
            let store = UserDataStore.shared
            cards = ownedCards.filter { $0.card.isHeroSkin && store.isHeroFavorite($0.card.name) }
        } else if showOwnedSkins {
            // Owned skins mode
            cards = ownedCards.filter { $0.card.isHeroSkin }
            if ownedSkinClass != "ALL" {
                cards = cards.filter { $0.card.safeCardClass == ownedSkinClass }
            }
        } else if showUnownedSkins {
            // Unowned skins mode
            cards = unownedSkins
            if unownedSkinClass != "ALL" {
                cards = cards.filter { $0.card.safeCardClass == unownedSkinClass }
            }
        } else if showOwnedHeroCards {
            // Owned playable hero cards
            cards = ownedCards.filter { $0.card.isPlayableHero }
            if ownedHeroCardClass != "ALL" {
                cards = cards.filter { $0.card.safeCardClass == ownedHeroCardClass }
            }
        } else if showUnownedHeroCards {
            // Unowned playable hero cards
            cards = unownedHeroCards
            if unownedHeroCardClass != "ALL" {
                cards = cards.filter { $0.card.safeCardClass == unownedHeroCardClass }
            }
        } else if showUnownedOnly {
            // Unowned cards mode (non-heroes)
            cards = unownedCards
            if unownedClass != "ALL" {
                cards = cards.filter { $0.card.safeCardClass == unownedClass }
            }
        } else {
            cards = ownedCards

            // Separate heroes from regular cards
            if showHeroesOnly {
                cards = cards.filter { $0.card.safeType == "HERO" }
            } else {
                cards = cards.filter { $0.card.safeType != "HERO" }
            }

            if selectedClass != "ALL" {
                cards = cards.filter { $0.card.safeCardClass == selectedClass }
            }

            if showFavoritesOnly {
                let store = UserDataStore.shared
                if showHeroesOnly {
                    cards = cards.filter { store.isHeroFavorite($0.card.name) }
                } else {
                    cards = cards.filter { store.isFavorite($0.card.name) }
                }
            }
        }

        if selectedRarity != "ALL" {
            cards = cards.filter { $0.card.safeRarity == selectedRarity }
        }

        if selectedCost != "ALL" {
            if selectedCost == "7+" {
                cards = cards.filter { $0.card.safeCost >= 7 }
            } else if let cost = Int(selectedCost) {
                cards = cards.filter { $0.card.safeCost == cost }
            }
        }

        // Format filter (Standard/Wild)
        if selectedFormat == "STANDARD" {
            cards = cards.filter { CardFormats.isStandard($0.card) }
        } else if selectedFormat == "WILD" {
            cards = cards.filter { !CardFormats.isStandard($0.card) }
        }

        if !searchText.isEmpty {
            let terms = searchText.lowercased().split(separator: " ")
            cards = cards.filter { oc in
                let searchable = "\(oc.card.name) \(oc.card.text ?? "") \(oc.card.race ?? "")".lowercased()
                return terms.allSatisfy { searchable.contains($0) }
            }
        }

        return cards.sorted {
            if $0.card.safeCost != $1.card.safeCost { return $0.card.safeCost < $1.card.safeCost }
            return $0.card.name < $1.card.name
        }
    }

    var filteredCount: Int { filteredCards.count }
    /// Unique card names (1 per card regardless of copies/versions)
    var uniqueCount: Int { Set(ownedCards.map { $0.card.name }).count }
    /// Available copies (capped counts — what you can actually pick from)
    var availableCount: Int { ownedCards.reduce(0) { $0 + $1.totalCount } }
    /// Raw total earned all time (every copy, every version, every printing)
    var totalCount: Int { rawTotalCards }
    var trialCount: Int { trialCards.count }

    // MARK: - Trial Card Detection

    /// Current trial sets (as of Cataclysm expansion, March 2026).
    /// Players get free temporary access to ALL cards in these sets.
    /// Update this list when trial sets rotate with new expansions.
    static let trialSets: Set<String> = [
        "EMERALD_DREAM", "THE_LOST_CITY"
    ]

    /// Detect granted/trial card IDs by finding the largest single-timestamp group.
    /// These are cards the server grants in bulk (Core Set rotation, trial access, etc.)
    /// — as opposed to cards the player earned through packs, adventures, or rewards.
    ///
    /// The largest timestamp group represents all cards granted at session start.
    /// All cards in this group are tagged as "trial" (temporary grants that may rotate).
    static func detectTrialCardIds(_ cards: [CollectionCard], database: CardDatabase) -> Set<String> {
        // Group cards by timestamp
        var timestampGroups: [UInt64: [CollectionCard]] = [:]
        for card in cards {
            let ts = card.acquisitionTimestamp ?? 0
            guard ts > 0 else { continue }
            timestampGroups[ts, default: []].append(card)
        }

        // Find the largest timestamp group (the server grant batch)
        guard let largestGroup = timestampGroups.max(by: { $0.value.count < $1.value.count }) else {
            return []
        }

        // Only flag if the group is significantly large (>100 cards = clearly a batch grant)
        guard largestGroup.value.count > 100 else { return [] }

        print("[TrialDetection] Largest timestamp group: \(largestGroup.value.count) cards")

        // Exclude hero cards and hero skins — those are permanent defaults, not trials
        let excludedSets: Set<String> = ["HERO_SKINS"]

        var trialIds: Set<String> = []
        for card in largestGroup.value {
            guard let hsCard = database.card(byId: card.cardId) else { continue }
            if hsCard.safeType == "HERO" { continue }
            if let set = hsCard.set, excludedSets.contains(set) { continue }
            trialIds.insert(card.cardId)
        }

        return trialIds
    }
}
