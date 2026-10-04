# Architecture

## The one structural idea

`AbloxCore` imports nothing from Apple. Not SwiftUI, not RealityKit, not
Network, not even `simd`.

Everything that can be decided without pixels or sockets lives there: the data
model, the wire format, the rule engine, and character collision. That code
builds and runs on Linux, which means it can be tested in CI in milliseconds
instead of on a device.

This is not architecture for its own sake. Two bugs in this codebase were found
by tests that could only exist because of it:

1. `AvatarProfile.generated(for:)` indexed individual UUID bytes, so any two
   peers whose ids shared a prefix got identical avatars. Now it hashes all
   sixteen bytes with FNV-1a under per-attribute seeds — and deliberately not
   with `Hasher`, which is randomly seeded per process and would make the same
   player look different on every iPad.
2. `BoundingBox.intersects` is inclusive, so a player standing exactly on a
   floor counted as penetrating it — and the horizontal collision pass then
   treated the floor as a wall and shoved them backwards off it. Collision now
   uses `penetrates(_:epsilon:)`, which requires real interpenetration.

Neither would have been obvious on a device. Both took seconds to find.

## Layers

```
┌──────────────────────────────────────────────┐
│ UI/        SwiftUI                           │  menu, lobby, avatar, HUD
├──────────────────────────────────────────────┤
│ Engine/    RealityKit                        │  entities, avatars, viewport
├──────────────────────────────────────────────┤
│ Net/       Network.framework                 │  TLS, Bonjour, host, client
├──────────────────────────────────────────────┤
│ AbloxCore/ Foundation only                   │  model, protocol, rules, physics
└──────────────────────────────────────────────┘
```

Dependencies point downward only. `AbloxCore` knows nothing about the layers
above it, which is what lets the Studio reuse it unchanged.

## Data model

A `WorldDocument` holds a **flat array** of `BlockData` with `parentID` links,
not a nested tree.

Flat storage means a `WorldDelta` can name one block by id, and reparenting is
a single field edit rather than moving a subtree. The tree is reconstructed on
demand by `children(of:)`, `ancestors(of:)` and `subtree(of:)` — all of which
are cycle-safe, because a malformed document must not hang the Explorer.

`BlockData.transform` is always **local to its parent**, matching RealityKit's
entity hierarchy, so `WorldScene` can attach child entities directly without
recomputing anything. `worldTransform(of:)` composes the chain when world space
is actually needed.

`BlockData` decodes leniently: a world written by an older build that predates
`behavior` or `tags` loads with the same defaults `init` uses, rather than
failing the whole document.

## The rule engine

`EventRule` is a fixed vocabulary of triggers and actions, not a scripting
language. Typing code on an iPad is miserable; a closed vocabulary can be
edited entirely with pickers, and it cannot contain a syntax error or an
infinite loop.

`EventMachine` evaluates rules **on the host only**, and has no clock of its
own — time is passed in. That is what makes every branch testable:

```swift
var machine = EventMachine(world: world, startTime: 0)
_ = machine.handle(.roundStarted)
XCTAssertTrue(machine.advance(to: 0.5).isEmpty)
XCTAssertFalse(machine.advance(to: 1.1).isEmpty)
```

It covers cooldowns, fire limits, per-player collectible tracking, proximity
with 15% hysteresis (so a player wobbling on the boundary does not machine-gun
a rule), a kill plane, and one level of `scoreReached` cascade — enough for
"collect ten coins to win" without risking a rule loop.

Common behaviours are built in rather than requiring a rule: `.collectible`,
`.hazard`, `.checkpoint`, `.goal` and `.spawn` work with no authoring at all.
Authored rules layer on top.

## Character movement

Two stages, both in core:

1. `CharacterSolver.step` — intent to velocity. Camera-relative stick,
   diagonal normalisation, air control, ground friction, rate-limited turning,
   terminal velocity, and no double jumps.
2. `WorldCollider.resolve` — velocity to position, resolved against the world.
   Axis-separated, horizontal before vertical, with step-up for shallow
   obstacles.

Deliberately **not** RealityKit physics for the player. A dynamic rigid body is
simulated independently on each device and drifts within seconds. Solving
kinematically against the shared document means every iPad computes the same
answer from the same inputs, with no reconciliation machinery at all.

Blocks still use RealityKit physics — an unanchored crate is a dynamic body.
The player is the special case, because the player is the thing that has to
agree across devices. A game only turns RealityKit physics on when its world
has an unanchored part at all; otherwise it would simulate a static body per
part every frame for nothing.

### Big worlds: `WorldIndex`

`WorldDocument.worldBounds(of:)` searches the block list for the block and for
each ancestor, so asking it about every block is quadratic. The collider, the
camera and the host's NPCs used to do exactly that every frame, which is what
pulled worlds of a thousand parts well under 30 fps. `WorldIndex` measures every
block once (a dictionary makes parent lookups constant) and keeps a 4 m grid on
the ground plane, so a question like "what does this box touch" only looks at
the nearby cells. Answers come back in document order, so "the first solid the
player sinks into" is the same block it always was — `WorldIndexTests` checks
the collider step against the full-list version.

`WorldIndexCache` keeps the index up to date as the round changes the world.
`WorldDocument.blockRevision` is new after every change to `blocks` (copies of a
world share it until one changes; it is never saved and never part of
equality), so "nothing changed" costs one comparison. When something has, each
block is compared with the few fields its entry is made from — not whole
blocks, so a recoloured or relabelled block costs nothing — and blocks added on
the end, blocks moved where they stand and everything hanging from a moved
block (a character model's parts) are folded in; anything else is a rebuild.
The cache never holds the block list itself: when it did, every change to the
world copied every block. For the same reason `blocks` is changed through a
`_modify` accessor rather than `didSet`, which across modules copies the whole
array on every change. (2.4: a 300-character game builds its models about four
times faster.)

Even comparing a few fields of every block was too much when a script changes
blocks one at a time: sixty characters walked by a script made the host check
every block sixty times a tick. So the world keeps a short `BlockJournal` of
the blocks changed one at a time since a revision (`insert`, `update` and
`mutate` write to it; anything else clears it), and the cache looks only at
those when the journal goes back to its own revision. Revisions are never
reused, so a journal from another copy of the world is never taken for this
one. `block(id:)` and `index(of:)` go through `BlockOrders`, an id → position
map shared by copies and checked on every answer, caught up from the same
journal. (2.6: the host's ticks in a 3,000-part world with sixty walking
characters went from about 230 ms to 7 ms in a debug build.)

## Rendering

`WorldScene` **reconciles** rather than rebuilds. The Studio calls `sync` on
every frame of a drag and multiplayer calls it on every delta; tearing down two
hundred entities at 60 Hz would drop frames and throw away RealityKit's
internal caches. Untouched blocks are skipped by comparing against the last
applied `BlockData`.

Meshes are cached one per `BlockShape`, always generated at unit size and
scaled by the entity transform. So `BlockShape.unitBounds` is the single source
of truth for how big a block is — the same numbers used by picking, by the
physics collider, and by `WorldCollider`.

Materials are shared too, one per colour and material kind, so a world
painted from a dozen colours hands RealityKit a dozen materials rather than
one per part.

### Drawing a big game in few pieces

RealityKit draws each entity on its own, twice with the sun's shadows, and on
an iPad the number of entities cost more than their size. In a game (not the
Studio) `StillPartBaker` bakes the parts that stay put into merged meshes:
parts at the top of the map into one mesh per 48 m patch and per colour and
material, parts hung from a block — a character's eighteen — into one mesh per
colour under that block, so they still move with it. `RenderMerging.canMerge`
says which parts qualify (seen, solid-looking, anchored, no picture, light
or animation, and nothing the renderer moves or makes vanish itself). Words
over a part (`label`) are drawn over the view from where its entity is, baked
or not, so they do not keep it out.
The vertices are the very meshes a part on its own is drawn with, read back
from RealityKit (`UnitShapes`), with each part's pattern repeats baked into its
texture coordinates, so a baked part looks exactly as it did. Parts of a plain
material (no pattern drawn on it) take their colour from a palette instead:
one row of spots on a texture (`ColorPalette`), each part's vertices pointing
at its colour's spot, sampled exactly. Their mesh is then one per kind of
material rather than one per colour, with the same kind of material a part has
on its own — so a character of six colours is one mesh, not six. A part in a
palette mesh whose colour alone changes (`RenderMerging.onlyRecoloured`) stays
in it: it is given a spot of its own, and each later change paints that spot
again in the texture in place (`TextureResource.replace`), so a dance floor
changing colour on every beat stays one mesh. The launch check holds the whole
scene still, photographs the view merged, merged again (the noise floor) and
part by part, and prints how far apart the pictures are, the mean shift of
each colour and where on the screen they differ; at the end it draws the sky
alone, the most that simulator draws at all.

Players are drawn the same way at a smaller scale: whatever only ever moves
as a whole — a face, a hat, a pet, a ride, a weapon — has its parts that share
a plain material merged into one mesh when it is built (`RigidParts`), the
parts' own vertices placed where they were and drawn with the very material
they had; a part that turns by itself (a hat's propeller) is left out. The
frame-rate run dresses eight players in every kind of gear and checks every
hat, face and pet merged against the same one unmerged (`BenchmarkCrowd`).

A baked part keeps its entity, switched off. A change that shows (`looksTheSame`
ignores names, tags, scores and words), an effect that tints, slides or hides it, or a
child hung from it takes it out: its mesh is rebuilt without it, and until then
it is drawn by the old mesh, so it is never drawn twice or missing for a frame.
It may go back in once it has stayed the same for a while — 3 s on the map, 0.6 s
on a character, and longer each time it is taken out again, so a part a script
keeps changing settles as a part of its own. Meshes are rebuilt between
frames within a few milliseconds a frame. Blocks see-through to the end (a
character's root) are not handed to the GPU at all. When the world has a part
that can fall, RealityKit physics needs every part's own entity, and nothing is
baked.

The play screen is not rebuilt for every touch. The stick, the buttons, the
camera drag and a game controller write into `PlayControls`, a class the 3D
view reads every frame; as SwiftUI state, every movement of a thumb (and every
frame a controller's stick was held) rebuilt the whole play screen. The
compass and a map that turns with the camera follow `shownYaw`, at most
fifteen times a second, in small views of their own. The map draws the world
as one picture (`MapFootprint`), made at most every two seconds from an index
kept up to date change by change; it used to measure every block from scratch
and draw thousands of rectangles whenever anything moved.

The game no longer rebuilds its screen for every change either.
`SessionCoordinator` applies the world's changes in place as they arrive
(`WorldDeltaInbox`, one hop to the main thread per burst), writes down which
blocks changed (`WorldChangeLog`), and tells SwiftUI at most ten times a
second (`PublishThrottle`). The 3D view takes the changes every frame and
`WorldScene.sync(to:changes:index:physicsEnabled:)` looks at only those
blocks. Words over blocks and blocks that move by themselves are looked for
four times a second, and only the nearest few dozen (`labelLimit`,
`animationRange`) are followed every frame.

### Graphics settings

Settings → Graphics picks **Auto**, **High**, **Medium**, **Low** or
**Lightest** (`GraphicsQuality`, `GraphicsProfile`). Lower levels shorten or drop the sun's
shadows, draw at a lower resolution, use plain boxes and fewer-sided spheres
and cylinders, turn off HDR and depth of field, and stop drawing parts (and
characters) beyond a view distance — measured to each part's nearest edge, so
the ground under you never disappears. **Auto** starts at High;
`FrameRateGovernor` steps down after two slow seconds (one under 16 fps) and
only steps back up after a long fast run, never to a level that was too slow
in the last minute. Before giving up a level it gives up pixels: a second
under 50 fps draws 5 % fewer, down to 80 %, and fast seconds give them back, so
a game sits at a smooth 60 with its shadows and shapes where it can.
**Show frame rate** puts a small counter at the top of the play screen.

In a game the parts get no RealityKit colliders at all: taps are picked with
the view's ray against `WorldIndex`, as shots and the camera already were.

`ARView` in `.nonAR` mode rather than `RealityView`, so the app runs on
iPadOS 17 as well as 18, and because `ARView` exposes the
`SceneEvents.Update` subscription the character controller needs.

## Concurrency

`AbloxHost`, `AbloxClient` and `AbloxBrowser` each own a private serial
`DispatchQueue` and deliver callbacks on it. `SessionCoordinator` is
`@MainActor` and is the single place that hops to the main thread. No view ever
touches a `DispatchQueue`.

## What is where

| Concern | File |
|---|---|
| Vectors, rotations, bounds, rays | `AbloxCore/Math.swift` |
| A part | `AbloxCore/BlockData.swift` |
| A world | `AbloxCore/WorldDocument.swift` |
| Triggers and actions | `AbloxCore/EventRule.swift` |
| Rule evaluation | `AbloxCore/EventMachine.swift` |
| Character collision | `AbloxCore/WorldCollider.swift` |
| Bounds and a grid for big worlds | `AbloxCore/WorldIndex.swift` |
| Graphics levels and auto quality | `AbloxCore/Graphics.swift` |
| Which parts merge, and the merged vertices | `AbloxCore/MeshMerging.swift` |
| World changes waiting for the main thread | `AbloxCore/LiveWorld.swift` |
| The frame-rate test world | `AbloxCore/RenderBenchmark.swift` |
| Merged meshes in a game | `Engine/MergedMeshes.swift` |
| The stick, buttons and camera, read every frame | `Engine/PlayControls.swift` |
| The map's picture of the world | `UI/Game/MapFootprint.swift` |
| Packet vocabulary | `AbloxCore/Packets.swift` |
| Codec and reassembly | `AbloxCore/WireFormat.swift` |
| TLS and room codes | `Net/TLSPeerSecurity.swift` |
| Message framing | `Net/AbloxFramer.swift` |
| Hosting | `Net/AbloxHost.swift` |
| Joining | `Net/AbloxClient.swift` |
| Discovery | `Net/AbloxBrowser.swift` |
| UI-facing session state | `Net/SessionCoordinator.swift` |
| Block → entity | `Engine/BlockEntityFactory.swift` |
| Scene reconciliation | `Engine/WorldScene.swift` |
| Avatars | `Engine/AvatarEntity.swift` |
| The play surface | `Engine/GameViewport.swift` |
