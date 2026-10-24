// swift-tools-version: 6.0
// "Ace Setup": Kyle's guide for setup day (installing Ace on Ashley's and
// Alex's devices). Runs only on Kyle's Mac. Build with ./make-app.sh.
import PackageDescription

let package = Package(
    name: "AceSetup",
    platforms: [.macOS(.v15)],
    targets: [
        .executableTarget(name: "AceSetup", path: "Sources/AceSetup",
                          swiftSettings: [.swiftLanguageMode(.v5)]),
    ]
)
