// swift-tools-version: 5.9
import PackageDescription

// This manifest exists purely so that `AbloxCore` — the portable data model,
// wire format and rule engine — can be built and unit-tested off-device,
// including on Linux CI. It points at exactly the same source files the iPad
// app compiles, so there is one implementation, not a copy.
//
// The shipping app is `Ablox.swiftpm`, which has its own manifest and is what
// you open in Swift Playgrounds on iPad.
let package = Package(
    name: "AbloxCore",
    products: [
        .library(name: "AbloxCore", targets: ["AbloxCore"])
    ],
    targets: [
        .target(
            name: "AbloxCore",
            path: "Ablox.swiftpm/Sources/AbloxCore"
        ),
        .testTarget(
            name: "AbloxCoreTests",
            dependencies: ["AbloxCore"],
            path: "Tests/AbloxCoreTests"
        )
    ]
)
