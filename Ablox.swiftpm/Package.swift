// swift-tools-version: 5.9

// This is the shipping app. Open `Ablox.swiftpm` in Swift Playgrounds on iPad
// (or in Xcode) and press Run.
//
// The repository root also has a Package.swift. That one exists only to build
// and unit-test `Sources/AbloxCore` off-device — it points at these same
// source files, so there is one implementation rather than a copy.

import PackageDescription
import AppleProductTypes

let package = Package(
    name: "Ablox",
    platforms: [
        .iOS("17.0")
    ],
    products: [
        .iOSApplication(
            name: "Ablox",
            targets: ["AbloxApp"],
            bundleIdentifier: "com.ablox.client",
            teamIdentifier: "",
            displayVersion: "1.0",
            bundleVersion: "1",
            appIcon: .placeholder(icon: .cube),
            accentColor: .presetColor(.cyan),
            supportedDeviceFamilies: [
                .pad,
                .phone
            ],
            supportedInterfaceOrientations: [
                .landscapeRight,
                .landscapeLeft,
                .portrait(upsideDown: false)
            ],
            capabilities: [
                // Required on iOS 14+ before Bonjour browsing or any local
                // connection is permitted. Without the declared service type,
                // NWBrowser fails with a policy-denied DNS error rather than
                // simply finding nothing.
                .localNetwork(
                    purposeString: "Ablox finds nearby iPads so you can build and play in the same world together. Nothing leaves your local network.",
                    bonjourServices: ["_ablox._tcp"]
                )
            ]
        )
    ],
    targets: [
        .executableTarget(
            name: "AbloxApp",
            path: "Sources"
        )
    ]
)
