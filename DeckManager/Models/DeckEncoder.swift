import Foundation

/// Encodes a deck into Hearthstone's deck code format (Base64 varint).
///
/// Format: [0=reserved] [1=version] [format] [hero count] [hero dbfIds...]
///         [single-copy count] [single dbfIds sorted...]
///         [double-copy count] [double dbfIds sorted...]
///         [n-copy count] [(dbfId, count) pairs...]
struct DeckEncoder {

    /// Encode a saved deck into a Hearthstone deck string.
    /// Requires the CardDatabase to look up dbfIds from card names.
    static func encode(deck: SavedDeck, database: CardDatabase) -> String? {
        // Resolve card names to dbfIds and group by count
        var singles: [Int] = []     // dbfIds appearing once
        var doubles: [Int] = []     // dbfIds appearing twice
        var nCopies: [(Int, Int)] = [] // (dbfId, count) for count > 2

        for slot in deck.cards {
            guard let card = database.cards.first(where: { $0.name == slot.cardName }) else {
                print("[DeckEncoder] Card not found: \(slot.cardName)")
                continue
            }

            switch slot.count {
            case 1: singles.append(card.dbfId)
            case 2: doubles.append(card.dbfId)
            default: nCopies.append((card.dbfId, slot.count))
            }
        }

        singles.sort()
        doubles.sort()

        // Determine hero dbfId based on class
        guard let heroDbfId = heroDbfId(for: deck.heroClass) else {
            print("[DeckEncoder] Unknown hero class: \(deck.heroClass)")
            return nil
        }

        // Determine format
        let format: Int = deck.format == "wild" ? 1 : 2

        // Build varint byte array
        var bytes: [UInt8] = []
        writeVarint(0, to: &bytes)           // reserved
        writeVarint(1, to: &bytes)           // version
        writeVarint(format, to: &bytes)      // format

        writeVarint(1, to: &bytes)           // 1 hero
        writeVarint(heroDbfId, to: &bytes)   // hero dbfId

        writeVarint(singles.count, to: &bytes)
        for id in singles { writeVarint(id, to: &bytes) }

        writeVarint(doubles.count, to: &bytes)
        for id in doubles { writeVarint(id, to: &bytes) }

        writeVarint(nCopies.count, to: &bytes)
        for (id, count) in nCopies {
            writeVarint(id, to: &bytes)
            writeVarint(count, to: &bytes)
        }

        // Base64 encode
        let data = Data(bytes)
        return data.base64EncodedString()
    }

    /// Decode a Hearthstone deck string into card dbfIds.
    static func decode(_ deckString: String) -> (format: Int, heroDbfId: Int, cards: [(dbfId: Int, count: Int)])? {
        guard let data = Data(base64Encoded: deckString) else { return nil }
        let bytes = Array(data)
        var offset = 0

        func readVarint() -> Int? {
            var result = 0
            var shift = 0
            while offset < bytes.count {
                let byte = bytes[offset]
                offset += 1
                result |= Int(byte & 0x7F) << shift
                if byte & 0x80 == 0 { return result }
                shift += 7
            }
            return nil
        }

        guard let _ = readVarint(),           // reserved
              let _ = readVarint(),           // version
              let format = readVarint(),
              let heroCount = readVarint() else { return nil }

        var heroDbfId = 0
        for _ in 0..<heroCount {
            guard let id = readVarint() else { return nil }
            heroDbfId = id
        }

        var cards: [(dbfId: Int, count: Int)] = []

        // Singles
        guard let singleCount = readVarint() else { return nil }
        for _ in 0..<singleCount {
            guard let id = readVarint() else { return nil }
            cards.append((dbfId: id, count: 1))
        }

        // Doubles
        guard let doubleCount = readVarint() else { return nil }
        for _ in 0..<doubleCount {
            guard let id = readVarint() else { return nil }
            cards.append((dbfId: id, count: 2))
        }

        // N-copies
        guard let nCount = readVarint() else { return nil }
        for _ in 0..<nCount {
            guard let id = readVarint(), let count = readVarint() else { return nil }
            cards.append((dbfId: id, count: count))
        }

        return (format: format, heroDbfId: heroDbfId, cards: cards)
    }

    // MARK: - Varint encoding

    private static func writeVarint(_ value: Int, to bytes: inout [UInt8]) {
        var v = value
        while v > 0x7F {
            bytes.append(UInt8(v & 0x7F) | 0x80)
            v >>= 7
        }
        bytes.append(UInt8(v & 0x7F))
    }

    // MARK: - Hero dbfIds

    /// Map hero class to the default hero card dbfId
    private static func heroDbfId(for heroClass: String) -> Int? {
        heroMap.first(where: { $0.value == heroClass })?.key
    }

    /// Map hero dbfId to class name
    static func heroClass(for dbfId: Int) -> String? {
        heroMap[dbfId]
    }

    private static let heroMap: [Int: String] = [
        78065: "DEATHKNIGHT",   // The Lich King (DK hero)
        56550: "DEMONHUNTER",   // Illidan Stormrage
        274:   "DRUID",         // Malfurion Stormrage
        31:    "HUNTER",        // Rexxar
        637:   "MAGE",          // Jaina Proudmoore
        671:   "PALADIN",       // Uther Lightbringer
        813:   "PRIEST",        // Anduin Wrynn
        930:   "ROGUE",         // Valeera Sanguinar
        1066:  "SHAMAN",        // Thrall
        893:   "WARLOCK",       // Gul'dan
        7:     "WARRIOR",       // Garrosh Hellscream
    ]

    /// Import a deck string into a SavedDeck, resolving dbfIds via the card database.
    /// Handles the full Hearthstone clipboard format including ### name and # comment lines.
    static func importDeck(_ deckString: String, database: CardDatabase) -> SavedDeck? {
        let lines = deckString
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }

        // Extract deck name from "### Deck Name" line
        let deckName = lines
            .first(where: { $0.hasPrefix("###") })?
            .dropFirst(3)
            .trimmingCharacters(in: .whitespaces)
            ?? "Imported Deck"

        // Extract the Base64 deck code (non-empty, non-comment lines)
        let cleaned = lines
            .filter { !$0.isEmpty && !$0.hasPrefix("#") }
            .joined()

        guard let decoded = decode(cleaned) else { return nil }

        // Resolve hero class: try our map first, then look up the hero card in the database
        let heroClass: String
        if let mapped = self.heroClass(for: decoded.heroDbfId) {
            heroClass = mapped
        } else if let heroCard = database.cards.first(where: { $0.dbfId == decoded.heroDbfId }),
                  let cardClass = heroCard.cardClass, cardClass != "NEUTRAL" {
            heroClass = cardClass
        } else {
            // Last resort: extract from "# Class: Mage" comment line
            if let classLine = lines.first(where: { $0.hasPrefix("# Class:") }) {
                let raw = classLine.dropFirst(8).trimmingCharacters(in: .whitespaces)
                // Handle multi-word class names
                switch raw.lowercased() {
                case "death knight": heroClass = "DEATHKNIGHT"
                case "demon hunter": heroClass = "DEMONHUNTER"
                default: heroClass = raw.uppercased()
                }
            } else {
                return nil
            }
        }

        var cards: [DeckSlot] = []
        for (dbfId, count) in decoded.cards {
            guard let card = database.cards.first(where: { $0.dbfId == dbfId }) else { continue }
            cards.append(DeckSlot(
                cardName: card.name,
                cardId: card.id,
                count: count,
                source: .manual
            ))
        }

        let format = decoded.format == 1 ? "wild" : "standard"
        return SavedDeck(
            id: UUID().uuidString,
            name: deckName,
            heroClass: heroClass,
            format: format,
            cards: cards,
            createdAt: Date(),
            updatedAt: Date()
        )
    }
}
