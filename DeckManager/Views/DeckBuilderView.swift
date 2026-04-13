import SwiftUI
import AppKit

enum DeckSheet: String, Identifiable {
    case synergy, cardPicker, importDeck
    var id: String { rawValue }
}

/// The Deck Builder view — a canvas of 30 (or 40) card slots.
/// Users fill slots from favorites, synergies, or manual selection.
struct DeckBuilderView: View {
    @ObservedObject var userStore = UserDataStore.shared
    @ObservedObject var database = CardDatabase.shared
    let ownedCards: [OwnedCard]

    @State private var deck: SavedDeck
    @State private var showClassPicker = true
    @State private var showAddOptions = false
    @State private var selectedSlotIndex: Int?
    @State private var activeSheet: DeckSheet?
    @State private var deckNameEditing = false
    @State private var showSaveConfirm = false

    let onDismiss: () -> Void

    init(ownedCards: [OwnedCard], existingDeck: SavedDeck? = nil, onDismiss: @escaping () -> Void) {
        self.ownedCards = ownedCards
        self.onDismiss = onDismiss
        _deck = State(initialValue: existingDeck ?? SavedDeck(
            id: UUID().uuidString,
            name: "New Deck",
            heroClass: "MAGE",
            format: "standard",
            cards: [],
            createdAt: Date(),
            updatedAt: Date()
        ))
        _showClassPicker = State(initialValue: existingDeck == nil)
    }

    var body: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)
                .ignoresSafeArea()

            if showClassPicker {
                classPickerView
            } else {
                deckCanvasView
            }
        }
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .synergy:
                SynergyPickerSheet(
                    heroClass: deck.heroClass,
                    userStore: userStore,
                    onSelect: { synergy in
                        addSynergyToDeck(synergy)
                    }
                )
            case .cardPicker:
                CardPickerSheet(
                    heroClass: deck.heroClass,
                    ownedCards: ownedCards,
                    existingCardNames: Set(deck.cards.map { $0.cardName }),
                    onSelect: { cardName, cardId in
                        addManualCard(name: cardName, id: cardId)
                    }
                )
            case .importDeck:
                ImportDeckSheet(database: database) { imported in
                    deck = imported
                    showClassPicker = false
                }
            }
        }
    }

    // MARK: - Class Picker

    /// Pick a representative hero skin for a class.
    /// Prefers a random favorite skin, falls back to a random owned skin.
    private func representativeSkin(for cls: String) -> HSCard? {
        let favNames = userStore.heroFavorites
        let ownedSkins = ownedCards.filter { $0.card.isHeroSkin && $0.card.safeCardClass == cls }

        // Favorite skins for this class
        let favSkins = ownedSkins.filter { favNames.contains($0.card.name) }
        if let pick = favSkins.randomElement() { return pick.card }

        // Any owned skin for this class
        if let pick = ownedSkins.randomElement() { return pick.card }

        // Fallback: any skin in the full database for this class
        let dbSkins = database.cards.filter { $0.isHeroSkin && $0.safeCardClass == cls }
        return dbSkins.randomElement()
    }

    private var classPickerView: some View {
        VStack(spacing: 12) {
            // Top bar with title and actions
            HStack {
                Button("Cancel") { onDismiss() }
                    .buttonStyle(.plain)
                    .foregroundColor(.secondary)
                    .font(FontManager.philosopher(size: 11))

                Spacer()

                Text("Choose a Class")
                    .font(FontManager.philosopher(size: 18, weight: .bold))
                    .foregroundColor(.primary)

                Spacer()

                Button(action: { activeSheet = .importDeck }) {
                    HStack(spacing: 4) {
                        Image(systemName: "square.and.arrow.down")
                        Text("Import Deck Code")
                    }
                    .font(FontManager.philosopher(size: 11, weight: .medium))
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
            }
            .padding(.horizontal, 24)
            .padding(.top, 16)

            // Class grid (scrollable)
            ScrollView {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: 6), spacing: 2) {
                    ForEach(HS_CLASSES, id: \.self) { cls in
                        Button(action: {
                            deck.heroClass = cls
                            withAnimation { showClassPicker = false }
                        }) {
                            ZStack(alignment: .bottom) {
                                if let skin = representativeSkin(for: cls) {
                                    CardImageView(card: skin)
                                } else {
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(Color.white.opacity(0.05))
                                        .aspectRatio(0.7, contentMode: .fit)
                                }
                                Text(formatClass(cls))
                                    .font(FontManager.philosopher(size: 12, weight: .bold))
                                    .foregroundColor(.black)
                                    .offset(y: -42)
                            }
                            .clipped()
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 24)
            }
        }
        .padding(.bottom, 12)
    }

    // MARK: - Deck Canvas

    private var deckCanvasView: some View {
        VStack(spacing: 0) {
            // Header
            deckHeader

            // Card slots grid
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 160, maximum: 240))], spacing: 12) {
                    ForEach(0..<deck.deckSize, id: \.self) { index in
                        if index < deck.cards.count {
                            filledSlot(deck.cards[index], index: index)
                        } else {
                            emptySlot(index: index)
                        }
                    }
                }
                .padding(16)
            }
        }
    }

    // MARK: - Deck Header

    private var deckHeader: some View {
        let rgb = HSClassColor.color(for: deck.heroClass)
        let classColor = Color(red: rgb.r, green: rgb.g, blue: rgb.b)

        return VStack(spacing: 6) {
            // Top row: navigation, deck info, save/export
            HStack {
                Button(action: onDismiss) {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                        Text("Back")
                    }
                    .font(FontManager.philosopher(size: 11))
                }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)

                if deckNameEditing {
                    TextField("Deck name", text: $deck.name, onCommit: { deckNameEditing = false })
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 200)
                } else {
                    Text(deck.name)
                        .font(FontManager.philosopher(size: 16, weight: .bold))
                        .foregroundColor(.primary)
                        .onTapGesture { deckNameEditing = true }
                }

                Text("·").foregroundColor(.secondary)
                Text(formatClass(deck.heroClass))
                    .font(FontManager.philosopher(size: 13, weight: .medium))
                    .foregroundColor(classColor)

                Text("·").foregroundColor(.secondary)
                Text("\(deck.totalCards)/\(deck.deckSize)")
                    .font(FontManager.philosopher(size: 13))
                    .foregroundColor(deck.isComplete ? .green : .secondary)

                Spacer()

                Button(action: { activeSheet = .importDeck }) {
                    HStack(spacing: 4) {
                        Image(systemName: "square.and.arrow.down")
                        Text("Import")
                    }
                    .font(FontManager.philosopher(size: 11))
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)

                Button(action: saveDeck) {
                    Text("Save")
                        .font(FontManager.philosopher(size: 11, weight: .medium))
                }
                .buttonStyle(.borderedProminent)
                .tint(.blue)

                Button(action: copyDeckCode) {
                    HStack(spacing: 4) {
                        Image(systemName: "doc.on.doc")
                        Text("Copy Code")
                    }
                    .font(FontManager.philosopher(size: 11))
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .disabled(!deck.isComplete)
            }

            // Bottom row: add card actions
            HStack(spacing: 12) {
                Button(action: { addFavoritesToDeck(neutralOnly: false) }) {
                    HStack(spacing: 4) {
                        Image(systemName: "heart.fill").foregroundColor(.red)
                        Text("Class Favorites")
                    }
                    .font(FontManager.philosopher(size: 10))
                }
                .buttonStyle(.plain)
                .disabled(userStore.favorites.isEmpty)

                Button(action: { addFavoritesToDeck(neutralOnly: true) }) {
                    HStack(spacing: 4) {
                        Image(systemName: "heart.fill").foregroundColor(.orange)
                        Text("Neutral Favorites")
                    }
                    .font(FontManager.philosopher(size: 10))
                }
                .buttonStyle(.plain)
                .disabled(userStore.favorites.isEmpty)

                Button(action: { activeSheet = .synergy }) {
                    HStack(spacing: 4) {
                        Image(systemName: "bolt.fill").foregroundColor(.yellow)
                        Text("Synergy")
                    }
                    .font(FontManager.philosopher(size: 10))
                }
                .buttonStyle(.plain)

                Button(action: { activeSheet = .cardPicker }) {
                    HStack(spacing: 4) {
                        Image(systemName: "plus")
                        Text("Add Card")
                    }
                    .font(FontManager.philosopher(size: 10))
                }
                .buttonStyle(.plain)

                Spacer()
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
    }

    // MARK: - Slots

    private func filledSlot(_ slot: DeckSlot, index: Int) -> some View {
        let isTrialCard = ownedCards.first(where: { $0.card.name == slot.cardName })?.isTrial ?? false

        return ZStack(alignment: .bottom) {
            ZStack(alignment: .topTrailing) {
                if let card = database.cards.first(where: { $0.name == slot.cardName }) {
                    CardImageView(card: card)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                } else {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.white.opacity(0.05))
                    .aspectRatio(0.7, contentMode: .fit)
                    .overlay {
                        Text(slot.cardName)
                            .font(FontManager.philosopher(size: 10))
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(4)
                    }
                }

                // Trial badge
                if isTrialCard {
                    HStack(spacing: 2) {
                        Image(systemName: "hourglass")
                            .font(FontManager.philosopher(size: 7))
                        Text("Trial")
                            .font(FontManager.philosopher(size: 8, weight: .bold))
                    }
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Color.cyan.opacity(0.85))
                    .foregroundColor(.black)
                    .cornerRadius(4)
                    .padding(4)
                }
            }

            // Controls overlay at bottom of card
            HStack(spacing: 8) {
                // Source icon
                Group {
                    switch slot.source {
                    case .favorite:
                        Image(systemName: "heart.fill")
                            .foregroundColor(.red)
                    case .synergy:
                        Image(systemName: "bolt.fill")
                            .foregroundColor(.yellow)
                    case .manual:
                        Image(systemName: "hand.tap")
                            .foregroundColor(.blue)
                    }
                }
                .font(FontManager.philosopher(size: 14))

                if slot.count > 1 {
                    Text("×\(slot.count)")
                        .font(FontManager.philosopher(size: 14, weight: .bold))
                        .foregroundColor(.orange)
                }

                Button(action: { incrementCard(at: index) }) {
                    Image(systemName: "plus.circle.fill")
                        .font(FontManager.philosopher(size: 18))
                        .foregroundColor(.green)
                }
                .buttonStyle(.plain)

                Button(action: { removeCard(at: index) }) {
                    Image(systemName: "minus.circle.fill")
                        .font(FontManager.philosopher(size: 18))
                        .foregroundColor(.red)
                }
                .buttonStyle(.plain)
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 10)
            .background(
                Capsule().fill(Color.black.opacity(0.7))
            )
            .padding(.bottom, 8)
        }
    }

    private func emptySlot(index: Int) -> some View {
        RoundedRectangle(cornerRadius: 4)
            .strokeBorder(Color.white.opacity(0.15), style: StrokeStyle(lineWidth: 1, dash: [4]))
            .aspectRatio(0.7, contentMode: .fit)
            .overlay {
                Image(systemName: "plus")
                    .font(FontManager.philosopher(size: 16))
                    .foregroundColor(Color.white.opacity(0.15))
            }
            .onTapGesture { activeSheet = .cardPicker }
            .cursor(.pointingHand)
    }

    // MARK: - Actions

    private func addFavoritesToDeck(neutralOnly: Bool) {
        let targetClass = neutralOnly ? "NEUTRAL" : deck.heroClass
        let classCards = ownedCards.filter {
            userStore.isFavorite($0.card.name) &&
            $0.card.safeCardClass == targetClass &&
            !$0.card.isHeroSkin
        }

        for oc in classCards {
            if deck.totalCards >= deck.deckSize { break }
            // Skip if already in deck — user can manually increase count
            if deck.cards.contains(where: { $0.cardName == oc.card.name }) { continue }
            deck.cards.append(DeckSlot(
                cardName: oc.card.name,
                cardId: oc.card.id,
                count: 1,
                source: .favorite
            ))
        }
        deck.updatedAt = Date()
    }

    private func addSynergyToDeck(_ synergy: Synergy) {
        for cardName in synergy.cardNames {
            if deck.totalCards >= deck.deckSize { break }
            // Skip if already in deck — user can manually increase count
            if deck.cards.contains(where: { $0.cardName == cardName }) { continue }

            guard let card = database.cards.first(where: { $0.name == cardName }) else { continue }
            deck.cards.append(DeckSlot(
                cardName: cardName,
                cardId: card.id,
                count: 1,
                source: .synergy
            ))
        }
        deck.updatedAt = Date()
    }

    private func maxCopies(for card: HSCard?) -> Int {
        if card?.safeRarity == "LEGENDARY" || deck.hasHighlanderCard { return 1 }
        return 2
    }

    private func addManualCard(name: String, id: String) {
        if deck.totalCards >= deck.deckSize { return }
        let card = database.cards.first(where: { $0.name == name })

        // Don't add a Highlander card if the deck already has duplicates
        if card?.isHighlander == true && deck.hasDuplicates { return }

        if let existing = deck.cards.firstIndex(where: { $0.cardName == name }) {
            if deck.cards[existing].count < maxCopies(for: card) {
                deck.cards[existing].count += 1
            }
        } else {
            deck.cards.append(DeckSlot(
                cardName: name,
                cardId: id,
                count: 1,
                source: .manual
            ))
        }
        deck.updatedAt = Date()
    }

    private func incrementCard(at index: Int) {
        guard index < deck.cards.count else { return }
        guard deck.totalCards < deck.deckSize else { return }
        let card = database.cards.first(where: { $0.name == deck.cards[index].cardName })
        if deck.cards[index].count < maxCopies(for: card) {
            deck.cards[index].count += 1
            deck.updatedAt = Date()
        }
    }

    private func removeCard(at index: Int) {
        guard index < deck.cards.count else { return }
        if deck.cards[index].count > 1 {
            deck.cards[index].count -= 1
        } else {
            deck.cards.remove(at: index)
        }
        deck.updatedAt = Date()
    }

    private func saveDeck() {
        userStore.saveDeck(deck)
        onDismiss()
    }

    private func copyDeckCode() {
        guard let code = DeckEncoder.encode(deck: deck, database: database) else {
            print("[DeckBuilder] Failed to encode deck")
            return
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(code, forType: .string)
        print("[DeckBuilder] Deck code copied: \(code)")
    }

    private func formatClass(_ cls: String) -> String {
        switch cls {
        case "DEATHKNIGHT": return "Death Knight"
        case "DEMONHUNTER": return "Demon Hunter"
        default: return cls.prefix(1).uppercased() + cls.dropFirst().lowercased()
        }
    }
}

// MARK: - Synergy Picker Sheet

struct SynergyPickerSheet: View {
    let heroClass: String
    let userStore: UserDataStore
    let onSelect: (Synergy) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 16) {
            Text("Add Synergy")
                .font(FontManager.philosopher(size: 16, weight: .bold))

            let available = userStore.synergies(forClass: heroClass)

            if available.isEmpty {
                Text("No synergies created for this class yet.")
                    .foregroundColor(.secondary)
                    .padding()
            } else {
                ForEach(available) { synergy in
                    Button(action: {
                        onSelect(synergy)
                        dismiss()
                    }) {
                        HStack {
                            Image(systemName: "bolt.fill")
                                .foregroundColor(.yellow)
                            Text(synergy.name)
                                .font(FontManager.philosopher(size: 13, weight: .medium))
                            Spacer()
                            Text("\(synergy.cardNames.count) cards")
                                .font(FontManager.philosopher(size: 11))
                                .foregroundColor(.secondary)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.05)))
                    }
                    .buttonStyle(.plain)
                }
            }

            Button("Cancel") { dismiss() }
                .buttonStyle(.plain)
                .foregroundColor(.secondary)
        }
        .padding(20)
        .frame(width: 350)
    }
}

// MARK: - Card Picker Sheet

struct CardPickerSheet: View {
    let heroClass: String
    let ownedCards: [OwnedCard]
    let existingCardNames: Set<String>
    let onSelect: (String, String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Add Card")
                    .font(FontManager.philosopher(size: 16, weight: .bold))
                Spacer()
                Button("Done") { dismiss() }
                    .buttonStyle(.plain)
                    .foregroundColor(.blue)
            }
            .padding(16)

            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("Search...", text: $searchText)
                    .textFieldStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)

            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 100, maximum: 130))], spacing: 8) {
                    ForEach(filteredCards, id: \.card.id) { oc in
                        let alreadyAdded = existingCardNames.contains(oc.card.name)

                        ZStack {
                            CardImageView(card: oc.card)
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                                .opacity(alreadyAdded ? 0.4 : 1.0)

                            if alreadyAdded {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(FontManager.philosopher(size: 20))
                                    .foregroundColor(.green)
                            }
                        }
                        .onTapGesture {
                            if !alreadyAdded {
                                onSelect(oc.card.name, oc.card.id)
                            }
                        }
                        .cursor(.pointingHand)
                    }
                }
                .padding(16)
            }
        }
        .frame(width: 600, height: 500)
    }

    private var filteredCards: [OwnedCard] {
        var cards = ownedCards.filter {
            ($0.card.safeCardClass == heroClass || $0.card.safeCardClass == "NEUTRAL") &&
            !$0.card.isHeroSkin
        }

        if !searchText.isEmpty {
            let terms = searchText.lowercased().split(separator: " ")
            cards = cards.filter { oc in
                let s = "\(oc.card.name) \(oc.card.text ?? "")".lowercased()
                return terms.allSatisfy { s.contains($0) }
            }
        }

        return cards.sorted {
            if $0.card.safeCost != $1.card.safeCost { return $0.card.safeCost < $1.card.safeCost }
            return $0.card.name < $1.card.name
        }
    }
}

// MARK: - Import Deck Sheet

struct ImportDeckSheet: View {
    let database: CardDatabase
    let onImport: (SavedDeck) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var deckString = ""
    @State private var errorMessage: String?
    @State private var previewDeck: SavedDeck?

    var body: some View {
        VStack(spacing: 16) {
            Text("Import Deck Code")
                .font(FontManager.philosopher(size: 16, weight: .bold))

            Text("Paste a Hearthstone deck code below. You can copy one from Hearthstone by viewing a deck and clicking \"Copy Deck Code\".")
                .font(FontManager.philosopher(size: 11))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 400)

            // Text input
            TextEditor(text: $deckString)
                .font(.system(size: 12, design: .monospaced))
                .frame(height: 80)
                .border(Color.white.opacity(0.2), width: 1)
                .onChange(of: deckString) { _ in
                    errorMessage = nil
                    previewDeck = nil
                }

            // Paste from clipboard button
            Button(action: pasteFromClipboard) {
                HStack(spacing: 4) {
                    Image(systemName: "doc.on.clipboard")
                    Text("Paste from Clipboard")
                }
                .font(FontManager.philosopher(size: 11))
            }
            .buttonStyle(.plain)
            .foregroundColor(.blue)

            // Preview
            if let preview = previewDeck {
                let rgb = HSClassColor.color(for: preview.heroClass)
                let color = Color(red: rgb.r, green: rgb.g, blue: rgb.b)

                VStack(spacing: 4) {
                    HStack {
                        Text(formatClass(preview.heroClass))
                            .font(FontManager.philosopher(size: 13, weight: .semibold))
                            .foregroundColor(color)
                        Text("\u{00B7}")
                            .foregroundColor(.secondary)
                        Text("\(preview.totalCards) cards")
                            .font(FontManager.philosopher(size: 12))
                            .foregroundColor(.secondary)
                        Text("\u{00B7}")
                            .foregroundColor(.secondary)
                        Text(preview.format == "wild" ? "Wild" : "Standard")
                            .font(FontManager.philosopher(size: 12))
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }

            if let error = errorMessage {
                Text(error)
                    .font(FontManager.philosopher(size: 11))
                    .foregroundColor(.red)
            }

            HStack(spacing: 16) {
                Button("Cancel") { dismiss() }
                    .buttonStyle(.plain)
                    .foregroundColor(.secondary)

                Button(action: parseDeck) {
                    Text("Preview")
                        .font(FontManager.philosopher(size: 12, weight: .medium))
                }
                .buttonStyle(.borderedProminent)
                .tint(.blue)
                .disabled(deckString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                Button(action: {
                    if previewDeck == nil { parseDeck() }
                    if let preview = previewDeck {
                        onImport(preview)
                        dismiss()
                    }
                }) {
                    Text("Import")
                        .font(FontManager.philosopher(size: 12, weight: .medium))
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .disabled(deckString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 500)
    }

    private func pasteFromClipboard() {
        if let str = NSPasteboard.general.string(forType: .string) {
            deckString = str
            parseDeck()
        }
    }

    private func parseDeck() {
        let trimmed = deckString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            errorMessage = "Please paste a deck code."
            return
        }

        guard let imported = DeckEncoder.importDeck(trimmed, database: database) else {
            errorMessage = "Could not parse this deck code. Make sure it's a valid Hearthstone deck string."
            return
        }

        if imported.cards.isEmpty {
            errorMessage = "Decoded the deck but no cards could be resolved. The card database may need updating."
            return
        }

        previewDeck = imported
        errorMessage = nil
    }

    private func formatClass(_ cls: String) -> String {
        switch cls {
        case "DEATHKNIGHT": return "Death Knight"
        case "DEMONHUNTER": return "Demon Hunter"
        default: return cls.prefix(1).uppercased() + cls.dropFirst().lowercased()
        }
    }
}
