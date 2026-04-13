// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "DeckManager",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "DeckManager",
            path: "DeckManager",
            resources: [
                .copy("Resources/Philosopher-Regular.ttf"),
                .copy("Resources/Philosopher-Bold.ttf"),
                .copy("Resources/Philosopher-Italic.ttf"),
                .copy("Resources/Philosopher-BoldItalic.ttf"),
            ]
        ),
    ]
)
