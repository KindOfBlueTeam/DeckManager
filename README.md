# DeckManager

A native macOS Hearthstone card collection browser and deck builder. Import your collection from a JSON file, browse cards with filters, build and manage decks, and export deck codes to Hearthstone.

## Download

Download **[DeckManager.zip](DeckManager.zip)** and follow the install instructions below.

## Features

- **Card Browser** — filter by class, rarity, cost, Standard/Wild format, search, favorites
- **Deck Builder** — 30-slot canvas (40 with Prince Renathal), import/export Hearthstone deck codes
- **Saved Decks** — persistent deck library with copy, edit, and delete
- **Synergies** — named card groups organized by class
- **Favorites** — heart overlay on card art, organized by class
- **Collection Import** — drag-and-drop or file picker for collection JSON files
- **Card Grid Density** — adjustable slider for card size
- **Philosopher Font** — custom serif font for a Hearthstone-themed UI
- **Dark Mode** — clean dark appearance with darker sidebar panels

## Requirements

- macOS 13.0 or later
- Apple Silicon or Intel Mac
- A collection JSON file (from [DeckRipper](https://github.com/KindOfBlueTeam/DeckRippper) or [deck.coach](https://deck.coach))

## Install

1. Download `DeckManager.zip` from this repo
2. Unzip it (Safari auto-extracts to `DeckManager.app`)
3. Open Terminal and run:
   ```bash
   xattr -cr ~/Downloads/DeckManager.app
   ```
4. Drag `DeckManager.app` to `/Applications`
5. Launch DeckManager

## Usage

1. On first launch, DeckManager asks you to **load a collection JSON file**
2. Choose the file exported by DeckRipper or downloaded from deck.coach
3. Browse your cards, build decks, and manage your collection
4. Click **Upload Deck Data** in the header to load a different collection
5. Click **Talk to a Coach!** to open the AI deck coach at [deck.coach/ai](https://deck.coach/ai)

## Build From Source

Requires Swift 5.9+ (included with Xcode Command Line Tools).

```bash
# Development build
swift build
.build/debug/DeckManager

# Release .app bundle + zip
./build-app.sh
```

## Project Structure

```
DeckManager/
├── DeckManager.zip          ← download this
├── Package.swift
├── build-app.sh
├── install.sh
├── DeckManager/             ← source code
│   ├── App.swift
│   ├── WizardView.swift
│   ├── Models/
│   │   ├── CardModels.swift
│   │   ├── CardDatabase.swift
│   │   ├── CollectionViewModel.swift
│   │   ├── DeckEncoder.swift
│   │   ├── FontManager.swift
│   │   └── UserDataStore.swift
│   ├── Views/
│   │   ├── AppRootView.swift
│   │   ├── AppearanceSettingsView.swift
│   │   ├── CollectionView.swift
│   │   ├── DeckBuilderView.swift
│   │   ├── SynergySheets.swift
│   │   └── WindowAppearance.swift
│   └── Resources/
│       └── Philosopher-*.ttf
└── docs/
```

## License

MIT License — see [LICENSE](LICENSE) for details.
