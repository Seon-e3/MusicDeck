// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "MusicDeck",
    platforms: [.macOS(.v15)],
    targets: [.executableTarget(name: "MusicDeck")],
    swiftLanguageModes: [.v5]
)
