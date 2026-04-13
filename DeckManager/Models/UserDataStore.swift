import Foundation

/// Persistent storage for user data: favorites, synergies, and saved decks.
/// All data is stored as JSON files in ~/Library/Application Support/DeckManager/
/// and loaded on app launch.
class UserDataStore: ObservableObject {
    static let shared = UserDataStore()

    // MARK: - Published state

    @Published var favorites: Set<String> = []        // card names
    @Published var heroFavorites: Set<String> = []    // hero card names
    @Published var synergies: [Synergy] = []
    @Published var savedDecks: [SavedDeck] = []
    @Published var appearanceMode: String = "dark"     // "system", "light", "dark"
    @Published var playerName: String? = nil            // user's chosen display name
    @Published var cardSize: Double = 150               // grid card width (80–250 range)
    @Published var fontScale: Double = 1.0               // font size multiplier (0.8–1.5)

    // MARK: - Storage paths

    private let dataDir: URL = {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let newDir = appSupport.appendingPathComponent("DeckManager").appendingPathComponent("UserData")

        // Migrate from old directories if they exist
        for oldName in ["DeckCoach", "DeckRipperHS"] {
            let oldDir = appSupport.appendingPathComponent(oldName).appendingPathComponent("UserData")
            if FileManager.default.fileExists(atPath: oldDir.path) && !FileManager.default.fileExists(atPath: newDir.path) {
                try? FileManager.default.createDirectory(at: newDir.deletingLastPathComponent(), withIntermediateDirectories: true)
                try? FileManager.default.moveItem(at: oldDir, to: newDir)
                try? FileManager.default.removeItem(at: appSupport.appendingPathComponent(oldName))
                break
            }
        }
        if !FileManager.default.fileExists(atPath: newDir.path) {
        } else {
            try? FileManager.default.createDirectory(at: newDir, withIntermediateDirectories: true)
        }
        return newDir
    }()

    private var favoritesFile: URL { dataDir.appendingPathComponent("favorites.json") }
    private var heroFavoritesFile: URL { dataDir.appendingPathComponent("hero_favorites.json") }
    private var playerNameFile: URL { dataDir.appendingPathComponent("player_name.json") }
    private var synergiesFile: URL { dataDir.appendingPathComponent("synergies.json") }
    private var decksFile: URL { dataDir.appendingPathComponent("decks.json") }
    private var appearanceFile: URL { dataDir.appendingPathComponent("appearance.json") }

    // MARK: - Init

    init() {
        loadAll()
        loadAppearance()
        loadPlayerName()
    }

    // MARK: - Favorites

    func isFavorite(_ cardName: String) -> Bool {
        favorites.contains(cardName)
    }

    func toggleFavorite(_ cardName: String) {
        if favorites.contains(cardName) {
            favorites.remove(cardName)
        } else {
            favorites.insert(cardName)
        }
        saveFavorites()
    }

    func addFavorite(_ cardName: String) {
        favorites.insert(cardName)
        saveFavorites()
    }

    func removeFavorite(_ cardName: String) {
        favorites.remove(cardName)
        saveFavorites()
    }

    /// Get favorites grouped by class, given a card database
    func favoritesByClass(database: CardDatabase) -> [String: [HSCard]] {
        var result: [String: [HSCard]] = [:]
        for cardName in favorites {
            // Find the card in the database
            if let card = database.cards.first(where: { $0.name == cardName }) {
                result[card.safeCardClass, default: []].append(card)
            }
        }
        // Sort each class's cards by name
        for key in result.keys {
            result[key]?.sort { $0.name < $1.name }
        }
        return result
    }

    // MARK: - Hero Favorites

    func isHeroFavorite(_ cardName: String) -> Bool {
        heroFavorites.contains(cardName)
    }

    func toggleHeroFavorite(_ cardName: String) {
        if heroFavorites.contains(cardName) {
            heroFavorites.remove(cardName)
        } else {
            heroFavorites.insert(cardName)
        }
        saveHeroFavorites()
    }

    // MARK: - Player Name

    func setPlayerName(_ name: String?) {
        playerName = name
        savePlayerName()
    }

    private func loadPlayerName() {
        guard let data = try? Data(contentsOf: playerNameFile),
              let decoded = try? JSONDecoder().decode(String?.self, from: data) else { return }
        playerName = decoded
    }

    private func savePlayerName() {
        guard let data = try? JSONEncoder().encode(playerName) else { return }
        try? data.write(to: playerNameFile, options: .atomic)
    }

    // MARK: - Synergies

    func createSynergy(name: String, heroClass: String, cardNames: [String] = []) -> Synergy {
        let synergy = Synergy(
            id: UUID().uuidString,
            name: name,
            heroClass: heroClass,
            cardNames: cardNames,
            createdAt: Date()
        )
        synergies.append(synergy)
        saveSynergies()
        return synergy
    }

    func updateSynergy(_ synergy: Synergy) {
        if let idx = synergies.firstIndex(where: { $0.id == synergy.id }) {
            synergies[idx] = synergy
            saveSynergies()
        }
    }

    func deleteSynergy(id: String) {
        synergies.removeAll { $0.id == id }
        saveSynergies()
    }

    func addCardToSynergy(synergyId: String, cardName: String) {
        if let idx = synergies.firstIndex(where: { $0.id == synergyId }) {
            if !synergies[idx].cardNames.contains(cardName) {
                synergies[idx].cardNames.append(cardName)
                saveSynergies()
            }
        }
    }

    func removeCardFromSynergy(synergyId: String, cardName: String) {
        if let idx = synergies.firstIndex(where: { $0.id == synergyId }) {
            synergies[idx].cardNames.removeAll { $0 == cardName }
            saveSynergies()
        }
    }

    /// Get synergies for a specific class (also includes Neutral synergies since those cards fit any deck)
    func synergies(forClass heroClass: String) -> [Synergy] {
        synergies.filter { $0.heroClass == heroClass || $0.heroClass == "NEUTRAL" }
    }

    // MARK: - Saved Decks

    func saveDeck(_ deck: SavedDeck) {
        if let idx = savedDecks.firstIndex(where: { $0.id == deck.id }) {
            savedDecks[idx] = deck
        } else {
            savedDecks.append(deck)
        }
        saveDecks()
    }

    func deleteDeck(id: String) {
        savedDecks.removeAll { $0.id == id }
        saveDecks()
    }

    func renameDeck(id: String, name: String) {
        if let idx = savedDecks.firstIndex(where: { $0.id == id }) {
            savedDecks[idx].name = name
            saveDecks()
        }
    }

    // MARK: - Persistence

    private func loadAll() {
        loadFavorites()
        loadHeroFavorites()
        loadSynergies()
        loadDecks()
    }

    private func loadFavorites() {
        guard let data = try? Data(contentsOf: favoritesFile),
              let decoded = try? JSONDecoder().decode(Set<String>.self, from: data) else { return }
        favorites = decoded
    }

    private func loadHeroFavorites() {
        guard let data = try? Data(contentsOf: heroFavoritesFile),
              let decoded = try? JSONDecoder().decode(Set<String>.self, from: data) else { return }
        heroFavorites = decoded
    }

    private func saveHeroFavorites() {
        guard let data = try? JSONEncoder().encode(heroFavorites) else { return }
        try? data.write(to: heroFavoritesFile, options: .atomic)
    }

    private func saveFavorites() {
        guard let data = try? JSONEncoder().encode(favorites) else { return }
        try? data.write(to: favoritesFile, options: .atomic)
    }

    private func loadSynergies() {
        guard let data = try? Data(contentsOf: synergiesFile),
              let decoded = try? JSONDecoder().decode([Synergy].self, from: data) else { return }
        synergies = decoded
    }

    private func saveSynergies() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        guard let data = try? encoder.encode(synergies) else { return }
        try? data.write(to: synergiesFile, options: .atomic)
    }

    private func loadDecks() {
        guard let data = try? Data(contentsOf: decksFile),
              let decoded = try? JSONDecoder().decode([SavedDeck].self, from: data) else { return }
        savedDecks = decoded
    }

    private func saveDecks() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        guard let data = try? encoder.encode(savedDecks) else { return }
        try? data.write(to: decksFile, options: .atomic)
    }

    // MARK: - Appearance

    private struct AppearanceSettings: Codable {
        var appearanceMode: String
        var windowStyle: String?  // legacy, ignored
        var cardSize: Double?
        var fontScale: Double?
    }

    private func loadAppearance() {
        guard let data = try? Data(contentsOf: appearanceFile),
              let decoded = try? JSONDecoder().decode(AppearanceSettings.self, from: data) else { return }
        appearanceMode = decoded.appearanceMode
        if let size = decoded.cardSize { cardSize = size }
        if let scale = decoded.fontScale { fontScale = scale }
        FontManager.scale = fontScale
    }

    func saveAppearance() {
        FontManager.scale = fontScale
        let settings = AppearanceSettings(appearanceMode: appearanceMode, cardSize: cardSize, fontScale: fontScale)
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        guard let data = try? encoder.encode(settings) else { return }
        try? data.write(to: appearanceFile, options: .atomic)
        NotificationCenter.default.post(name: WindowAppearance.reapplyNotification, object: nil)
    }
}

// MARK: - Data Models

struct Synergy: Codable, Identifiable {
    let id: String
    var name: String
    var heroClass: String       // single class (e.g., "MAGE") — cards can be this class or NEUTRAL
    var cardNames: [String]     // card names in this synergy
    let createdAt: Date
}

struct SavedDeck: Codable, Identifiable {
    let id: String
    var name: String
    var heroClass: String
    var format: String          // "standard" or "wild"
    var cards: [DeckSlot]       // the cards in the deck
    let createdAt: Date
    var updatedAt: Date

    var deckSize: Int {
        // Check for deck size modifiers
        let hasRenathal = cards.contains { $0.cardName == "Prince Renathal" }
        return hasRenathal ? 40 : 30
    }

    var totalCards: Int {
        cards.reduce(0) { $0 + $1.count }
    }

    var isComplete: Bool {
        totalCards == deckSize
    }

    /// True if the deck contains any Highlander card (no duplicates requirement)
    var hasHighlanderCard: Bool {
        let db = CardDatabase.shared
        return cards.contains { slot in
            db.card(byId: slot.cardId)?.isHighlander == true
        }
    }

    /// True if the deck has any card with count > 1
    var hasDuplicates: Bool {
        cards.contains { $0.count > 1 }
    }
}

struct DeckSlot: Codable {
    var cardName: String
    var cardId: String          // HearthstoneJSON string ID (e.g., "EX1_055")
    var count: Int              // 1 or 2 (1 for legendaries)
    var source: SlotSource      // why this card was added
}

enum SlotSource: String, Codable {
    case favorite               // added from favorites (heart icon)
    case synergy                // added from a synergy (lightning bolt icon)
    case manual                 // added manually by the user
}

/// Cards that modify deck construction size.
/// Data-driven so we can add future cards without code changes.
struct DeckSizeModifier {
    let cardName: String
    let modifiedSize: Int

    static let all: [DeckSizeModifier] = [
        DeckSizeModifier(cardName: "Prince Renathal", modifiedSize: 40),
        // Add future deck size modifiers here
    ]

    static func deckSize(for cardNames: [String]) -> Int {
        for modifier in all {
            if cardNames.contains(modifier.cardName) {
                return modifier.modifiedSize
            }
        }
        return 30
    }
}
