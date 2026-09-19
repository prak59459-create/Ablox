# Ablox

A sandbox game platform for iPad, built to run in **Swift Playgrounds**. Build
worlds, play them with friends in the same room, no server and no account.

Two apps make up the platform:

| Repository | App | What it does |
|---|---|---|
| **this one** | `Ablox.swiftpm` | The player client: main menu, world library, 3D play, multiplayer |
| [`Ablox-studio`](https://github.com/prak59459-create/Ablox-studio) | `AbloxStudio.swiftpm` | The level editor: place parts, edit properties, wire up events |

## Running it

Open `Ablox.swiftpm` in Swift Playgrounds on iPad (iPadOS 17 or later) and
press Run. It also opens in Xcode 15+.

On first launch iPadOS asks for **Local Network** permission. Say yes — without
it, Ablox cannot see other iPads and the Play tab stays empty.

## Two Package.swift files, on purpose

- `Ablox.swiftpm/Package.swift` — the shipping app. This is what you open.
- `Package.swift` (repo root) — builds and tests `AbloxCore` alone, on any
  platform including Linux CI.

The root manifest points its target at `Ablox.swiftpm/Sources/AbloxCore`, the
same files the app compiles. There is one implementation, not a vendored copy.

```
swift test        # 296 tests, no device or simulator needed
```

`AbloxCore` has no `import SwiftUI`, `RealityKit`, `Network` or even `simd`.
That is what makes the data model, wire format, rule engine and character
collision testable off-device — and it is why the bug where two peers whose
UUIDs share a prefix got identical avatars was caught by a test rather than by
a child on a sofa.

## How it fits together

```
Ablox.swiftpm/Sources/
├── AbloxCore/     portable: no Apple frameworks, fully unit-tested
│   ├── Math            Vec3, Quat, Transform3D, BoundingBox, Ray
│   ├── BlockData       one authored part
│   ├── WorldDocument   the whole world, flat blocks + parentID links
│   ├── EventRule       triggers and actions
│   ├── EventMachine    host-authoritative rule evaluation
│   ├── WorldCollider   deterministic character collision
│   ├── Packets         wire vocabulary and binary header
│   └── WireFormat      codec + stream reassembly
├── Net/           Network.framework: TLS, Bonjour, host, client
├── Engine/        RealityKit: entities, avatars, the play viewport
└── UI/            SwiftUI: menu, lobby, avatar editor, HUD
```

Further reading:

- [`docs/architecture.md`](docs/architecture.md) — why the pieces are split this way
- [`docs/networking.md`](docs/networking.md) — the protocol, and the security model in plain terms
- [`docs/localization.md`](docs/localization.md) — English and Japanese, and why there is no `.lproj`
- [`docs/ipad-build.md`](docs/ipad-build.md) — the errors only an iPad can report
- [`docs/roadmap.md`](docs/roadmap.md) — what is built and what is not

## Two decisions worth knowing about

**TLS uses a pre-shared key, not a certificate.** Swift Playgrounds on iPad
cannot obtain a `sec_identity_t`, so certificate-based TLS would mean telling
clients to trust any certificate — TLS with the security taken out. Instead the
host shows a six-character room code; both sides derive the session key from it
with HMAC-SHA256. That gives real TLS 1.3 encryption *and* mutual
authentication. The trade-offs are written out honestly in
[`docs/networking.md`](docs/networking.md) — the code is the whole secret, and
there is no forward secrecy if it leaks.

**Character movement is solved in plain Swift, not RealityKit physics.** A
dynamic rigid body would be simulated independently on each iPad and drift
apart within seconds. `WorldCollider` resolves movement deterministically
against the shared `WorldDocument`, so every device computes the same answer —
and it has 16 tests, including one that walks a player at a pillar from twelve
directions and asserts they never end up inside it.

## Status

Playable end to end: create a world, play it solo, host it, join a friend,
collect coins, hit checkpoints, reach a goal, chat. See the roadmap for what
is deliberately not built yet.
