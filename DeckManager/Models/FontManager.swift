import SwiftUI
import CoreText

/// Registers and provides Philosopher font for the Hearthstone-themed UI.
enum FontManager {
    private static var registered = false

    /// Global font size multiplier (0.8–1.5). Set by UserDataStore on load/save.
    static var scale: Double = 1.0

    /// Register bundled Philosopher fonts. Call once at app startup.
    static func registerFonts() {
        guard !registered else { return }
        registered = true

        let fontNames = [
            "Philosopher-Regular",
            "Philosopher-Bold",
            "Philosopher-Italic",
            "Philosopher-BoldItalic",
        ]

        for name in fontNames {
            guard let url = findFont(named: name) else {
                print("[FontManager] Font not found: \(name)")
                continue
            }
            var error: Unmanaged<CFError>?
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error)
        }
    }

    /// Search multiple locations for font files — handles both dev builds and .app bundles.
    private static func findFont(named name: String) -> URL? {
        let filename = "\(name).ttf"

        // 1. SPM resource bundle (dev builds via `swift build`)
        //    Bundle.module crashes if the bundle doesn't exist, so check manually
        let execURL = Bundle.main.bundleURL
        let spmBundleName = "DeckManager_DeckManager.bundle"

        // Check inside .app/Contents/Resources/
        let appResourceBundle = execURL
            .appendingPathComponent("Contents/Resources")
            .appendingPathComponent(spmBundleName)
            .appendingPathComponent(filename)
        if FileManager.default.fileExists(atPath: appResourceBundle.path) {
            return appResourceBundle
        }

        // Check next to executable (SPM debug builds)
        let execDir = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent()
        let spmBundle = execDir.appendingPathComponent(spmBundleName).appendingPathComponent(filename)
        if FileManager.default.fileExists(atPath: spmBundle.path) {
            return spmBundle
        }

        // Check .app/Contents/MacOS/ (next to executable in app bundle)
        let macosBundle = execURL
            .appendingPathComponent("Contents/MacOS")
            .appendingPathComponent(spmBundleName)
            .appendingPathComponent(filename)
        if FileManager.default.fileExists(atPath: macosBundle.path) {
            return macosBundle
        }

        // Loose font file in Resources
        let looseResource = execURL
            .appendingPathComponent("Contents/Resources")
            .appendingPathComponent(filename)
        if FileManager.default.fileExists(atPath: looseResource.path) {
            return looseResource
        }

        // Source tree fallback (development)
        let sourceTree = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // Models/
            .deletingLastPathComponent() // DeckManager/
            .appendingPathComponent("Resources/\(filename)")
        if FileManager.default.fileExists(atPath: sourceTree.path) {
            return sourceTree
        }

        return nil
    }

    // MARK: - Font accessors

    static func philosopher(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        let scaled = size * CGFloat(scale)
        let name = (weight == .bold || weight == .semibold) ? "Philosopher-Bold" : "Philosopher-Regular"
        if let nsFont = NSFont(name: name, size: scaled) {
            return Font(nsFont)
        }
        return Font.system(size: scaled, weight: weight)
    }

    static func philosopherItalic(size: CGFloat, bold: Bool = false) -> Font {
        let scaled = size * CGFloat(scale)
        let name = bold ? "Philosopher-BoldItalic" : "Philosopher-Italic"
        if let nsFont = NSFont(name: name, size: scaled) {
            return Font(nsFont)
        }
        return Font.system(size: scaled).italic()
    }

    // MARK: - Rarity colors (full brightness)

    static func rarityColor(for rarity: String?) -> Color {
        switch rarity?.uppercased() {
        case "COMMON":    return .white
        case "RARE":      return Color(red: 0.0, green: 0.44, blue: 1.0)
        case "EPIC":      return Color(red: 0.64, green: 0.21, blue: 0.93)
        case "LEGENDARY": return Color(red: 1.0, green: 0.55, blue: 0.0)
        default:          return .white
        }
    }

    /// Build an AttributedString with card names highlighted by rarity color.
    /// Strips markdown bold markers (**) before matching since the AI uses them around card names.
    static func rarityHighlighted(text: String, baseFont: Font, baseColor: Color) -> AttributedString {
        // Strip markdown bold markers — AI wraps card names in **name**
        let cleanText = text.replacingOccurrences(of: "**", with: "")

        let db = CardDatabase.shared
        guard !db.cards.isEmpty else {
            var attr = AttributedString(cleanText)
            attr.font = baseFont
            attr.foregroundColor = baseColor
            return attr
        }

        // Build sorted card name list (longest first to match "Prince Renathal" before "Prince")
        let uniqueNames = Set(db.cards.map(\.name)).filter { $0.count >= 3 }
        let sortedNames = uniqueNames.sorted { $0.count > $1.count }

        // Find all non-overlapping matches
        struct Match: Comparable {
            let range: Range<String.Index>
            let rarity: String?
            static func < (lhs: Match, rhs: Match) -> Bool {
                lhs.range.lowerBound < rhs.range.lowerBound
            }
        }

        var matches: [Match] = []
        let lowerText = cleanText.lowercased()

        for name in sortedNames {
            let lowerName = name.lowercased()
            var searchStart = lowerText.startIndex
            while let range = lowerText.range(of: lowerName, range: searchStart..<lowerText.endIndex) {
                let before = range.lowerBound == lowerText.startIndex || !lowerText[lowerText.index(before: range.lowerBound)].isLetter
                let after = range.upperBound == lowerText.endIndex || !lowerText[range.upperBound].isLetter
                if before && after && !matches.contains(where: { $0.range.overlaps(range) }) {
                    let card = db.cards.first { $0.name.lowercased() == lowerName }
                    matches.append(Match(range: range, rarity: card?.rarity))
                }
                searchStart = range.upperBound
            }
        }

        matches.sort()

        var result = AttributedString()
        var currentIndex = cleanText.startIndex

        for match in matches {
            if currentIndex < match.range.lowerBound {
                var segment = AttributedString(cleanText[currentIndex..<match.range.lowerBound])
                segment.font = baseFont
                segment.foregroundColor = baseColor
                result += segment
            }
            var cardSegment = AttributedString(cleanText[match.range])
            cardSegment.font = baseFont
            cardSegment.foregroundColor = rarityColor(for: match.rarity)
            result += cardSegment
            currentIndex = match.range.upperBound
        }

        if currentIndex < cleanText.endIndex {
            var segment = AttributedString(cleanText[currentIndex...])
            segment.font = baseFont
            segment.foregroundColor = baseColor
            result += segment
        }

        return result
    }
}
