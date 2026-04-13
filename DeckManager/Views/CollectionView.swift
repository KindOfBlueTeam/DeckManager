import SwiftUI

/// Main collection browser view with frosted vibrancy background.
struct CollectionView: View {
    @StateObject private var viewModel = CollectionViewModel()
    @State private var showCardText = false
    @State private var selectedCard: OwnedCard?
    @State private var showDeckBuilder = false
    @State private var editingDeck: SavedDeck?
    @ObservedObject private var userStore = UserDataStore.shared
    let collectionPath: String
    var onReloadCollection: (() -> Void)?

    var body: some View {
        ZStack {
            // Solid dark background
            Color(nsColor: .windowBackgroundColor)
                .ignoresSafeArea()

            if !viewModel.isLoaded {
                loadingView
            } else {
                mainContent
            }
        }
        .task {
            await viewModel.loadCollection(from: collectionPath)
        }
        .sheet(isPresented: $showCreateSynergy) {
            CreateSynergySheet(
                database: CardDatabase.shared,
                ownedCards: viewModel.ownedCards,
                onSave: { name, heroClass, cardNames in
                    _ = userStore.createSynergy(name: name, heroClass: heroClass, cardNames: cardNames)
                }
            )
        }
        .sheet(item: $editingSynergy) { synergy in
            EditSynergySheet(
                synergy: synergy,
                database: CardDatabase.shared,
                ownedCards: viewModel.ownedCards,
                onSave: { updated in
                    userStore.updateSynergy(updated)
                }
            )
        }
        .sheet(isPresented: $showSavedDecks) {
            SavedDecksSheet(
                onEdit: { deck in
                    showSavedDecks = false
                    editingDeck = deck
                    withAnimation { showDeckBuilder = true }
                }
            )
        }
        .sheet(isPresented: $showSynergiesSheet) {
            SynergiesSheet(
                onCreateSynergy: { showSynergiesSheet = false; showCreateSynergy = true },
                onEditSynergy: { synergy in showSynergiesSheet = false; editingSynergy = synergy }
            )
        }
    }

    private var loadingView: some View {
        VStack(spacing: 12) {
            ProgressView()
                .scaleEffect(1.2)
            Text("Loading card database...")
                .font(FontManager.philosopher(size: 13))
                .foregroundColor(.secondary)
        }
    }

    private var mainContent: some View {
        ZStack {
            if showDeckBuilder {
                DeckBuilderView(
                    ownedCards: viewModel.ownedCards,
                    existingDeck: editingDeck,
                    onDismiss: {
                        withAnimation {
                            showDeckBuilder = false
                            editingDeck = nil
                        }
                    }
                )
            } else {
                VStack(spacing: 0) {
                    // Header
                    headerBar

                    // Main area: sidebar + card grid
                    HStack(spacing: 0) {
                        // Left sidebar
                        classProgressSidebar

                        // Right: filters + card grid
                        VStack(spacing: 0) {
                            filterBar
                            cardGrid
                        }
                    }
                }

                // Card detail overlay
                if let card = selectedCard {
                    CardDetailOverlay(ownedCard: card) {
                        withAnimation(.easeOut(duration: 0.15)) {
                            selectedCard = nil
                        }
                    }
                    .transition(.opacity)
                }
            }
        }
    }

    // MARK: - Header

    private var headerBar: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(userStore.playerName != nil ? "\(userStore.playerName!)'s Collection" : "My Collection")
                    .font(FontManager.philosopher(size: 20, weight: .bold))
                    .foregroundColor(.primary)
                HStack(spacing: 12) {
                    Label("\(viewModel.totalCount) Total", systemImage: "square.stack.3d.up")
                    Label("\(viewModel.availableCount) Available", systemImage: "hand.raised")
                    Label("\(viewModel.uniqueCount) Unique", systemImage: "sparkles")
                    if let scanDate = viewModel.scanDate {
                        Label(scanAgeText(scanDate), systemImage: "clock")
                            .foregroundColor(scanAgeColor(scanDate))
                    }
                }
                .font(FontManager.philosopher(size: 11))
                .foregroundColor(.secondary)
            }

            Spacer()

            // Accessibility toggle
            Toggle(isOn: $showCardText) {
                Text("Show card text")
                    .font(FontManager.philosopher(size: 11))
            }
            .toggleStyle(.checkbox)
            .foregroundColor(.secondary)

            // Upload new collection
            Button(action: { onReloadCollection?() }) {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.up.doc")
                        .font(FontManager.philosopher(size: 11))
                    Text("Upload Deck Data")
                        .font(FontManager.philosopher(size: 11, weight: .medium))
                }
                .foregroundColor(.blue)
            }
            .buttonStyle(.plain)

            // Settings
            Button(action: { showAppearanceSettings.toggle() }) {
                Image(systemName: "gearshape")
                    .font(FontManager.philosopher(size: 14))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showAppearanceSettings) {
                AppearanceSettingsView(onReloadCollection: onReloadCollection)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(panelBackground)
    }

    private func scanAgeText(_ date: Date) -> String {
        let interval = Date().timeIntervalSince(date)
        let minutes = Int(interval) / 60
        let hours = minutes / 60
        let days = hours / 24
        let weeks = days / 7
        let months = days / 30
        let years = days / 365

        if years > 0 { return "Updated \(years) year\(years == 1 ? "" : "s") ago" }
        if months > 0 { return "Updated \(months) month\(months == 1 ? "" : "s") ago" }
        if weeks > 0 { return "Updated \(weeks) week\(weeks == 1 ? "" : "s") ago" }
        if days > 0 { return "Updated \(days) day\(days == 1 ? "" : "s") ago" }
        if hours > 0 { return "Updated \(hours) hour\(hours == 1 ? "" : "s") ago" }
        return "Updated just now"
    }

    private func scanAgeColor(_ date: Date) -> Color {
        let days = Int(Date().timeIntervalSince(date)) / 86400
        if days >= 365 { return .red }
        if days >= 30 { return .orange }
        if days >= 7 { return Color.yellow }
        return .green
    }

    // MARK: - Class Progress Sidebar

    @State private var cardsExpanded = false
    @State private var ownedCardsExpanded = false
    @State private var classesExpanded = false

    /// True if any top-level sidebar section is expanded
    private var anyTopLevelExpanded: Bool {
        cardsExpanded || classesExpanded || heroesExpanded
    }

    /// Opacity for a top-level section: full if expanded or nothing is open, dimmed otherwise
    private func sectionOpacity(_ isExpanded: Bool) -> Double {
        if !anyTopLevelExpanded { return 1.0 }
        return isExpanded ? 1.0 : 0.4
    }
    @State private var classesShowAll = false
    @State private var trialCardsExpanded = false
    @State private var unownedExpanded = false
    @State private var heroesExpanded = false
    @State private var skinsExpanded = false
    @State private var ownedSkinsExpanded = false
    @State private var unownedSkinsExpanded = false
    @State private var heroCardsExpanded = false
    @State private var ownedHeroCardsExpanded = false
    @State private var unownedHeroCardsExpanded = false
    @State private var favoriteHeroesExpanded = false

    @State private var savedDecksExpanded = false

    private let panelBackground = Color.black.opacity(0.3)

    private var classProgressSidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Deck Builder button
            Button(action: {
                editingDeck = nil
                withAnimation { showDeckBuilder = true }
            }) {
                HStack(spacing: 6) {
                    Image(systemName: "hammer.fill")
                        .font(FontManager.philosopher(size: 12))
                    Text("Deck Builder")
                        .font(FontManager.philosopher(size: 12, weight: .semibold))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.blue.opacity(0.2)))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.blue.opacity(0.4), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .foregroundColor(.blue)
            .padding(.bottom, 4)

            // Saved Decks button
            Button(action: { showSavedDecks = true }) {
                HStack(spacing: 6) {
                    Text("Saved Decks")
                        .font(FontManager.philosopher(size: 12, weight: .semibold))
                    if !userStore.savedDecks.isEmpty {
                        Text("(\(userStore.savedDecks.count))")
                            .font(FontManager.philosopher(size: 11))
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.orange.opacity(0.2)))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.orange.opacity(0.4), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .foregroundColor(.orange)
            .padding(.bottom, 4)

            // Synergies button
            Button(action: { showSynergiesSheet = true }) {
                HStack(spacing: 6) {
                    Text("Synergies")
                        .font(FontManager.philosopher(size: 12, weight: .semibold))
                    if !userStore.synergies.isEmpty {
                        Text("(\(userStore.synergies.count))")
                            .font(FontManager.philosopher(size: 11))
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.orange.opacity(0.2)))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.orange.opacity(0.4), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .foregroundColor(.orange)
            .padding(.bottom, 4)

            // AI Coach link
            Link(destination: URL(string: "https://deck.coach/ai")!) {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles")
                        .font(FontManager.philosopher(size: 10))
                    Text("Talk to a Coach!")
                        .font(FontManager.philosopher(size: 12, weight: .semibold))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.purple.opacity(0.2)))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.purple.opacity(0.4), lineWidth: 1))
            }
            .foregroundColor(.purple)
            .padding(.bottom, 12)

            Divider()
                .padding(.bottom, 8)

            // Collapsible: Cards (FAVORITES, OWNED, TRIAL, UNOWNED)
            DisclosureGroup(isExpanded: $cardsExpanded) {
                VStack(alignment: .leading, spacing: 0) {
                    // Favorites
                    DisclosureGroup(isExpanded: $favoritesExpanded) {
                        if userStore.favorites.isEmpty {
                            Text("Click the \u{2661} below any card to add it to your favorites.")
                                .font(FontManager.philosopher(size: 10))
                                .foregroundColor(.secondary)
                                .padding(.top, 4)
                        } else {
                            let grouped = userStore.favoritesByClass(database: CardDatabase.shared)
                            let sortedClasses = grouped.keys.sorted {
                                if $0 == "NEUTRAL" { return false }
                                if $1 == "NEUTRAL" { return true }
                                return $0 < $1
                            }

                            VStack(alignment: .leading, spacing: 4) {
                                ForEach(sortedClasses, id: \.self) { cls in
                                    let cards = grouped[cls] ?? []

                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(formatClassNameStatic(cls))
                                            .font(FontManager.philosopher(size: 9, weight: .semibold))
                                            .foregroundColor(.secondary)

                                        ForEach(cards, id: \.id) { card in
                                            HStack(spacing: 4) {
                                                Image(systemName: "heart.fill")
                                                    .font(FontManager.philosopher(size: 7))
                                                    .foregroundColor(.red)
                                                Text(card.name)
                                                    .font(FontManager.philosopher(size: 10))
                                                    .foregroundColor(.primary)
                                                    .lineLimit(1)
                                                Spacer()
                                                Button(action: { userStore.removeFavorite(card.name) }) {
                                                    Image(systemName: "xmark")
                                                        .font(FontManager.philosopher(size: 7))
                                                        .foregroundColor(.secondary)
                                                }
                                                .buttonStyle(.plain)
                                            }
                                        }
                                    }
                                    .padding(.bottom, 2)
                                }

                                Text("\(userStore.favorites.count) favorites")
                                    .font(FontManager.philosopher(size: 9))
                                    .foregroundColor(.secondary)
                                    .padding(.top, 2)
                            }
                            .padding(.top, 6)
                        }
                    } label: {
                        HStack {
                            Text("FAVORITES")
                                .font(FontManager.philosopher(size: 9, weight: .semibold))
                                .foregroundColor(.secondary)
                                .tracking(1)
                            if !userStore.favorites.isEmpty {
                                Text("(\(userStore.favorites.count))")
                                    .font(FontManager.philosopher(size: 9))
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .padding(.bottom, 8)

                    // Owned Cards
                    DisclosureGroup(isExpanded: $ownedCardsExpanded) {
                        VStack(alignment: .leading, spacing: 2) {
                            UnownedClassRow(
                                label: "All Classes",
                                isSelected: viewModel.showOwnedCards && viewModel.ownedCardClass == "ALL",
                                action: {
                                    clearHeroModes()
                                    viewModel.showOwnedCards = true
                                    viewModel.ownedCardClass = "ALL"
                                }
                            )

                            ForEach(HS_CLASSES, id: \.self) { cls in
                                UnownedClassRow(
                                    label: formatClassNameStatic(cls),
                                    isSelected: viewModel.showOwnedCards && viewModel.ownedCardClass == cls,
                                    action: {
                                        clearHeroModes()
                                        viewModel.showOwnedCards = true
                                        viewModel.ownedCardClass = cls
                                    }
                                )
                            }

                            UnownedClassRow(
                                label: "Neutral",
                                isSelected: viewModel.showOwnedCards && viewModel.ownedCardClass == "NEUTRAL",
                                action: {
                                    clearHeroModes()
                                    viewModel.showOwnedCards = true
                                    viewModel.ownedCardClass = "NEUTRAL"
                                }
                            )

                            if viewModel.showOwnedCards {
                                Button(action: { viewModel.showOwnedCards = false }) {
                                    Text("\u{2190} Back to My Collection")
                                        .font(FontManager.philosopher(size: 10))
                                        .foregroundColor(.blue)
                                }
                                .buttonStyle(.plain)
                                .padding(.top, 6)
                            }
                        }
                        .padding(.top, 6)
                    } label: {
                        Text("OWNED")
                            .font(FontManager.philosopher(size: 9, weight: .semibold))
                            .foregroundColor(.secondary)
                            .tracking(1)
                    }
                    .onChange(of: ownedCardsExpanded) { expanded in
                        if !expanded && viewModel.showOwnedCards {
                            viewModel.showOwnedCards = false
                        }
                    }
                    .padding(.bottom, 8)

                    // Trial Cards
                    if !viewModel.trialCards.isEmpty {
                        DisclosureGroup(isExpanded: $trialCardsExpanded) {
                            VStack(alignment: .leading, spacing: 2) {
                                UnownedClassRow(
                                    label: "All Classes",
                                    isSelected: viewModel.showTrialOnly && viewModel.trialClass == "ALL",
                                    action: {
                                        clearHeroModes()
                                        viewModel.showTrialOnly = true
                                        viewModel.trialClass = "ALL"
                                    }
                                )

                                ForEach(trialCardClasses, id: \.self) { cls in
                                    UnownedClassRow(
                                        label: formatClassNameStatic(cls),
                                        isSelected: viewModel.showTrialOnly && viewModel.trialClass == cls,
                                        action: {
                                            clearHeroModes()
                                            viewModel.showTrialOnly = true
                                            viewModel.trialClass = cls
                                        }
                                    )
                                }

                                if viewModel.showTrialOnly {
                                    Button(action: { viewModel.showTrialOnly = false }) {
                                        Text("\u{2190} Back to My Collection")
                                            .font(FontManager.philosopher(size: 10))
                                            .foregroundColor(.blue)
                                    }
                                    .buttonStyle(.plain)
                                    .padding(.top, 6)
                                }
                            }
                            .padding(.top, 6)
                        } label: {
                            HStack {
                                Text("TRIAL")
                                    .font(FontManager.philosopher(size: 9, weight: .semibold))
                                    .foregroundColor(.secondary)
                                    .tracking(1)
                                Text("(\(viewModel.trialCount))")
                                    .font(FontManager.philosopher(size: 9))
                                    .foregroundColor(.secondary)
                            }
                        }
                        .onChange(of: trialCardsExpanded) { expanded in
                            if !expanded && viewModel.showTrialOnly {
                                viewModel.showTrialOnly = false
                            }
                        }
                        .padding(.bottom, 8)
                    }

                    // Unowned Cards
                    DisclosureGroup(isExpanded: $unownedExpanded) {
                        VStack(alignment: .leading, spacing: 2) {
                            UnownedClassRow(
                                label: "All Classes",
                                isSelected: viewModel.showUnownedOnly && viewModel.unownedClass == "ALL",
                                action: {
                                    clearHeroModes()
                                    viewModel.showUnownedOnly = true
                                    viewModel.unownedClass = "ALL"
                                }
                            )

                            ForEach(HS_CLASSES, id: \.self) { cls in
                                UnownedClassRow(
                                    label: formatClassNameStatic(cls),
                                    isSelected: viewModel.showUnownedOnly && viewModel.unownedClass == cls,
                                    action: {
                                        clearHeroModes()
                                        viewModel.showUnownedOnly = true
                                        viewModel.unownedClass = cls
                                    }
                                )
                            }

                            UnownedClassRow(
                                label: "Neutral",
                                isSelected: viewModel.showUnownedOnly && viewModel.unownedClass == "NEUTRAL",
                                action: {
                                    clearHeroModes()
                                    viewModel.showUnownedOnly = true
                                    viewModel.unownedClass = "NEUTRAL"
                                }
                            )

                            if viewModel.showUnownedOnly {
                                Button(action: { viewModel.showUnownedOnly = false }) {
                                    Text("\u{2190} Back to My Collection")
                                        .font(FontManager.philosopher(size: 10))
                                        .foregroundColor(.blue)
                                }
                                .buttonStyle(.plain)
                                .padding(.top, 6)
                            }
                        }
                        .padding(.top, 6)
                    } label: {
                        Text("UNOWNED")
                            .font(FontManager.philosopher(size: 9, weight: .semibold))
                            .foregroundColor(.secondary)
                            .tracking(1)
                    }
                    .onChange(of: unownedExpanded) { expanded in
                        if !expanded && viewModel.showUnownedOnly {
                            viewModel.showUnownedOnly = false
                        }
                    }
                    .padding(.bottom, 4)

                    // Hero Cards (playable hero cards, not skins)
                    DisclosureGroup(isExpanded: $heroCardsExpanded) {
                        VStack(alignment: .leading, spacing: 4) {

                            // Owned Hero Cards
                            DisclosureGroup(isExpanded: $ownedHeroCardsExpanded) {
                                VStack(alignment: .leading, spacing: 2) {
                                    UnownedClassRow(
                                        label: "All Classes",
                                        isSelected: viewModel.showOwnedHeroCards && viewModel.ownedHeroCardClass == "ALL",
                                        action: {
                                            clearHeroModes()
                                            viewModel.showOwnedHeroCards = true
                                            viewModel.ownedHeroCardClass = "ALL"
                                        }
                                    )

                                    ForEach(HS_CLASSES, id: \.self) { cls in
                                        UnownedClassRow(
                                            label: formatClassNameStatic(cls),
                                            isSelected: viewModel.showOwnedHeroCards && viewModel.ownedHeroCardClass == cls,
                                            action: {
                                                clearHeroModes()
                                                viewModel.showOwnedHeroCards = true
                                                viewModel.ownedHeroCardClass = cls
                                            }
                                        )
                                    }

                                    if viewModel.showOwnedHeroCards {
                                        Button(action: { viewModel.showOwnedHeroCards = false }) {
                                            Text("\u{2190} Back to My Collection")
                                                .font(FontManager.philosopher(size: 10))
                                                .foregroundColor(.blue)
                                        }
                                        .buttonStyle(.plain)
                                        .padding(.top, 6)
                                    }
                                }
                                .padding(.top, 6)
                            } label: {
                                Text("OWNED")
                                    .font(FontManager.philosopher(size: 9, weight: .semibold))
                                    .foregroundColor(.secondary)
                                    .tracking(1)
                            }
                            .onChange(of: ownedHeroCardsExpanded) { expanded in
                                if !expanded && viewModel.showOwnedHeroCards {
                                    viewModel.showOwnedHeroCards = false
                                }
                            }
                            .padding(.bottom, 4)

                            // Unowned Hero Cards
                            DisclosureGroup(isExpanded: $unownedHeroCardsExpanded) {
                                VStack(alignment: .leading, spacing: 2) {
                                    UnownedClassRow(
                                        label: "All Classes",
                                        isSelected: viewModel.showUnownedHeroCards && viewModel.unownedHeroCardClass == "ALL",
                                        action: {
                                            clearHeroModes()
                                            viewModel.showUnownedHeroCards = true
                                            viewModel.unownedHeroCardClass = "ALL"
                                        }
                                    )

                                    ForEach(HS_CLASSES, id: \.self) { cls in
                                        UnownedClassRow(
                                            label: formatClassNameStatic(cls),
                                            isSelected: viewModel.showUnownedHeroCards && viewModel.unownedHeroCardClass == cls,
                                            action: {
                                                clearHeroModes()
                                                viewModel.showUnownedHeroCards = true
                                                viewModel.unownedHeroCardClass = cls
                                            }
                                        )
                                    }

                                    if viewModel.showUnownedHeroCards {
                                        Button(action: { viewModel.showUnownedHeroCards = false }) {
                                            Text("\u{2190} Back to My Collection")
                                                .font(FontManager.philosopher(size: 10))
                                                .foregroundColor(.blue)
                                        }
                                        .buttonStyle(.plain)
                                        .padding(.top, 6)
                                    }
                                }
                                .padding(.top, 6)
                            } label: {
                                Text("UNOWNED")
                                    .font(FontManager.philosopher(size: 9, weight: .semibold))
                                    .foregroundColor(.secondary)
                                    .tracking(1)
                            }
                            .onChange(of: unownedHeroCardsExpanded) { expanded in
                                if !expanded && viewModel.showUnownedHeroCards {
                                    viewModel.showUnownedHeroCards = false
                                }
                            }
                        }
                        .padding(.top, 6)
                    } label: {
                        Text("HERO CARDS")
                            .font(FontManager.philosopher(size: 9, weight: .semibold))
                            .foregroundColor(.secondary)
                            .tracking(1)
                    }
                    .onChange(of: heroCardsExpanded) { expanded in
                        if !expanded {
                            viewModel.showOwnedHeroCards = false
                            viewModel.showUnownedHeroCards = false
                        }
                    }
                }
                .padding(.top, 6)
                .padding(.leading, 8)
            } label: {
                Text("CARDS")
                    .font(FontManager.philosopher(size: 9, weight: .semibold))
                    .foregroundColor(.secondary)
                    .tracking(1)
            }
            .opacity(sectionOpacity(cardsExpanded))
            .animation(.easeInOut(duration: 0.2), value: anyTopLevelExpanded)
            .padding(.bottom, 12)

            // Collapsible: Classes
            DisclosureGroup(isExpanded: $classesExpanded) {
                VStack(alignment: .leading, spacing: 4) {
                    // Per-class disclosure groups
                    ForEach(viewModel.classOwnership) { co in
                            DisclosureGroup {
                                VStack(alignment: .leading, spacing: 6) {
                                    // Progress bar
                                    ClassProgressBar(ownership: co)

                                    // Quick filter button
                                    Button(action: {
                                        viewModel.showUnownedOnly = false
                                        viewModel.showUnownedHeroes = false
                                        viewModel.showOwnedHeroes = false
                                        viewModel.showFavoriteHeroes = false
                                        viewModel.showTrialOnly = false
                                        viewModel.selectedClass = co.className
                                        viewModel.showHeroesOnly = false
                                    }) {
                                        Text("View \(co.formattedClass) Cards")
                                            .font(FontManager.philosopher(size: 10))
                                            .foregroundColor(.blue)
                                    }
                                    .buttonStyle(.plain)
                                }
                                .padding(.top, 4)
                            } label: {
                                HStack(spacing: 6) {
                                    Text(co.formattedClass)
                                        .font(FontManager.philosopher(size: 10))
                                        .foregroundColor(.secondary)
                                    Spacer()
                                    Text(String(format: "%.0f%%", co.percentage))
                                        .font(FontManager.philosopher(size: 9))
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                    }
                .padding(.top, 6)
                .padding(.leading, 8)
            } label: {
                Text("CLASSES")
                    .font(FontManager.philosopher(size: 9, weight: .semibold))
                    .foregroundColor(.secondary)
                    .tracking(1)
            }
            .opacity(sectionOpacity(classesExpanded))
            .animation(.easeInOut(duration: 0.2), value: anyTopLevelExpanded)
            .padding(.bottom, 12)

            // Collapsible: Heroes
            DisclosureGroup(isExpanded: $heroesExpanded) {
                VStack(alignment: .leading, spacing: 4) {

                    // SKINS subsection (cosmetic, not playable)
                    DisclosureGroup(isExpanded: $skinsExpanded) {
                        VStack(alignment: .leading, spacing: 4) {

                            // Favorite Skins
                            DisclosureGroup(isExpanded: $favoriteHeroesExpanded) {
                                VStack(alignment: .leading, spacing: 2) {
                                    if userStore.heroFavorites.isEmpty {
                                        Text("Click the \u{2661} on any skin to add it here.")
                                            .font(FontManager.philosopher(size: 10))
                                            .foregroundColor(.secondary)
                                            .padding(.top, 4)
                                    } else {
                                        ForEach(Array(userStore.heroFavorites).sorted(), id: \.self) { name in
                                            HStack(spacing: 4) {
                                                Image(systemName: "heart.fill")
                                                    .font(FontManager.philosopher(size: 7))
                                                    .foregroundColor(.red)
                                                Text(name)
                                                    .font(FontManager.philosopher(size: 10))
                                                    .foregroundColor(.secondary)
                                                    .lineLimit(1)
                                                Spacer()
                                                Button(action: { userStore.toggleHeroFavorite(name) }) {
                                                    Image(systemName: "xmark")
                                                        .font(FontManager.philosopher(size: 7))
                                                        .foregroundColor(.secondary)
                                                }
                                                .buttonStyle(.plain)
                                            }
                                        }

                                        Button(action: {
                                            clearHeroModes()
                                            viewModel.showFavoriteHeroes = true
                                        }) {
                                            Text("View Favorites")
                                                .font(FontManager.philosopher(size: 10))
                                                .foregroundColor(.blue)
                                        }
                                        .buttonStyle(.plain)
                                        .padding(.top, 4)
                                    }

                                    if viewModel.showFavoriteHeroes {
                                        Button(action: { viewModel.showFavoriteHeroes = false }) {
                                            Text("\u{2190} Back to My Collection")
                                                .font(FontManager.philosopher(size: 10))
                                                .foregroundColor(.blue)
                                        }
                                        .buttonStyle(.plain)
                                        .padding(.top, 4)
                                    }
                                }
                                .padding(.top, 4)
                            } label: {
                                HStack {
                                    Text("FAVORITES")
                                        .font(FontManager.philosopher(size: 9, weight: .semibold))
                                        .foregroundColor(.secondary)
                                        .tracking(1)
                                    if !userStore.heroFavorites.isEmpty {
                                        Text("(\(userStore.heroFavorites.count))")
                                            .font(FontManager.philosopher(size: 9))
                                            .foregroundColor(.secondary)
                                    }
                                }
                            }
                            .padding(.bottom, 4)

                            // Owned Skins
                            DisclosureGroup(isExpanded: $ownedSkinsExpanded) {
                                VStack(alignment: .leading, spacing: 2) {
                                    UnownedClassRow(
                                        label: "All Classes",
                                        isSelected: viewModel.showOwnedSkins && viewModel.ownedSkinClass == "ALL",
                                        action: {
                                            clearHeroModes()
                                            viewModel.showOwnedSkins = true
                                            viewModel.ownedSkinClass = "ALL"
                                        }
                                    )

                                    ForEach(HS_CLASSES, id: \.self) { cls in
                                        UnownedClassRow(
                                            label: formatClassNameStatic(cls),
                                            isSelected: viewModel.showOwnedSkins && viewModel.ownedSkinClass == cls,
                                            action: {
                                                clearHeroModes()
                                                viewModel.showOwnedSkins = true
                                                viewModel.ownedSkinClass = cls
                                            }
                                        )
                                    }

                                    if viewModel.showOwnedSkins {
                                        Button(action: { viewModel.showOwnedSkins = false }) {
                                            Text("\u{2190} Back to My Collection")
                                                .font(FontManager.philosopher(size: 10))
                                                .foregroundColor(.blue)
                                        }
                                        .buttonStyle(.plain)
                                        .padding(.top, 6)
                                    }
                                }
                                .padding(.top, 6)
                            } label: {
                                Text("OWNED")
                                    .font(FontManager.philosopher(size: 9, weight: .semibold))
                                    .foregroundColor(.secondary)
                                    .tracking(1)
                            }
                            .onChange(of: ownedSkinsExpanded) { expanded in
                                if !expanded && viewModel.showOwnedSkins {
                                    viewModel.showOwnedSkins = false
                                }
                            }
                            .padding(.bottom, 4)

                            // Unowned Skins
                            DisclosureGroup(isExpanded: $unownedSkinsExpanded) {
                                VStack(alignment: .leading, spacing: 2) {
                                    UnownedClassRow(
                                        label: "All Classes",
                                        isSelected: viewModel.showUnownedSkins && viewModel.unownedSkinClass == "ALL",
                                        action: {
                                            clearHeroModes()
                                            viewModel.showUnownedSkins = true
                                            viewModel.unownedSkinClass = "ALL"
                                        }
                                    )

                                    ForEach(HS_CLASSES, id: \.self) { cls in
                                        UnownedClassRow(
                                            label: formatClassNameStatic(cls),
                                            isSelected: viewModel.showUnownedSkins && viewModel.unownedSkinClass == cls,
                                            action: {
                                                clearHeroModes()
                                                viewModel.showUnownedSkins = true
                                                viewModel.unownedSkinClass = cls
                                            }
                                        )
                                    }

                                    if viewModel.showUnownedSkins {
                                        Button(action: { viewModel.showUnownedSkins = false }) {
                                            Text("\u{2190} Back to My Collection")
                                                .font(FontManager.philosopher(size: 10))
                                                .foregroundColor(.blue)
                                        }
                                        .buttonStyle(.plain)
                                        .padding(.top, 6)
                                    }
                                }
                                .padding(.top, 6)
                            } label: {
                                Text("UNOWNED")
                                    .font(FontManager.philosopher(size: 9, weight: .semibold))
                                    .foregroundColor(.secondary)
                                    .tracking(1)
                            }
                            .onChange(of: unownedSkinsExpanded) { expanded in
                                if !expanded && viewModel.showUnownedSkins {
                                    viewModel.showUnownedSkins = false
                                }
                            }
                        }
                        .padding(.top, 6)
                    } label: {
                        Text("SKINS")
                            .font(FontManager.philosopher(size: 9, weight: .semibold))
                            .foregroundColor(.secondary)
                            .tracking(1)
                    }
                    .onChange(of: skinsExpanded) { expanded in
                        if !expanded {
                            viewModel.showOwnedSkins = false
                            viewModel.showUnownedSkins = false
                            viewModel.showFavoriteHeroes = false
                        }
                    }
                    .padding(.bottom, 4)

                }
                .padding(.top, 6)
                .padding(.leading, 8)
            } label: {
                Text("HEROES")
                    .font(FontManager.philosopher(size: 9, weight: .semibold))
                    .foregroundColor(.secondary)
                    .tracking(1)
            }
            .onChange(of: heroesExpanded) { expanded in
                if !expanded {
                    clearHeroModes()
                }
            }
            .opacity(sectionOpacity(heroesExpanded))
            .animation(.easeInOut(duration: 0.2), value: anyTopLevelExpanded)
            .padding(.bottom, 12)

            Spacer()
        }
        .padding(12)
        .frame(width: 220)
        .background(panelBackground)
    }

    @State private var favoritesExpanded = false
    @State private var synergiesExpanded = false
    @State private var showCreateSynergy = false
    @State private var editingSynergy: Synergy?
    @State private var showAppearanceSettings = false
    @State private var copiedDeckId: String?
    @State private var showSavedDecks = false
    @State private var showSynergiesSheet = false

    private func clearHeroModes() {
        viewModel.showUnownedOnly = false
        viewModel.showUnownedHeroes = false
        viewModel.showOwnedHeroes = false
        viewModel.showFavoriteHeroes = false
        viewModel.showTrialOnly = false
        viewModel.showOwnedSkins = false
        viewModel.showUnownedSkins = false
        viewModel.showOwnedHeroCards = false
        viewModel.showUnownedHeroCards = false
        viewModel.showOwnedCards = false
    }

    private var trialCardClasses: [String] {
        let classOrder = HS_CLASSES + ["NEUTRAL"]
        let classesWithTrials = Set(viewModel.trialCards.map { $0.card.safeCardClass })
        return classOrder.filter { classesWithTrials.contains($0) }
    }

    private var synergyClasses: [String] {
        let classOrder = HS_CLASSES + ["NEUTRAL"]
        let classesWithSynergies = Set(userStore.synergies.map { $0.heroClass })
        return classOrder.filter { classesWithSynergies.contains($0) }
    }

    private func formatClassNameStatic(_ cls: String) -> String {
        switch cls {
        case "DEATHKNIGHT": return "Death Knight"
        case "DEMONHUNTER": return "Demon Hunter"
        default: return cls.prefix(1).uppercased() + cls.dropFirst().lowercased()
        }
    }

    // MARK: - Filter Bar

    private var filterBar: some View {
        HStack(spacing: 10) {
            // Search
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                    .font(FontManager.philosopher(size: 12))
                TextField("Search cards...", text: $viewModel.searchText)
                    .textFieldStyle(.plain)
                    .font(FontManager.philosopher(size: 12))
                if !viewModel.searchText.isEmpty {
                    Button(action: { viewModel.searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                            .font(FontManager.philosopher(size: 11))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(.ultraThinMaterial)
            .cornerRadius(6)
            .frame(maxWidth: 200)

            // Class picker
            Picker("Class", selection: $viewModel.selectedClass) {
                Text("All Classes").tag("ALL")
                ForEach(viewModel.classOwnership) { co in
                    Text("\(co.formattedClass) (\(co.ownedUnique))").tag(co.className)
                }
            }
            .pickerStyle(.menu)
            .font(FontManager.philosopher(size: 12))

            // Rarity picker
            Picker("Rarity", selection: $viewModel.selectedRarity) {
                Text("All Rarities").tag("ALL")
                Text("Free").tag("FREE")
                Text("Common").tag("COMMON")
                Text("Rare").tag("RARE")
                Text("Epic").tag("EPIC")
                Text("Legendary").tag("LEGENDARY")
            }
            .pickerStyle(.menu)
            .font(FontManager.philosopher(size: 12))

            // Cost picker
            Picker("Cost", selection: $viewModel.selectedCost) {
                Text("All Costs").tag("ALL")
                ForEach(0..<7, id: \.self) { c in
                    Text("\(c) Mana").tag(String(c))
                }
                Text("7+ Mana").tag("7+")
            }
            .pickerStyle(.menu)
            .font(FontManager.philosopher(size: 12))

            // Format picker
            Picker("Format", selection: $viewModel.selectedFormat) {
                Text("All Formats").tag("ALL")
                Text("Standard").tag("STANDARD")
                Text("Wild").tag("WILD")
            }
            .pickerStyle(.menu)
            .font(FontManager.philosopher(size: 12))

            // Heroes toggle
            Toggle(isOn: $viewModel.showHeroesOnly) {
                Text("Heroes")
                    .font(FontManager.philosopher(size: 11))
            }
            .toggleStyle(.checkbox)
            .foregroundColor(.secondary)

            // Favorites toggle
            Toggle(isOn: $viewModel.showFavoritesOnly) {
                Text("Favorites")
                    .font(FontManager.philosopher(size: 11))
            }
            .toggleStyle(.checkbox)
            .foregroundColor(.secondary)

            Text("\(viewModel.filteredCount) cards matched")
                .font(FontManager.philosopher(size: 11, weight: .medium))
                .foregroundColor(viewModel.filteredCount > 0 ? .green : .red)

            Spacer()

            // Card size slider
            HStack(spacing: 4) {
                Image(systemName: "square.grid.3x3")
                    .font(FontManager.philosopher(size: 10))
                    .foregroundColor(.secondary)
                Slider(value: $userStore.cardSize, in: 80...250, step: 10)
                    .frame(width: 80)
                    .onChange(of: userStore.cardSize) { _ in
                        userStore.saveAppearance()
                    }
                Image(systemName: "square.grid.2x2")
                    .font(FontManager.philosopher(size: 10))
                    .foregroundColor(.secondary)
            }

        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
    }

    // MARK: - Card Grid

    private var cardGrid: some View {
        ScrollView {
            LazyVGrid(columns: [
                GridItem(.adaptive(minimum: userStore.cardSize, maximum: userStore.cardSize + 50))
            ], spacing: 8) {
                ForEach(viewModel.filteredCards) { oc in
                    CardTileView(ownedCard: oc, showText: showCardText)
                        .onTapGesture {
                            withAnimation(.easeOut(duration: 0.15)) {
                                selectedCard = oc
                            }
                        }
                        .cursor(.pointingHand)
                }
            }
            .padding(20)
        }
    }
}

// MARK: - Card Image with Fallback

struct CardImageView: View {
    let card: HSCard
    @State private var useFallback = false

    var body: some View {
        AsyncImage(url: useFallback ? card.imageUrl : card.imageUrl512) { phase in
            switch phase {
            case .success(let image):
                image
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .scaleEffect(1.15)
                    .clipped()
            case .failure:
                if !useFallback {
                    // Try 256x as fallback
                    Color.clear.onAppear { useFallback = true }
                } else {
                    // Both failed — show placeholder
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.white.opacity(0.05))
                        .aspectRatio(0.7, contentMode: .fit)
                        .overlay {
                            VStack(spacing: 4) {
                                Image(systemName: "questionmark")
                                    .font(FontManager.philosopher(size: 20))
                                    .foregroundColor(.secondary)
                                Text(card.name)
                                    .font(FontManager.philosopher(size: 9))
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                            }
                        }
                }
            case .empty:
                ProgressView()
                    .frame(height: 180)
            @unknown default:
                EmptyView()
            }
        }
    }
}

// MARK: - Unowned Class Row

struct UnownedClassRow: View {
    let label: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(label)
                    .font(FontManager.philosopher(size: 11))
                    .foregroundColor(isSelected ? .white : .secondary)
                Spacer()
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(isSelected ? Color.white.opacity(0.1) : Color.clear)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Class Progress Bar

struct ClassProgressBar: View {
    let ownership: ClassOwnership

    var body: some View {
        HStack(spacing: 6) {
            Text(ownership.formattedClass)
                .font(FontManager.philosopher(size: 10))
                .foregroundColor(.secondary)
                .frame(width: 75, alignment: .leading)
                .lineLimit(1)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.white.opacity(0.08))

                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.white.opacity(0.25))
                        .frame(width: geo.size.width * min(CGFloat(ownership.percentage) / 100.0, 1.0))
                }
            }
            .frame(height: 8)

            Text(String(format: "%.0f%%", ownership.percentage))
                .font(FontManager.philosopher(size: 9))
                .foregroundColor(.secondary)
                .frame(width: 30, alignment: .trailing)
        }
        .frame(height: 20)
    }
}

// MARK: - Card Tile

struct CardTileView: View {
    let ownedCard: OwnedCard
    let showText: Bool
    @ObservedObject private var userStore = UserDataStore.shared

    private var isHero: Bool { ownedCard.card.safeType == "HERO" }

    private var isFavorite: Bool {
        isHero ? userStore.isHeroFavorite(ownedCard.card.name) : userStore.isFavorite(ownedCard.card.name)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Card image with heart overlay
            CardImageView(card: ownedCard.card)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay {
                    GeometryReader { geo in
                        let heartSize = geo.size.height * 0.20
                        Button(action: {
                            if isHero {
                                userStore.toggleHeroFavorite(ownedCard.card.name)
                            } else {
                                userStore.toggleFavorite(ownedCard.card.name)
                            }
                        }) {
                            ZStack {
                                if isFavorite {
                                    Image(systemName: "heart.fill")
                                        .resizable()
                                        .aspectRatio(contentMode: .fit)
                                        .frame(width: heartSize, height: heartSize)
                                        .foregroundColor(.red)
                                    Image(systemName: "heart")
                                        .resizable()
                                        .aspectRatio(contentMode: .fit)
                                        .frame(width: heartSize, height: heartSize)
                                        .foregroundColor(.black)
                                } else {
                                    Image(systemName: "heart")
                                        .resizable()
                                        .aspectRatio(contentMode: .fit)
                                        .frame(width: heartSize, height: heartSize)
                                        .foregroundColor(Color.white.opacity(0.5))
                                }
                            }
                            .shadow(color: .black.opacity(0.6), radius: 3, x: 0, y: 1)
                        }
                        .buttonStyle(.plain)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .offset(y: -geo.size.height * 0.15)
                    }
                }

            // Accessibility card text
            if showText {
                VStack(alignment: .leading, spacing: 1) {
                    Text(ownedCard.card.name)
                        .font(FontManager.philosopher(size: 9, weight: .semibold))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    Text("\(ownedCard.card.safeCost) mana · \(ownedCard.card.formattedRarity)")
                        .font(FontManager.philosopher(size: 8))
                        .foregroundColor(.secondary)
                    if let text = ownedCard.card.cleanText {
                        Text(text)
                            .font(FontManager.philosopher(size: 8))
                            .foregroundStyle(.tertiary)
                            .lineLimit(2)
                    }
                }
                .padding(.horizontal, 4)
                .padding(.top, 1)
                .padding(.bottom, 2)
            }
        }
    }

}

// MARK: - Card Detail Overlay

struct CardDetailOverlay: View {
    let ownedCard: OwnedCard
    let onDismiss: () -> Void

    var body: some View {
        ZStack {
            // Dimmed backdrop — click to dismiss
            Color.black.opacity(0.6)
                .ignoresSafeArea()
                .onTapGesture { onDismiss() }

            // Large card image
            VStack(spacing: 12) {
                AsyncImage(url: ownedCard.card.imageUrl512) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .shadow(color: .black.opacity(0.5), radius: 20, y: 10)
                    case .failure:
                        largePlaceholder
                    case .empty:
                        ProgressView()
                            .frame(height: 400)
                    @unknown default:
                        largePlaceholder
                    }
                }
                .frame(maxHeight: 500)

                // Card info below image
                VStack(spacing: 4) {
                    Text(ownedCard.card.name)
                        .font(FontManager.philosopher(size: 18, weight: .bold))
                        .foregroundColor(.white)

                    HStack(spacing: 8) {
                        Text("\(ownedCard.card.safeCost) Mana")
                        Text("·")
                        Text(ownedCard.card.formattedRarity)
                        Text("·")
                        Text(ownedCard.card.formattedClass)
                        if ownedCard.hasGolden {
                            Text("·")
                            Text("★ Golden")
                                .foregroundColor(.yellow)
                        }
                    }
                    .font(FontManager.philosopher(size: 12))
                    .foregroundColor(.gray)

                    if let text = ownedCard.card.cleanText {
                        Text(text)
                            .font(FontManager.philosopher(size: 13))
                            .foregroundColor(.white.opacity(0.8))
                            .multilineTextAlignment(.center)
                            .padding(.top, 4)
                            .frame(maxWidth: 350)
                    }

                    HStack(spacing: 8) {
                        Text("Owned: \(ownedCard.totalCount) cop\(ownedCard.totalCount == 1 ? "y" : "ies")")
                            .font(FontManager.philosopher(size: 11))
                            .foregroundColor(.gray)

                        if ownedCard.goldenCount > 0 {
                            HStack(spacing: 2) {
                                Text("★")
                                    .font(FontManager.philosopher(size: 9))
                                Text("Golden")
                                    .font(FontManager.philosopher(size: 10, weight: .bold))
                            }
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.yellow.opacity(0.85))
                            .foregroundColor(.black)
                            .cornerRadius(4)
                        }

                        if ownedCard.isTrial {
                            Text("Trial")
                                .font(FontManager.philosopher(size: 10, weight: .bold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.cyan.opacity(0.85))
                                .foregroundColor(.black)
                                .cornerRadius(4)
                        }
                    }
                    .padding(.top, 4)
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.black.opacity(0.75))
                )
            }
            .padding(30)
        }
        .onExitCommand { onDismiss() } // Escape key
    }

    private var largePlaceholder: some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(Color.white.opacity(0.05))
            .frame(width: 300, height: 400)
            .overlay {
                VStack(spacing: 8) {
                    Image(systemName: "questionmark")
                        .font(FontManager.philosopher(size: 40))
                        .foregroundColor(.secondary)
                    Text(ownedCard.card.name)
                        .font(FontManager.philosopher(size: 14))
                        .foregroundColor(.secondary)
                }
            }
    }
}

// MARK: - Cursor modifier

extension View {
    func cursor(_ cursor: NSCursor) -> some View {
        onHover { inside in
            if inside { cursor.push() }
            else { NSCursor.pop() }
        }
    }
}

// MARK: - Frosted Vibrancy Background

struct VisualEffectBackground: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}

// MARK: - Saved Decks Sheet

struct SavedDecksSheet: View {
    @ObservedObject private var userStore = UserDataStore.shared
    @Environment(\.dismiss) private var dismiss
    @State private var selectedClass = "ALL"
    @State private var copiedDeckId: String?
    let onEdit: (SavedDeck) -> Void

    private var filteredDecks: [SavedDeck] {
        let decks = selectedClass == "ALL"
            ? userStore.savedDecks
            : userStore.savedDecks.filter { $0.heroClass == selectedClass }
        return decks.sorted { $0.heroClass < $1.heroClass }
    }

    private var deckClasses: [String] {
        let classes = Set(userStore.savedDecks.map { $0.heroClass })
        return HS_CLASSES.filter { classes.contains($0) }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Saved Decks")
                    .font(FontManager.philosopher(size: 16, weight: .bold))
                Spacer()

                Picker("Class", selection: $selectedClass) {
                    Text("All Classes").tag("ALL")
                    ForEach(deckClasses, id: \.self) { cls in
                        Text(formatClass(cls)).tag(cls)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 160)

                Button("Done") { dismiss() }
                    .buttonStyle(.plain)
                    .foregroundColor(.secondary)
            }
            .padding(16)

            Divider()

            if userStore.savedDecks.isEmpty {
                Spacer()
                Text("No saved decks yet.")
                    .font(FontManager.philosopher(size: 14))
                    .foregroundColor(.secondary)
                Spacer()
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(filteredDecks) { deck in
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text(deck.name)
                                        .font(FontManager.philosopher(size: 14, weight: .semibold))
                                        .foregroundColor(.primary)
                                    Spacer()
                                    Text(formatClass(deck.heroClass))
                                        .font(FontManager.philosopher(size: 11))
                                        .foregroundColor(.secondary)
                                    Text("\(deck.totalCards)/\(deck.deckSize)")
                                        .font(FontManager.philosopher(size: 11, weight: .medium))
                                        .foregroundColor(deck.isComplete ? .green : .orange)
                                }

                                // Card list
                                ForEach(deck.cards, id: \.cardName) { slot in
                                    HStack(spacing: 4) {
                                        Text(slot.cardName)
                                            .font(FontManager.philosopher(size: 11))
                                            .foregroundColor(.secondary)
                                            .lineLimit(1)
                                        Spacer()
                                        if slot.count > 1 {
                                            Text("\u{00D7}\(slot.count)")
                                                .font(FontManager.philosopher(size: 10, weight: .bold))
                                                .foregroundColor(.orange)
                                        }
                                    }
                                }

                                // Actions
                                HStack(spacing: 12) {
                                    if let code = DeckEncoder.encode(deck: deck, database: CardDatabase.shared) {
                                        Button(action: {
                                            NSPasteboard.general.clearContents()
                                            NSPasteboard.general.setString(code, forType: .string)
                                            copiedDeckId = deck.id
                                            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                                if copiedDeckId == deck.id { copiedDeckId = nil }
                                            }
                                        }) {
                                            HStack(spacing: 3) {
                                                Image(systemName: copiedDeckId == deck.id ? "checkmark" : "doc.on.doc")
                                                    .font(FontManager.philosopher(size: 10))
                                                Text(copiedDeckId == deck.id ? "Copied!" : "Copy Code")
                                                    .font(FontManager.philosopher(size: 11))
                                            }
                                            .foregroundColor(copiedDeckId == deck.id ? .green : .blue)
                                        }
                                        .buttonStyle(.plain)
                                    }

                                    Button(action: { onEdit(deck) }) {
                                        HStack(spacing: 3) {
                                            Image(systemName: "pencil")
                                                .font(FontManager.philosopher(size: 10))
                                            Text("Edit")
                                                .font(FontManager.philosopher(size: 11))
                                        }
                                        .foregroundColor(.secondary)
                                    }
                                    .buttonStyle(.plain)

                                    Button(action: { userStore.deleteDeck(id: deck.id) }) {
                                        HStack(spacing: 3) {
                                            Image(systemName: "trash")
                                                .font(FontManager.philosopher(size: 10))
                                            Text("Delete")
                                                .font(FontManager.philosopher(size: 11))
                                        }
                                        .foregroundColor(.red.opacity(0.7))
                                    }
                                    .buttonStyle(.plain)
                                }
                                .padding(.top, 2)
                            }
                            .padding(12)
                            .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.05)))
                        }
                    }
                    .padding(16)
                }
            }
        }
        .frame(width: 500, height: 500)
    }

    private func formatClass(_ cls: String) -> String {
        switch cls {
        case "DEATHKNIGHT": return "Death Knight"
        case "DEMONHUNTER": return "Demon Hunter"
        default: return cls.prefix(1).uppercased() + cls.dropFirst().lowercased()
        }
    }
}

// MARK: - Synergies Sheet

struct SynergiesSheet: View {
    @ObservedObject private var userStore = UserDataStore.shared
    @Environment(\.dismiss) private var dismiss
    let onCreateSynergy: () -> Void
    let onEditSynergy: (Synergy) -> Void

    private var synergyClasses: [String] {
        let classOrder = HS_CLASSES + ["NEUTRAL"]
        let classesWithSynergies = Set(userStore.synergies.map { $0.heroClass })
        return classOrder.filter { classesWithSynergies.contains($0) }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Synergies")
                    .font(FontManager.philosopher(size: 16, weight: .bold))
                Spacer()
                Button(action: onCreateSynergy) {
                    HStack(spacing: 4) {
                        Image(systemName: "plus.circle.fill")
                            .font(FontManager.philosopher(size: 12))
                        Text("Create Synergy")
                            .font(FontManager.philosopher(size: 12, weight: .medium))
                    }
                    .foregroundColor(.blue)
                }
                .buttonStyle(.plain)

                Button("Done") { dismiss() }
                    .buttonStyle(.plain)
                    .foregroundColor(.secondary)
                    .padding(.leading, 12)
            }
            .padding(16)

            Divider()

            if userStore.synergies.isEmpty {
                Spacer()
                VStack(spacing: 8) {
                    Text("No synergies yet.")
                        .font(FontManager.philosopher(size: 14))
                        .foregroundColor(.secondary)
                    Text("Create groups of cards that work well together.")
                        .font(FontManager.philosopher(size: 12))
                        .foregroundColor(.secondary)
                }
                Spacer()
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(synergyClasses, id: \.self) { cls in
                            let classSynergies = userStore.synergies.filter { $0.heroClass == cls }

                            VStack(alignment: .leading, spacing: 8) {
                                Text(formatClass(cls))
                                    .font(FontManager.philosopher(size: 13, weight: .bold))
                                    .foregroundColor(.primary)

                                ForEach(classSynergies) { synergy in
                                    VStack(alignment: .leading, spacing: 4) {
                                        HStack {
                                            Text(synergy.name)
                                                .font(FontManager.philosopher(size: 12, weight: .semibold))
                                                .foregroundColor(.primary)
                                            Spacer()
                                            Text("\(synergy.cardNames.count) cards")
                                                .font(FontManager.philosopher(size: 10))
                                                .foregroundColor(.secondary)
                                        }

                                        ForEach(synergy.cardNames, id: \.self) { name in
                                            HStack(spacing: 4) {
                                                Image(systemName: "bolt.fill")
                                                    .font(FontManager.philosopher(size: 8))
                                                    .foregroundColor(.yellow)
                                                Text(name)
                                                    .font(FontManager.philosopher(size: 11))
                                                    .foregroundColor(.secondary)
                                                    .lineLimit(1)
                                            }
                                        }

                                        HStack(spacing: 12) {
                                            Button(action: { onEditSynergy(synergy) }) {
                                                HStack(spacing: 3) {
                                                    Image(systemName: "pencil")
                                                        .font(FontManager.philosopher(size: 10))
                                                    Text("Edit")
                                                        .font(FontManager.philosopher(size: 11))
                                                }
                                                .foregroundColor(.secondary)
                                            }
                                            .buttonStyle(.plain)

                                            Button(action: { userStore.deleteSynergy(id: synergy.id) }) {
                                                HStack(spacing: 3) {
                                                    Image(systemName: "trash")
                                                        .font(FontManager.philosopher(size: 10))
                                                    Text("Delete")
                                                        .font(FontManager.philosopher(size: 11))
                                                }
                                                .foregroundColor(.red.opacity(0.7))
                                            }
                                            .buttonStyle(.plain)
                                        }
                                        .padding(.top, 2)
                                    }
                                    .padding(12)
                                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.05)))
                                }
                            }
                        }
                    }
                    .padding(16)
                }
            }
        }
        .frame(width: 500, height: 500)
    }

    private func formatClass(_ cls: String) -> String {
        switch cls {
        case "DEATHKNIGHT": return "Death Knight"
        case "DEMONHUNTER": return "Demon Hunter"
        default: return cls.prefix(1).uppercased() + cls.dropFirst().lowercased()
        }
    }
}
