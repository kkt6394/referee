// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Referee",
    platforms: [.iOS(.v16), .watchOS(.v9), .macOS(.v13)],
    products: [
        .library(name: "RefereeLedger", targets: ["RefereeLedger"])
    ],
    targets: [
        .systemLibrary(name: "CSQLite", pkgConfig: "sqlite3"),
        .target(name: "RefereeLedger", dependencies: ["CSQLite"]),
        .testTarget(name: "RefereeLedgerTests", dependencies: ["RefereeLedger"])
    ]
)
