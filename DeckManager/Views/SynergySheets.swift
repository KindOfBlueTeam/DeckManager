import SwiftUI

/// Sheet for creating a new synergy.
/// User picks a class (or Neutral), then selects cards from that class + Neutral.
struct CreateSynergySheet: View {
    let database: CardDatabase
    let ownedCards: [OwnedCard]
    let onSave: (String, String, [String]) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var selectedClass = "NEUTRAL"
    @State private var selectedCards: Set<String> = []
    @State private var searchText = ""

    /// The synergy's heroClass: the chosen player class, or NEUTRAL if "Neutral Synergy"
    private var heroClass: String { selectedClass }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Create Synergy")
                    .font(FontManager.philosopher(size: 16, weight: .bold))
                Spacer()
                Button("Cancel") { dismiss() }
                    .buttonStyle(.plain)
                    .foregroundColor(.secondary)
            }
            .padding(16)

            Divider()

            // Name and class picker
            HStack(spacing: 12) {
                TextField("Synergy name...", text: $name)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 200)

                Picker("Class", selection: $selectedClass) {
                    Text("Neutral Synergy").tag("NEUTRAL")
                    ForEach(HS_CLASSES, id: \.self) { cls in
                        Text(formatClass(cls)).tag(cls)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 170)
                .onChange(of: selectedClass) { _ in
                    // Clear selections when class changes — cards from old class are no longer valid
                    selectedCards.removeAll()
                    searchText = ""
                }

                Spacer()

                Text("\(selectedCards.count) cards selected")
                    .font(FontManager.philosopher(size: 12))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            // Search
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                    .font(FontManager.philosopher(size: 11))
                TextField("Search cards...", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(FontManager.philosopher(size: 12))
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)

            // Card list: selected class + Neutral (or just Neutral if "Neutral Synergy")
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 100, maximum: 140))], spacing: 8) {
                    ForEach(filteredCards, id: \.card.id) { oc in
                        SynergyCardPicker(
                            card: oc.card,
                            isSelected: selectedCards.contains(oc.card.name),
                            onToggle: {
                                if selectedCards.contains(oc.card.name) {
                                    selectedCards.remove(oc.card.name)
                                } else {
                                    selectedCards.insert(oc.card.name)
                                }
                            }
                        )
                    }
                }
                .padding(16)
            }

            Divider()

            // Save button
            HStack {
                Spacer()
                Button("Create Synergy") {
                    let derivedClass = Self.deriveClass(from: selectedCards, ownedCards: ownedCards)
                    onSave(name.isEmpty ? "Untitled Synergy" : name, derivedClass, Array(selectedCards))
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(selectedCards.isEmpty)
            }
            .padding(16)
        }
        .frame(width: 600, height: 500)
    }

    /// Derive the heroClass from the selected cards.
    /// If any card belongs to a player class, that's the synergy's class. Otherwise NEUTRAL.
    /// For multi-class cards, uses the first non-NEUTRAL class.
    static func deriveClass(from cardNames: Set<String>, ownedCards: [OwnedCard]) -> String {
        for name in cardNames {
            if let oc = ownedCards.first(where: { $0.card.name == name }) {
                for cls in oc.card.allClasses {
                    if cls != "NEUTRAL" { return cls }
                }
            }
        }
        return "NEUTRAL"
    }

    private var filteredCards: [OwnedCard] {
        var cards = ownedCards.filter {
            $0.card.belongsToClass(selectedClass) && !$0.card.isHeroSkin
        }

        if !searchText.isEmpty {
            let terms = searchText.lowercased().split(separator: " ")
            cards = cards.filter { oc in
                let s = "\(oc.card.name) \(oc.card.text ?? "")".lowercased()
                return terms.allSatisfy { s.contains($0) }
            }
        }

        return cards.sorted { $0.card.name < $1.card.name }
    }

    private func formatClass(_ cls: String) -> String {
        switch cls {
        case "DEATHKNIGHT": return "Death Knight"
        case "DEMONHUNTER": return "Demon Hunter"
        case "NEUTRAL": return "Neutral Synergy"
        default: return cls.prefix(1).uppercased() + cls.dropFirst().lowercased()
        }
    }
}

/// Sheet for editing an existing synergy.
/// Class can be changed — changing clears card selections since cards may no longer be valid.
struct EditSynergySheet: View {
    let synergy: Synergy
    let database: CardDatabase
    let ownedCards: [OwnedCard]
    let onSave: (Synergy) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var selectedClass: String
    @State private var selectedCards: Set<String>
    @State private var searchText = ""

    init(synergy: Synergy, database: CardDatabase, ownedCards: [OwnedCard], onSave: @escaping (Synergy) -> Void) {
        self.synergy = synergy
        self.database = database
        self.ownedCards = ownedCards
        self.onSave = onSave
        _name = State(initialValue: synergy.name)
        _selectedClass = State(initialValue: synergy.heroClass)
        _selectedCards = State(initialValue: Set(synergy.cardNames))
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Edit Synergy")
                    .font(FontManager.philosopher(size: 16, weight: .bold))
                Spacer()
                Button("Cancel") { dismiss() }
                    .buttonStyle(.plain)
                    .foregroundColor(.secondary)
            }
            .padding(16)

            Divider()

            // Name and class picker
            HStack(spacing: 12) {
                TextField("Synergy name...", text: $name)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 200)

                Picker("Class", selection: $selectedClass) {
                    Text("Neutral Synergy").tag("NEUTRAL")
                    ForEach(HS_CLASSES, id: \.self) { cls in
                        Text(formatClass(cls)).tag(cls)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 170)
                .onChange(of: selectedClass) { newClass in
                    // Keep cards that are still valid for the new class
                    let validNames = Set(ownedCards.filter {
                        $0.card.belongsToClass(newClass) && !$0.card.isHeroSkin
                    }.map { $0.card.name })
                    selectedCards = selectedCards.intersection(validNames)
                    searchText = ""
                }

                Spacer()

                Text("\(selectedCards.count) cards selected")
                    .font(FontManager.philosopher(size: 12))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            // Search
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                    .font(FontManager.philosopher(size: 11))
                TextField("Search cards...", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(FontManager.philosopher(size: 12))
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)

            // Card list: selected class + Neutral (or just Neutral)
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 100, maximum: 140))], spacing: 8) {
                    ForEach(filteredCards, id: \.card.id) { oc in
                        SynergyCardPicker(
                            card: oc.card,
                            isSelected: selectedCards.contains(oc.card.name),
                            onToggle: {
                                if selectedCards.contains(oc.card.name) {
                                    selectedCards.remove(oc.card.name)
                                } else {
                                    selectedCards.insert(oc.card.name)
                                }
                            }
                        )
                    }
                }
                .padding(16)
            }

            Divider()

            // Save button
            HStack {
                Spacer()
                Button("Save Changes") {
                    var updated = synergy
                    updated.name = name.isEmpty ? "Untitled Synergy" : name
                    updated.heroClass = CreateSynergySheet.deriveClass(from: selectedCards, ownedCards: ownedCards)
                    updated.cardNames = Array(selectedCards)
                    onSave(updated)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(16)
        }
        .frame(width: 600, height: 500)
    }

    private var filteredCards: [OwnedCard] {
        var cards = ownedCards.filter {
            $0.card.belongsToClass(selectedClass) && !$0.card.isHeroSkin
        }

        if !searchText.isEmpty {
            let terms = searchText.lowercased().split(separator: " ")
            cards = cards.filter { oc in
                let s = "\(oc.card.name) \(oc.card.text ?? "")".lowercased()
                return terms.allSatisfy { s.contains($0) }
            }
        }

        return cards.sorted { $0.card.name < $1.card.name }
    }

    private func formatClass(_ cls: String) -> String {
        switch cls {
        case "DEATHKNIGHT": return "Death Knight"
        case "DEMONHUNTER": return "Demon Hunter"
        case "NEUTRAL": return "Neutral"
        default: return cls.prefix(1).uppercased() + cls.dropFirst().lowercased()
        }
    }
}

/// A small card tile for the synergy picker — shows card image with a checkmark overlay
struct SynergyCardPicker: View {
    let card: HSCard
    let isSelected: Bool
    let onToggle: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            CardImageView(card: card)
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(isSelected ? Color.yellow : Color.clear, lineWidth: 2)
                )
                .opacity(isSelected ? 1.0 : 0.7)

            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .font(FontManager.philosopher(size: 16))
                    .foregroundColor(.yellow)
                    .background(Circle().fill(Color.black.opacity(0.5)))
                    .padding(4)
            }
        }
        .onTapGesture { onToggle() }
        .cursor(.pointingHand)
    }
}
