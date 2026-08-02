// swift-tools-version: 5.10
import PackageDescription

var products: [Product] = []
var dependencies: [Package.Dependency] = [
    .package(path: "../leafiy-ui")
]
var targets: [Target] = [
    .systemLibrary(name: "CSQLite", path: "Sources/CSQLite"),
    .target(
        name: "FifiCore",
        dependencies: [
            "CSQLite",
            .product(name: "LeafiyUICore", package: "leafiy-ui")
        ]
    ),
    .testTarget(
        name: "FifiCoreTests",
        dependencies: [
            "FifiCore",
            .product(name: "LeafiyUICore", package: "leafiy-ui")
        ]
    )
]

// The app target needs AppKit/SwiftUI; FifiCore + tests also build on Linux.
#if os(macOS)
products.append(.executable(name: "fifi", targets: ["Fifi"]))
targets.append(
    .executableTarget(
        name: "Fifi",
        dependencies: [
            "FifiCore",
            .product(name: "LeafiyUI", package: "leafiy-ui"),
            .product(name: "LeafiyUICore", package: "leafiy-ui")
        ],
        path: "Sources/Fifi",
        resources: [.process("Resources")]
    )
)
targets.append(
    .testTarget(
        name: "FifiTests",
        dependencies: [
            "Fifi",
            .product(name: "LeafiyUICore", package: "leafiy-ui")
        ]
    )
)
#endif

let package = Package(
    name: "Fifi",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v14)
    ],
    products: products,
    dependencies: dependencies,
    targets: targets
)
