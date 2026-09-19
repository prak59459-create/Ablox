# Tasks 3–8

Where each task in the brief stands, and the decisions behind the parts that
differ from the spec.

---

## Task 3 — Avatar movement & real-time sync

**Built.** Floating virtual joystick, third-person follow camera, and
interpolated remote avatars.

| Spec | Where |
|---|---|
| Virtual joystick with bounded travel | `UI/Game/VirtualJoystick.swift` |
| Auto-turn toward movement | `CharacterSolver.step` |
| Third-person follow camera | `GameViewport.updateCamera` |
| Lerp remote positions, not overwrite | `PlayerSnapshot.interpolated(toward:t:)` |
| 20 Hz transform broadcast | `AbloxProtocol.transformHz` |

Two deliberate differences:

**20 Hz is a ceiling, not a rate.** The spec asks for a fixed 1/20 s timer.
Sending on a timer costs `players × 20` packets a second whether or not
anything moved, which on a shared Wi-Fi is most of the traffic wasted on people
standing still. `TransformPublisher` (Task 8) sends only when peers could not
have predicted the avatar, and never faster than 20 Hz. An idle player costs
one keepalive per second instead of twenty packets.

**Yaw interpolation takes the shortest arc.** Lerping raw degrees makes an
avatar crossing 180° spin the long way round. `angularDelta(from:to:)` handles
the wrap; `testInterpolationTakesShortestYawArc` holds it.

---

## Task 4 — Gimmick / event script system

**Built.** Three no-code gimmicks, on top of the behaviours that already
existed.

| Spec gimmick | Implementation |
|---|---|
| ハイジャンプ (Bounce) | `BlockBehavior.bounce` → `EventAction.bouncePlayer(speed:)` |
| 消える足場 (Disappear) | `BlockBehavior.disappear`, scheduled hide then restore |
| ワープ (Teleport) | `BlockBehavior.teleport` → target block's top face |
| キルゾーン (KillZone) | `BlockBehavior.hazard` — already present |
| 1.5 s cooldown | `GimmickSettings.cooldown`, per block |

Tuning lives in `GimmickSettings` on each block, edited in the Studio
Inspector, which shows only the fields the chosen gimmick actually uses.

Decisions worth knowing:

- **The cooldown is per block, not per player.** Two children on one trampoline
  should not double-fire it. `testBounceCooldownIsSharedBetweenPlayers`.
- **Bounce replaces upward velocity rather than adding to it.** Adding would
  compound if a player bounced mid-rise and launch them out of the world.
- **A disappearing platform mutates the world document as well as
  broadcasting.** A player joining while it is gone sees it gone.
- **A teleporter with no target, a deleted target, or itself as target is
  inert.** Dropping the player at the origin — or into a loop — is worse than
  doing nothing. Three tests cover exactly these.

### The collision bug this uncovered

Writing the gimmick tests surfaced a real bug in code that had been passing its
own tests for weeks. A falling player comes to rest wherever the last
integration step left them, which can be up to `groundProbeDepth` (5 cm) above
the surface — it is the ground *probe*, not a collision, that stops them. The
touch test used the exact body box, so **a player standing on a hazard,
checkpoint or bounce pad might never register touching it.** Triggers are now
tested against a box grown by the probe depth. `WorldCollider.resolve`.

---

## Task 5 — Studio ↔ Play switching & world state

**Already built**, in the previous phase.

Mode switching is `StudioSession.toggleMode()`, which saves before entering
play so a crash while testing cannot lose work. Physics is off in edit mode so
blocks do not topple while being arranged. World serialisation is
`WorldDocument` (JSON, one file per world), and host→client sync is a
`worldSnapshot` on join plus `worldDelta` per edit — deltas rather than
resending the whole document on every change, which is what makes live
co-editing usable.

---

## Task 6 — Avatar customisation & economy

**Built.** Avatar customisation already existed; coins, inventory and the shop
are new.

| Piece | Where |
|---|---|
| Coins, inventory, purchase rules | `AbloxCore/Economy.swift` |
| Catalogue | `ShopCatalogue` |
| Score → coins | `CoinRate` |
| Shop screen | `UI/MainMenu/ShopView.swift` |
| Persistence | `AppSettings.wallet` |

Decisions:

- **Everything in the shop is cosmetic.** In a game four children play in one
  room, the one with the most coins must not also be the fastest.
  `testNothingInTheShopAffectsGameplay` asserts it, so the rule fails a build
  rather than eroding.
- **The first four colours of each slot are free.** A player with no coins can
  still make an avatar that looks like theirs.
- **Coins are earned from the host's authoritative score**, never from a
  client's claim. A client that reported its own coins would make the first
  child who reads the protocol very rich.
- **A negative round earns nothing rather than costing banked coins.** Losing
  points to a hazard should not empty a wallet someone saved into.
- **Buying something wears it immediately.** Having to then go and find it in
  the avatar editor is a step nobody wants.

---

## Task 7 — Chat & social safety

**Built.** Chat already existed; filtering, muting and the player list are new.

| Piece | Where |
|---|---|
| Word filter | `ChatModerator` |
| Mute list | `MuteList` |
| Player list, ping, roles | `UI/Game/PlayerListView.swift` |

**The filter is a speed bump, not a safety system**, and it says so in its own
documentation. A substring filter is trivially defeated by spacing or
substitution, and no word list is complete or culturally neutral. It exists
because an entirely unfiltered channel between children is worse, and because
`***` is a visible signal that someone is paying attention.

The real protections are structural and matter more: sessions are local-only
and never touch a server, joining needs a room code shared in person, and
everyone in a session is in the same room.

Details that took thought:

- **Ordinary words containing a blocked substring survive.** A filter that
  mangles "classic" or "assignment" teaches children the filter is broken.
  Matching is whole-word; `testOrdinaryWordsContainingABlockedSubstringSurvive`
  covers the classic cases.
- **Masking preserves length** so the shape of the message still reads.
- **Filtering happens on receipt**, so a peer running a modified client cannot
  opt its own messages out of your filter.
- **Muting is applied when the log is read**, not when a message arrives, so
  unmuting brings the backlog back instead of leaving a hole.
- **Muting is local, silent and per-device.** The muted player is not told and
  nobody else's view changes, which is what makes it safe for a child to use on
  someone sitting next to them.
- **You cannot mute yourself.** Silently dropping your own chat reads as the
  app being broken.

---

## Task 8 — Performance & QA

**Partly built.** Dead reckoning is done and measured; the rendering work is
partly pre-existing and partly not done.

### Done — network

`TransformPublisher` is the send half of dead reckoning. A peer that hears
nothing assumes the avatar continued as it was, so a packet is only sent when
reality has diverged past a threshold:

| Trigger | Default |
|---|---|
| Position diverges from prediction | 5 cm |
| Facing change | 2° |
| Velocity change | 0.5 m/s |
| Keepalive | 1 s |
| Rate ceiling | 20 Hz |

Comparing against the *prediction* rather than the last sent position is the
part that matters: comparing against the last sent position would send
constantly during steady running, which is exactly the case this is for.
Velocity and grounded-state changes send immediately, so a jump is never
delayed by the position threshold.

`suppressionRate` is exposed so the effect is measurable rather than assumed —
an idle player suppresses over 80% of ticks in test.

### Done — rendering, from earlier phases

- One cached mesh per `BlockShape`, generated at unit size and scaled per
  entity, so a world of 200 boxes allocates one box mesh.
- `WorldScene` reconciles against the document rather than rebuilding, skipping
  untouched blocks — which is what makes a 60 Hz Studio drag affordable.

### Not done, and honest about it

- **Mesh instancing proper.** The mesh cache gets most of the benefit; true
  instanced draw calls need `LowLevelMesh` or manual batching, and neither is
  worth doing before a device profile says it is the bottleneck.
- **Frustum culling.** RealityKit already culls off-screen entities. Adding our
  own on top would mean measuring first.
- **Entity pooling.** `WorldScene` reuses entities across syncs, which covers
  the editing case. A pool for rapid spawn/despawn is not needed yet.
- ~~**Background/foreground TLS reconnection.**~~ **Now done** — see below.

### Done — session resilience

Backgrounding an iPad kills the TCP connection; keepalive drops it within ~5 s.
Previously that sent the player back to the lobby to re-enter a room code they
had already typed. Now:

- `DisconnectReason` classifies *why* a session ended, replacing a bare string.
  The distinction that matters is retryable versus not — a Wi-Fi blip deserves
  a quiet reconnect, a wrong room code deserves a message. Retrying an
  authentication failure five times with backoff only delays telling the player
  the one thing they can fix.
- `ReconnectPolicy` supplies exponential backoff, capped, with jitter. The
  jitter earns its place: when a host's Wi-Fi blips, *every* client drops at
  the same instant, and without it they would all retry in lockstep against a
  host that is itself still recovering.
- `ReconnectCoordinator` steps the sequence — drop, wait, try, wait longer,
  give up — with an injected clock, so it is tested rather than discovered in
  a classroom.
- Returning to the foreground brings the next attempt forward, because the
  iPad has just regained its network and waiting out a backoff scheduled while
  it was asleep is delay the player can see.
- The world and roster stay on screen while reconnecting, behind a light
  banner rather than a modal. A blip is usually over in under a second.

Two details worth recording, both found by tests:

- **Giving up happens as soon as it is knowable.** An attempt is validated
  against when it would *run*, not against now — scheduling one the deadline
  will reject on arrival means the player watches "Reconnecting…" for a full
  backoff to learn something already known.
- **A failed attempt is not a fresh drop.** It arrives back through the same
  disconnect path, and treating it as new would reset the attempt counter to
  one: the backoff would never escalate and the give-up would never fire. An
  infinite retry loop that looks like it is working.

### Done — audio and haptics

`EventAction.playSound(name:)` had been reaching clients and going nowhere
since the first phase. `SoundCue` is now the closed set of names the client can
play, `FeedbackPlayer` plays them, and Studio's rule editor offers the list
instead of a free-text field that silently does nothing when misspelled.

Sounds are iOS system sounds via `AudioServicesPlaySystemSoundID` — no bundled
assets, so the Playground stays readable Swift. They are not bespoke game
sounds; synthesising tones with `AVAudioEngine` would sound better and still
need no assets, and is the obvious next step if feel matters more than
footprint.

Haptics carry equal weight deliberately: these iPads are often muted, so the
haptic is frequently the only feedback that arrives. The throttle that stops a
row of coins becoming a buzz rather than a series of taps lives in
`SoundCue.minimumInterval` and is tested.

### Test checklist — needs real devices

None of this can be verified in CI; it needs iPads in a room.

| # | Test | Pass condition |
|---|---|---|
| 1 | 4 iPads joined over TLS, 10 min | No disconnections; ping stays < 150 ms |
| 2 | 500+ blocks in one world | Sustained 60 fps in Play mode |
| 3 | 500+ blocks, Studio drag | No dropped frames while dragging |
| 4 | App backgrounded and returned | Session recovers, or fails with a readable message |
| 5 | Host leaves mid-session | Clients show "the host closed the world", not a hang |
| 6 | Wrong room code | "check the room code is the same on both iPads" |
| 7 | Local Network permission denied | Settings path named in the lobby |
| 8 | 4 players on one bounce pad | Fires once per cooldown, nobody launched out of the world |
| 9 | Disappearing platform, 2 players | Both see it vanish and return together |
| 10 | Coins across a relaunch | Wallet and purchases survive |
| 11 | Mute, then relaunch | Mute list survives; muted player still hidden |
| 12 | Idle 4-player session | `suppressionRate` > 0.8 |
| 13 | Background an iPad 10 s, return | Rejoins automatically; world still there |
| 14 | Host Wi-Fi off 3 s, back on | All clients recover, staggered not in lockstep |
| 15 | Background past the give-up window | Clear message, back to lobby, no hang |
| 16 | Muted iPad, collect a coin | Haptic still fires |
| 17 | Collect a row of coins fast | Taps stay distinct, not one buzz |

### Completion criteria

1. Every checklist row above passes on real hardware.
2. `swift test` green in both repositories (257 tests today).
3. `scripts/sync-core.sh --check` green.
4. Both `.swiftpm` bundles open and run in Swift Playgrounds on iPad.

---

## Test counts

| Repository | Tests |
|---|---|
| Ablox | 250 |
| Ablox Studio | 289 (250 mirrored core + 39 editor) |

Everything above that is testable off-device is tested off-device. The
RealityKit, SwiftUI and Network layers are not — they need the iOS SDK, and
they are where the remaining risk lives.
