// swift-tools-version: 5.9

// This is the shipping app. Open `Ablox.swiftpm` in Swift Playgrounds on iPad
// (or in Xcode) and press Run.
//
// The repository root also has a Package.swift. That one exists only to build
// and unit-test `Sources/AbloxCore` off-device — it points at these same
// source files, so there is one implementation rather than a copy.
//
// Deliberately ONE target. Swift Playgrounds App projects are built and
// navigated as a single module, and splitting the sources into library targets
// here buys nothing on device while adding a way for the manifest to fail. The
// off-device test package gets its module boundary from its own manifest
// instead, which is why no file in Sources/ imports AbloxCore.

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
            // No `appIcon:` on purpose. The parameter is optional, and two
            // guesses at `PlaceholderIcon`'s member names (`.hammer`, then
            // `.cube`) were both rejected on device — a wrong one does not
            // degrade to a default icon, it stops the manifest compiling and
            // the project will not open at all. The drawn Ablox cube is in
            // `design/AppIcon.png`; set it from Swift Playgrounds' own
            // app-settings screen, which writes the asset catalogue itself.
            accentColor: .presetColor(.cyan),
            supportedDeviceFamilies: [
                .pad,
                .phone
            ],
            // Plain values, not calls: `InterfaceOrientation` exposes static
            // properties, so `.portrait(upsideDown: false)` is a type error.
            // Upside-down portrait is simply left out of the list instead.
            supportedInterfaceOrientations: [
                .landscapeRight,
                .landscapeLeft,
                .portrait
            ],
            capabilities: [
                // Required on iOS 14+ before Bonjour browsing or any local
                // connection is permitted. Without the declared service type,
                // NWBrowser fails with a policy-denied DNS error rather than
                // simply finding nothing.
                .localNetwork(
                    purposeString: "Ablox finds nearby iPads so you can build and play in the same world together. Nothing leaves your local network.",
                    bonjourServiceTypes: ["_ablox._tcp"]
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
