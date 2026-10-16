#!/usr/bin/env python3
"""Writes Engine/IconArt.swift from the drawn icons in design/icons.

The 56 icons drawn for Ablox NEXT (the dock, the closet, the categories, the
HUD and Studio's tools) are kept inside the app as text, the way the cue
recordings are (scripts/cue-recordings.py): a Swift Playground stays readable
Swift with no resource bundle, and an update carries them like any other
source file.

Each icon is a 128 px WebP (iOS 14 and later decode WebP), base64 in a raw
string. Run from the repository root:

    python3 -I scripts/icon-art.py            # Ablox.swiftpm
    python3 -I scripts/icon-art.py --check    # fails if the Swift is stale

Studio's copy of Engine/IconArt.swift is the same file.
"""
import base64
import hashlib
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ART = os.path.join(ROOT, "design", "icons")
OUT = os.path.join(ROOT, "Ablox.swiftpm", "Sources", "Engine", "IconArt.swift")

# What to show while an icon cannot be read: an SF Symbol of the same idea.
FALLBACK = {
    "badge-difficulty": "gauge.with.dots.needle.50percent", "badge-downloaded": "arrow.down.circle.fill",
    "badge-new": "sparkles", "badge-players": "person.2.fill", "badge-time": "clock.fill", "bell": "bell.fill",
    "cat-battle": "shield.lefthalf.filled", "cat-horror": "moon.stars.fill", "cat-minigame": "puzzlepiece.fill",
    "cat-obby": "figure.run", "cat-popular": "flame.fill", "cat-roleplay": "house.fill", "cat-sim": "leaf.fill",
    "cat-vehicle": "car.fill", "coin": "circle.fill", "continue": "play.circle.fill", "create-script": "chevron.left.forwardslash.chevron.right",
    "create-sound": "speaker.wave.2.fill", "create-studio": "paintbrush.pointed.fill", "create-template": "square.grid.2x2.fill",
    "create-world": "globe.americas.fill", "create": "hammer.fill", "family": "figure.2.and.child.holdinghands",
    "friends": "person.2.fill", "heart": "heart.fill", "home": "house.fill", "hud-action": "hand.tap.fill",
    "hud-camera": "camera.fill", "hud-chat": "bubble.left.fill", "hud-emote": "face.smiling.fill", "hud-jump": "arrow.up.circle.fill",
    "hud-menu": "line.3.horizontal", "hud-players": "person.3.fill", "level": "star.circle.fill", "lock": "lock.fill",
    "mascot": "cube.fill", "me-aura": "sun.max.fill", "me-emote": "hand.wave.fill", "me-face": "face.smiling",
    "me-hat": "crown.fill", "me-pet": "pawprint.fill", "me-shirt": "tshirt.fill", "me-trail": "sparkle",
    "me-trophies": "trophy.fill", "me": "person.crop.circle.fill", "mission": "checklist", "pattern": "square.grid.3x3.fill",
    "play": "gamecontroller.fill", "settings": "gearshape.fill", "suggestion": "lightbulb.fill",
    "tool-move": "arrow.up.and.down.and.arrow.left.and.right", "tool-paint": "paintbrush.fill",
    "tool-play": "play.fill", "tool-rotate": "arrow.triangle.2.circlepath", "tool-scale": "arrow.up.left.and.arrow.down.right",
    "tool-select": "cursorarrow",
}

# Swift names: the file's name in camel case; `continue` is a keyword.
SPECIAL = {"continue": "carryOn"}


def case_name(name: str) -> str:
    if name in SPECIAL:
        return SPECIAL[name]
    head, *rest = name.split("-")
    return head + "".join(p[:1].upper() + p[1:] for p in rest)


def wrapped(text: str, width: int = 100) -> str:
    return "\n".join(text[i:i + width] for i in range(0, len(text), width))


def render() -> str:
    names = sorted(f[:-5] for f in os.listdir(ART) if f.endswith(".webp"))
    missing = [n for n in names if n not in FALLBACK]
    if missing:
        sys.exit(f"no fallback symbol for: {', '.join(missing)}")
    blobs = {}
    for n in names:
        with open(os.path.join(ART, n + ".webp"), "rb") as f:
            blobs[n] = f.read()
    total = sum(len(b) for b in blobs.values())
    out = []
    out.append("import Foundation\nimport SwiftUI\nimport UIKit\nimport AbloxCore\n")
    out.append("// Written by scripts/icon-art.py from design/icons. Do not edit by hand:")
    out.append("// change the art there and run it again.\n")
    out.append(f"/// The {len(names)} icons drawn for Ablox: the dock, the closet, the game")
    out.append("/// categories, the play screen and Studio's tools. Each is a 128 px WebP in")
    out.append(f"/// base64, {total // 1024} KB for all of them, kept here so the Playground needs no")
    out.append("/// resource bundle (see docs/icons.md). An icon that cannot be read shows its")
    out.append("/// SF Symbol (`fallbackSymbol`) instead.")
    out.append("public enum DrawnIcon: String, CaseIterable, Sendable, Identifiable {")
    for n in names:
        out.append(f'    case {case_name(n)} = "{n}"')
    out.append("\n    public var id: String { rawValue }\n")
    out.append("    /// The SF Symbol of the same idea.")
    out.append("    public var fallbackSymbol: String {")
    out.append("        switch self {")
    for n in names:
        out.append(f'        case .{case_name(n)}: return "{FALLBACK[n]}"')
    out.append("        }\n    }\n}\n")
    out.append("enum IconArt {\n")
    out.append("    private static let lock = NSLock()")
    out.append("    private static var decoded: [DrawnIcon: UIImage] = [:]\n")
    out.append("    /// The icon's picture, decoded the first time it is asked for.")
    out.append("    static func image(_ icon: DrawnIcon) -> UIImage? {")
    out.append("        lock.lock()")
    out.append("        defer { lock.unlock() }")
    out.append("        if let image = decoded[icon] { return image }")
    out.append("        guard let data = Data(base64Encoded: text(for: icon), options: .ignoreUnknownCharacters),")
    out.append("              let image = UIImage(data: data, scale: 2) else { return nil }")
    out.append("        decoded[icon] = image")
    out.append("        return image")
    out.append("    }\n")
    out.append("    /// For a check that every icon reads: its bytes' SHA-256, as written.")
    out.append("    static let digests: [DrawnIcon: String] = [")
    for n in names:
        out.append(f'        .{case_name(n)}: "{hashlib.sha256(blobs[n]).hexdigest()}",')
    out.append("    ]\n")
    out.append("    static func text(for icon: DrawnIcon) -> String {")
    out.append("        switch icon {")
    for n in names:
        out.append(f"        case .{case_name(n)}:")
        out.append('            return """')
        out.append(wrapped(base64.b64encode(blobs[n]).decode()))
        out.append('"""')
    out.append("        }\n    }\n}\n")
    out.append("/// A drawn icon at a size, or its symbol while it cannot be drawn.")
    out.append("public struct DrawnIconImage: View {")
    out.append("    private let icon: DrawnIcon")
    out.append("    private let size: CGFloat\n")
    out.append("    public init(_ icon: DrawnIcon, size: CGFloat = 32) {")
    out.append("        self.icon = icon")
    out.append("        self.size = size")
    out.append("    }\n")
    out.append("    public var body: some View {")
    out.append("        picture")
    out.append("            .aspectRatio(contentMode: .fit)")
    out.append("            .frame(width: size, height: size)")
    out.append("            .accessibilityHidden(true)")
    out.append("    }\n")
    out.append("    private var picture: Image {")
    out.append("        if let image = IconArt.image(icon) { return Image(uiImage: image).resizable().interpolation(.high) }")
    out.append("        return Image(systemName: icon.fallbackSymbol).resizable()")
    out.append("    }")
    out.append("}\n")
    return "\n".join(out)


def main() -> None:
    text = render()
    if "--check" in sys.argv:
        with open(OUT, encoding="utf-8") as f:
            if f.read() != text:
                sys.exit("Engine/IconArt.swift is out of date: run python3 -I scripts/icon-art.py")
        print("IconArt.swift is up to date")
        return
    with open(OUT, "w", encoding="utf-8") as f:
        f.write(text)
    print(f"wrote {os.path.relpath(OUT, ROOT)} ({len(text) // 1024} KB)")


if __name__ == "__main__":
    main()
