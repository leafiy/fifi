// swift-tools-version: 5.9
import PackageDescription

var products: [Product] = []
var targets: [Target] = [
    .systemLibrary(name: "CSQLite", path: "Sources/CSQLite"),
    .target(
        name: "FifiCore",
        dependencies: ["CSQLite"]
    ),
    .testTarget(
        name: "FifiCoreTests",
        dependencies: ["FifiCore"]
    )
]

// The app target needs AppKit/SwiftUI; FifiCore + tests also build on Linux.
#if os(macOS)
products.append(.executable(name: "fifi", targets: ["Fifi"]))
targets.append(
    .executableTarget(
        name: "Fifi",
        dependencies: ["FifiCore"],
        path: "Sources/Fifi"
    )
)
#endif

let package = Package(
    name: "Fifi",
    platforms: [
        .macOS(.v13)
    ],
    products: products,
    targets: targets
)
