# Roadmap

Against the four phases in the original brief.

## Phase 1 — Main UI hub & network foundation ✅

- [x] Sidebar hub with glassmorphism and an animated aurora background
      (which respects Reduce Motion)
- [x] Play lobby listing nearby hosts live over Bonjour, with world name and
      player count read from the TXT record before connecting
- [x] World library: create, rename, duplicate, delete, play, host
- [x] Avatar editor with a live rotating 3D preview
- [x] Settings: controls, movement feel, and a plain-language account of what
      Ablox does on your network
- [x] TLS 1.3 over `Network.framework`, keyed by a room code
- [x] Bonjour advertise and browse, including AWDL peer-to-peer

## Phase 2 — 3D engine foundation & data structures ✅

- [x] `BlockData`, `WorldDocument`, `NetworkPacket` and friends, all `Codable`
- [x] Binary packet header + JSON body, with an `NWProtocolFramer`
- [x] `WorldScene`: reconciling RealityKit renderer
- [x] `BlockEntityFactory` with a per-shape mesh cache
- [x] `AvatarEntity` built from primitives, with a distance-phased walk cycle
- [x] Deterministic character collision (`WorldCollider`)

## Phase 3 — Ablox Studio ✅

Lives in the [`Ablox-studio`](https://github.com/prak59459-create/Ablox-studio)
repository.

- [x] Explorer tree with drag-to-reparent
- [x] Inspector for transform, colour, material, behaviour, tags
- [x] Move / rotate / scale tools with grid snapping
- [x] Event rule editor
- [x] Undo/redo
- [x] Live co-editing over the same TLS mesh

## Phase 4 — Gameplay & interaction ✅

- [x] Floating virtual joystick, camera pad, jump
- [x] Left-handed layout, camera sensitivity, Y inversion
- [x] Built-in behaviours: spawn, checkpoint, hazard, collectible, goal
- [x] Authored rules: touch, tag-touch, tap, proximity, timer, score
- [x] Scoreboard, announcements, chat
- [x] Host-authoritative scoring
- [x] Edit ↔ play switching (in Studio)

## Phase 5 — Scripting ✅

- [x] AbloxScript (`.absc` files, many per world): a sandboxed interpreter with
      generous fuses, and errors in English and Japanese — see [`scripting.md`](scripting.md)
- [x] Free-form screen GUI, camera modes, fades and shakes, hiding the controls
- [x] Characters: appearance, movement, launching; NPCs that walk, follow and shoot
- [x] Building the map from a script: create, change, move and destroy blocks; sky and gravity
- [x] Game API: players, blocks, timers, teams, screen GUI (text, bars, buttons)
- [x] First-person camera, weapons and host-authoritative hitscan
- [x] Studio script editor with Check, a headless Test run, samples and a reference
- [x] Fixed: the host never showed joined players moving; a joining player
      ignored the spawn point the host gave them (`RosterState`)
- [x] Room codes can be typed on an on-screen pad when the keyboard does not
      appear (`CodePad`)

---

## Deliberately not built

Each of these is an omission with a reason, not an oversight.

**Server-side movement validation.** The host trusts a client's reported
position. Catching a modified client means simulating every player on the host
and reconciling, which is a large amount of machinery aimed at stopping a child
cheating in a game they are hosting for their own friends. Documented in
`networking.md` rather than half-built.

**Forward secrecy.** Would need ephemeral Diffie-Hellman, which needs
certificates, which Swift Playgrounds cannot provide. The limitation is
written down rather than papered over.

**Host migration.** When the host leaves, the session ends. Electing a new host
means agreeing on who has the freshest world state — a consensus problem, for a
case that is rare in a room where everyone can see each other.

**Persistent player accounts.** No accounts, by design. Identity is a per-device
UUID in `UserDefaults`.

**Audio.** `EventAction.playSound` carries a name and reaches the client, but
nothing plays it yet. Wiring it to `AVAudioPlayer` is small; choosing sounds
that ship inside a Playground without binary assets is the actual question.

**Texture and model import.** Every visual is a RealityKit primitive with a
colour. A Playground should be readable Swift, not a bundle of binaries.

## Known rough edges

- `WorldScene.animateTint` steps a colour ramp on `DispatchQueue.main`
  timers at 20 Hz. It works and is bounded, but a `SceneEvents.Update`
  subscription driving a per-frame interpolation would be cleaner.
- `EventMachine` resolves `scoreReached` cascades exactly one level deep. Enough
  for every rule the editor can author today; a rule that awards points *and*
  triggers another rule that awards points would stop after the first.
- The lobby shows a peer's player count from its Bonjour TXT record, which is
  refreshed on join and leave. A peer that crashes without sending `leave`
  leaves a stale count until keepalive notices.

## If work continued

1. Audio — the cheapest large improvement to how the game feels.
2. Other players' weapons drawn in their hands — today only tracers show
   that someone else is shooting.
3. A world-sharing flow: worlds are single JSON files already, so AirDrop is
   mostly a share sheet away.
4. Replay recording — the wire format is already a complete event log.
