# Icons and brand

## Where icons come from

Ablox uses **SF Symbols**, addressed through a named vocabulary rather than
inline strings.

```swift
Image(icon: .trophy)          // not Image(systemName: "trophy.fill")
Label("Play", icon: .gamepad)
```

`AbloxIcon` lives in `AbloxCore`, so it is shared with Ablox Studio and tested
off-device alongside the rest of the core. It carries the 232 names from the
project icon sheet, so the design and the code use one set of words: an icon
called `heart-filled` on the sheet is `AbloxIcon.heartFilled` in Swift.

### Why not inline `systemName:` strings

They were scattered across a dozen view files. A typo produced a silently blank
space at runtime — no compiler error, no crash, just a gap — and there was no
way to answer "which icons does this app use". One enum makes the vocabulary a
compile-time contract and gives a single place to swap in custom artwork later.

`AbloxIconTests` enforces it: every icon resolves to a non-empty symbol, names
are unique and kebab-case, and the icons the shipping UI depends on are listed
explicitly, so deleting one fails a test instead of leaving a blank square on
someone's iPad.

## Where SF Symbols isn't enough

43 of the 232 icons have **no honest SF Symbol equivalent**. They are mapped to
the closest stand-in and flagged:

```swift
AbloxIcon.potion.hasNativeEquivalent   // false
AbloxIcon.needingCustomArtwork         // the full list, in vocabulary order
```

They fall into four groups:

| Group | Examples | Why |
|---|---|---|
| Brand marks | `youtube`, `twitch`, `discord`, `spotify` | Apple will never ship these |
| Facial expressions | `sad`, `laugh`, `angry`, `surprised`, `thinking`, `wink`, `cool` | SF Symbols has `face.smiling` and little else |
| Game objects | `potion`, `pickaxe`, `scythe`, `grenade`, `chest`, `coin`, `sword`, `bow` | Not a productivity vocabulary |
| Hand gestures | `handshake`, `high-five`, `fist`, `peace`, `heart-hands` | Only a handful exist |

**This is the list worth drawing first.** Custom art for the other 189 would
mostly reproduce what the system already provides — and would lose Dynamic
Type, weight matching, optical alignment and the automatic SF Symbols
localisation that comes free with `Image(systemName:)`.

A test asserts the stand-ins stay under a third of the vocabulary. If that ever
fails, leaning on SF Symbols has become the wrong call and the registry should
point at a real asset catalogue instead.

### Swapping in custom artwork

`AbloxIcon.rawValue` is the sheet's own kebab-case name, so an asset bundle can
be keyed on it directly with no translation step. The change is confined to
`symbolName`:

```swift
public var symbolName: String { ... }        // today: SF Symbol names
// becomes
Image(icon:) → Image(rawValue, bundle: .module)   // when assets exist
```

No view file changes.

## The brand mark

`AbloxMark` draws the isometric cube as a SwiftUI `Shape` — three
quadrilaterals and a diamond aperture — rather than bundling a PNG.

Drawing it buys three things a bitmap would not:

- Sharp at every size, from a 16pt row to a full-screen splash, with no
  `@2x`/`@3x` set to keep in sync.
- It inherits the foreground style, so one mark works on the dark sidebar and
  inverted on a light sheet.
- The Playground stays readable Swift. A binary is the one thing you cannot
  inspect or diff on an iPad.

Two details in the geometry are easy to get wrong and are commented in place:
the aperture winds the same direction as the face around it, so it needs
**even-odd** fill or it vanishes under the default non-zero rule; and the hole
is scaled about the face centre by a single factor, because scaling width and
height independently reads as a squashed diamond rather than a hole in a
surface.

`AbloxLockup` pairs the mark with the wordmark, and is used by both apps so
they present one brand rather than two near-misses.

## The app icon

The one genuine binary in each bundle: `Sources/Resources/Assets.xcassets`.
iOS requires a real image file for the home screen — it is the only thing the
app cannot render at runtime.

Both are generated at 1024×1024 from the same geometry as `AbloxMark`
(`scripts/make-app-icon.py`), so the drawn mark and the home-screen icon cannot
drift apart:

- **Ablox** — light cube on a near-black tile.
- **Ablox Studio** — the inverted variation: dark cube on a light tile, so the
  two are distinguishable at a glance while plainly the same mark.

Both are lit from the upper left, top face lightest. Regenerating is
`python3 scripts/make-app-icon.py`.

## Notes on the source sheet

Three things surfaced while turning the sheet into a compile-checked
vocabulary. None affect the artwork; they matter because the names are now
code.

1. **Counts.** Each of the six sections holds **40** labels, not the 30 its
   header states, and the total is 240 rather than the 230 in the corner.
2. **Eight names repeat across sections**, so there are 232 distinct icons:
   `trophy` and `medal` (Social + Game), `crown`, `diamond`, `rocket`, `gift`
   (Game + Misc), `key` and `keyboard` (Game + Device). The registry keeps one
   of each — duplicate raw values would not compile.
3. **Eight labels look like transcription slips**, corrected here:
   `clixsperbeard`→`clapperboard`, `notification-ball`→`notification-bell`,
   `thumbs-poem`→`thumbs-down`, `snowflcke`→`snowflake`, `pecent`→`percent`,
   `hourgiass`→`hourglass`, `pienet`→`planet`, `paper-yane`→`paper-plane`.

If the sheet is regenerated, keeping these in step matters: `AbloxIconTests`
asserts the count is 232, so a divergence fails the build rather than going
unnoticed.
