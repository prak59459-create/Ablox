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
agree across devices.

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
