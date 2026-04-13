import Foundation

/// A card entry from a collection JSON (from DeckRipper or other exporters)
struct CollectionCard: Codable {
    let cardId: String   // e.g. "EX1_055"
    let count: Int
    let premium: Int     // 0=normal, 1=golden
    let acquisitionTimestamp: UInt64?
}

/// Wrapper for a full collection export
struct CollectionData: Codable {
    let agentId: String
    let platform: String
    let timestamp: String
    let cards: [CollectionCard]
    let totalCardsOwned: Int
    let uniqueEntries: Int
}

/// A Hearthstone card from the HearthstoneJSON database
struct HSCard: Codable, Identifiable, Hashable {
    let dbfId: Int
    let id: String          // e.g. "EX1_055"
    let name: String
    let cost: Int?
    let attack: Int?
    let health: Int?
    let durability: Int?
    let text: String?
    let flavor: String?
    let cardClass: String?  // "MAGE", "NEUTRAL", etc. (optional for some hero cards)
    let rarity: String?     // "COMMON", "RARE", "EPIC", "LEGENDARY"
    let set: String?
    let type: String?       // "MINION", "SPELL", "WEAPON"
    let race: String?
    let mechanics: [String]?
    let classes: [String]?  // multi-class cards (e.g., ["DEATHKNIGHT", "ROGUE"])

    /// Card image URL from HearthstoneJSON CDN
    var imageUrl: URL {
        URL(string: "https://art.hearthstonejson.com/v1/render/latest/enUS/256x/\(id).png")!
    }

    var imageUrl512: URL {
        URL(string: "https://art.hearthstonejson.com/v1/render/latest/enUS/512x/\(id).png")!
    }

    /// Safe accessors with defaults
    var safeCost: Int { cost ?? 0 }
    var safeCardClass: String { cardClass ?? classes?.first ?? "NEUTRAL" }

    /// All classes this card belongs to (for multi-class cards)
    var allClasses: [String] {
        if let classes = classes, !classes.isEmpty { return classes }
        if let cls = cardClass, cls != "NEUTRAL" { return [cls] }
        return ["NEUTRAL"]
    }

    /// Check if this card can be used by a specific class
    func belongsToClass(_ cls: String) -> Bool {
        if cls == "NEUTRAL" { return safeCardClass == "NEUTRAL" }
        return allClasses.contains(cls) || safeCardClass == "NEUTRAL"
    }
    var safeRarity: String { rarity ?? "FREE" }
    var safeType: String { type ?? "MINION" }

    /// True if this card requires no duplicate cards in the deck (Highlander/Reno cards)
    var isHighlander: Bool {
        guard let text = cleanText?.lowercased() else { return false }
        return text.contains("no duplicates") && text.contains("deck")
    }

    /// True if this is a cosmetic hero skin (not playable)
    var isHeroSkin: Bool { safeType == "HERO" && set == "HERO_SKINS" }

    /// True if this is a playable hero card (changes active hero during a game)
    var isPlayableHero: Bool { safeType == "HERO" && set != "HERO_SKINS" }

    /// Clean card text (strip HTML tags and $ symbols)
    var cleanText: String? {
        guard let text = text else { return nil }
        return text
            .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "$", with: "")
            .replacingOccurrences(of: "\n", with: " ")
    }

    var formattedClass: String {
        switch safeCardClass {
        case "DEATHKNIGHT": return "Death Knight"
        case "DEMONHUNTER": return "Demon Hunter"
        default: return safeCardClass.prefix(1).uppercased() + safeCardClass.dropFirst().lowercased()
        }
    }

    var formattedRarity: String {
        safeRarity.prefix(1).uppercased() + safeRarity.dropFirst().lowercased()
    }

    // Hashable by card ID
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: HSCard, rhs: HSCard) -> Bool {
        lhs.id == rhs.id
    }
}

/// A card the user owns (or has trial access to), with count and premium info
struct OwnedCard: Identifiable {
    let card: HSCard
    let normalCount: Int
    let goldenCount: Int
    let hasGolden: Bool
    var isTrial: Bool = false  // true if this is a trial/Core grant card

    var totalCount: Int { normalCount + goldenCount }
    var id: String { card.id }
}

/// Per-class collection ownership stats
struct ClassOwnership: Identifiable {
    let className: String
    let ownedUnique: Int
    let totalUnique: Int

    var percentage: Double {
        totalUnique > 0 ? Double(ownedUnique) / Double(totalUnique) * 100.0 : 0
    }

    var id: String { className }

    var formattedClass: String {
        switch className {
        case "DEATHKNIGHT": return "Death Knight"
        case "DEMONHUNTER": return "Demon Hunter"
        case "NEUTRAL": return "Neutral"
        default: return className.prefix(1).uppercased() + className.dropFirst().lowercased()
        }
    }
}

/// Hearthstone class colors
enum HSClassColor {
    static func color(for className: String) -> (r: Double, g: Double, b: Double) {
        switch className {
        case "DEATHKNIGHT":  return (0.77, 0.12, 0.23)
        case "DEMONHUNTER":  return (0.64, 0.19, 0.79)
        case "DRUID":        return (1.00, 0.49, 0.04)
        case "HUNTER":       return (0.67, 0.83, 0.45)
        case "MAGE":         return (0.25, 0.78, 0.92)
        case "PALADIN":      return (0.96, 0.55, 0.73)
        case "PRIEST":       return (0.90, 0.90, 0.90)
        case "ROGUE":        return (1.00, 0.96, 0.41)
        case "SHAMAN":       return (0.00, 0.44, 0.87)
        case "WARLOCK":      return (0.53, 0.53, 0.93)
        case "WARRIOR":      return (0.78, 0.61, 0.43)
        default:             return (0.50, 0.50, 0.50)
        }
    }
}

/// All playable Hearthstone classes
let HS_CLASSES: [String] = [
    "DEATHKNIGHT", "DEMONHUNTER", "DRUID", "HUNTER", "MAGE",
    "PALADIN", "PRIEST", "ROGUE", "SHAMAN", "WARLOCK", "WARRIOR"
]

/// Standard/Wild format classification.
/// Standard sets rotate yearly — update this list when a new Hearthstone year begins.
enum CardFormats {
    /// Sets currently legal in Standard (Year of the Pegasus, 2025-2026).
    /// CORE is always Standard. Update this when sets rotate.
    static let standardSets: Set<String> = [
        "CORE",
        "ISLAND_VACATION",
        "WHIZBANGS_WORKSHOP",
        "SPACE",
        "CATACLYSM",
        "THE_LOST_CITY",
        "EMERALD_DREAM",
        "TIME_TRAVEL",
        "BATTLE_OF_THE_BANDS",
    ]

    static func isStandard(_ card: HSCard) -> Bool {
        guard let set = card.set else { return false }
        return standardSets.contains(set)
    }
}
