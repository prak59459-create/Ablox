// swift-tools-version: 5.9

// This is the shipping app. Open `Ablox.swiftpm` in Swift Playgrounds on iPad
// (or in Xcode) and press Run.
//
// The repository root also has a Package.swift. That one exists only to build
// and unit-test `Sources/AbloxCore` off-device — it points at these same
// source files, so there is one implementation rather than a copy.
//
// Two targets: AbloxCore (the portable core, also built and tested
// off-device by the root package) and the app. The core is its own module on
// both, so every file outside Sources/AbloxCore says `import AbloxCore`.

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
            displayVersion: "2.1",
            bundleVersion: "10",
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
                ),
                // Only for reading a room's QR code (Play → Join with an
                // invitation). Asked for the first time the camera is used.
                .camera(purposeString: "Ablox uses the camera only to read a friend's room QR code. Nothing is recorded or kept.")
            ]
        )
    ],
    targets: [
        // Two modules rather than one, for the build on an iPad: each compile
        // job then holds only its own module's source, with the other one read
        // back as a small compiled summary. One module of this size had the
        // compiler holding the whole app in every job at once, which is what
        // ran an older iPad out of memory and made a build take minutes.
        //
        // The library target's name must differ from the app product's
        // ("Ablox"); Swift Playgrounds refuses a target and a product that
        // share one.
        //
        // `-gnone`: no debug information. Nothing on an iPad reads it, and
        // making it was about a fifth of the build (docs/ipad-build.md). It
        // goes to the compiler itself (`-Xfrontend`): package flags come
        // before the `-g` of a debug build, so given to the driver it would
        // lose, and the last one wins.
        .target(
            name: "AbloxCore",
            path: "Sources/AbloxCore",
            swiftSettings: [.unsafeFlags(["-Xfrontend", "-gnone"])]
        ),
        .executableTarget(
            name: "AbloxApp",
            dependencies: ["AbloxCore"],
            path: "Sources",
            exclude: ["AbloxCore"],
            swiftSettings: [.unsafeFlags(["-Xfrontend", "-gnone"])]
        )
    ]
)
