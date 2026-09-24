# AbloxScript (`.absc`)

The scripting language for Ablox worlds. Scripts are `.absc` files, written in
Ablox Studio (or anywhere, and imported), carried inside the world, and run by
whichever iPad hosts the game. Anything the rule pickers cannot express is
meant to be expressible here: free-form screen GUI, camera and screen control,
character appearance and movement, NPCs, building and changing the map, the
world's sky and gravity, weapons, raycasts and general computation.

> 日本語ガイド: [`scripting.ja.md`](scripting.ja.md) — for people making
> games. This page is the reference and the reasoning.

## Why not Swift?

Running Swift typed on an iPad means compiling it on the iPad, and an app may
not generate or load native code at runtime; Swift Playgrounds can only
because it *is* the compiler. JavaScriptCore was the other candidate and was
turned down: it cannot run under `swift test` on Linux where the rest of the
game is tested, it has no public way to stop an infinite loop on the host
everyone's game depends on, and its errors are written for programmers, in
English. AbloxScript is a tree-walking interpreter in plain Swift
(`AbloxCore/Script*.swift`) with errors in English and Japanese.

## Files

- A world has up to 32 `ScriptFile`s (`WorldDocument.scripts`), each a name
  ending `.absc`, a source, and an on/off switch.
- They run as **one program**: every file's top level in order, sharing
  globals; each file may have its own `on join` etc., and all of them run, in
  file order. A second `on tick` *within one file* is still an error.
- Errors carry their file: `ui.absc, line 12: …`. Line numbers are packed
  into the AST's existing `Int` (`ScriptLocation`) rather than widening every
  node.
- Worlds saved before scripts have no `scripts` key; worlds from the first
  scripting build have a single `script` string, decoded as `main.absc`.
- Studio imports `.absc` from the Files app and exports through the share
  sheet. A game-list entry may list `"scripts": ["games/x/main.absc"]` in
  `index.json`; the client downloads them with the world, and a repository
  file replaces a same-named one inside the world.
- A world can pull its files from a GitHub folder — see below.

## Getting files from GitHub

Scripts are easier to write on a computer, and a computer keeps them in a
repository. A world's `scriptSource` (`ScriptSource.swift`) names a public
repository, a branch and a folder:

- **Studio → Script → Get .absc files from GitHub** sets it; **Get the latest
  now** brings in every `.absc` in the folder. A file with the same name
  (ignoring case) is replaced, keeping its on/off switch; a new name is added;
  a file only on the iPad is never deleted. One pull is one undo step and
  reaches co-editors as a single `scriptsReplaced` delta.
- **Get the latest every time the game starts** (`updatesOnPlay`) makes the
  hosting iPad pull again in `SessionCoordinator.startHosting` before the
  round begins. If GitHub cannot be reached, the saved files are used and the
  host's log says so. Clients never fetch; they get the host's world.
- The folder is listed with GitHub's contents API
  (`api.github.com/repos/{owner}/{repo}/contents/{folder}?ref={branch}`) and
  each file is read from `raw.githubusercontent.com`. The API allows sixty
  unauthenticated requests an hour per network; when it refuses, the files the
  world already has are refreshed straight from the raw server, which has no
  such limit. The raw server caches for a few minutes, so a push can take
  that long to show up.
- Everything GitHub answers is untrusted. Every URL is built on the iPad from
  checked parts — a folder cannot climb out with `..`, a branch cannot carry a
  query, and a file name from the listing must already be a clean `.absc`
  name. The `download_url` in the listing is ignored. Files over 1 MB, more
  than 32 files, and anything that is not UTF-8 are left out. Nothing is ever
  uploaded, and there is no token.

## Safety

Worlds come from strangers, and scripts run on the host. The limits are fuses
rather than rules — each is far beyond what a game needs:

| Limit | Value |
|---|---|
| Steps per handler call | 2,000,000 (`while true do end` stops with an error) |
| Call depth | 200 |
| List / map size | 100,000 |
| Text length | 1,000,000 |
| Source per file | 1,000,000 characters |
| Timers alive | 1,000 |
| Screen items per player | 300 |
| NPCs | 100 |
| Blocks in the world | 20,000 |
| Weapons | clamped: damage ≤ 1e6, rate 0.1–30/s, range ≤ 1 km |

No file, network or clock access: the only way out of a script is the game
API. A handler that errors is reported once, on the host's screen, and the
game carries on.

## How it runs

```
client iPad                          host iPad
───────────                          ─────────
fire / button / text / chat ──────▶  GameRuntime
                                       ├─ EventMachine (rules, scores)
                                       ├─ ScriptInterpreter (all .absc files)
                                       ├─ NPC simulation (WorldCollider, 10 Hz)
                                       └─ Hitscan / ArmedState (shots)
◀── eventEffect: EventAction.script(ScriptEffect)  — per player or everyone
◀── worldDelta: blocks and environment the script changed
◀── playerTransform: NPC movement, like any avatar
◀── roster: appearance, visibility, NPCs coming and going
ScriptedPlayerState → GUI, camera, weapon, health, movement
```

- **Host-authoritative.** Clients report inputs; the host decides. A shot is
  checked for fire rate (35% jitter allowance), ammo, and a muzzle within
  2.5 m of the shooter's eyes (scaled by their size), then cast against every
  character's capsule (scaled) and every solid block.
- **NPCs** are `PlayerState`s with `isNPC`, simulated on the host with the
  same `WorldCollider` players use — so they climb the same steps — and
  broadcast as ordinary transforms. `PlayerSnapshot.isNPC` keeps them off the
  scoreboard and out of the player limit.
- **Map edits** go through `WorldDelta`, the same deltas Studio's co-editing
  uses, so every iPad's world document — and therefore its collision — agrees
  with the host's. An animated `move` is animated on each iPad first and the
  end position sent when it finishes. `restart_round()` restores the map from
  a copy taken before the first round.
- **Protocol version 3**: `playerInput` (fire, reload, button, text),
  `ScriptEffect`, `scriptsReplaced`, NPC and hidden flags in the roster.

## The language

```lua
let score = 0
if score > 3 then … elif … else … end
while ready do … end        for i in 1 to 10 do … end        for p in players() do … end
func add(a, b) return a + b end        let f = func(x) return x * 2 end
[1, 2, 3]   {x: 1, y: 2}   list[1]   map.x   map["x"]
{x: 1, y: 2, z: 3} + {x: 0, y: 5, z: 0} * 2        -- positions are arithmetic
-- comment      # comment
```

Lists start at 1. `nil` and `false` are the only false values. Setting a map
entry to `nil` (`map.x = nil`) removes it, so `keys` and `len` no longer count
it. `+` joins text when either side is text. Identifiers may be in any script (`let 点数 = 0`).
The lexer accepts the iPad keyboard's curly quotes and full-width symbols.

## Reference

Studio shows the full reference beside the editor (`ScriptReference.swift`);
tests fail if any event, function, member or option is missing from it.

**Events**: `start tick(dt) join(p) leave(p) touch(p, block) tap(p, block)
fire(p) hit(victim, attacker, damage) hit_block(p, block) death(victim, killer)
respawn(p) button(p, id) input(p, id, text) chat(p, text)`.

**Globals**: `players npcs find_player block blocks create_block create_npc
distance raycast time after every cancel announce sound chat fade shake
end_round restart_round weapon ui_text ui_button ui_panel ui_image ui_bar
ui_input ui_set ui_remove ui_clear game world`.

**Characters** (players and NPCs): `name id is_npc health max_health alive
score team position x y z yaw look velocity weapon ammo speed jump gravity
frozen color head_color leg_color size hat visible`, and `give take reload
teleport damage heal kill respawn launch look_at`. Players only: `camera
camera_distance fov controls default_ui camera_look camera_reset message sound
chat fade shake ui_*`. NPCs only: `move_to follow stop jump_now shoot say
destroy`. Any other name stores a value on the character (`p.kills = 0`).

**Blocks**: `name id position x y z size rotation color material shape visible
solid tags opacity behavior`, and `move move_to rotate clone destroy`. Only a
block with a behavior (`trigger`, `hazard`, `checkpoint`, `bounce`,
`collectible`, …) is reported by the iPad when touched, so a script-made coin
needs `create_block({…, behavior: "trigger"})` for `on touch` to see it.

**World**: `gravity sky sky_top sky_bottom light sun sun_yaw ground
ground_color fall_height`. **Game**: `respawn_time friendly_fire time
round_over`.

**Screen items** take options `at x y pivot dx dy w h color bg size bold
radius opacity visible layer parent text value max`. `x` and `y` are fractions
of the parent (the screen or a panel); `at` names one of nine edge positions.
Calling a `ui_` function again with the same id updates that item and keeps
every option not given. Each returns a handle (`t.text = …`, `t.remove()`).

**Standard library**: `print type str num floor ceil round abs sqrt sin cos
tan asin acos atan atan2 pow log exp sign lerp pi min max clamp random vec
magnitude normalize dot cross len append remove insert contains index_of keys
join shuffle range slice reverse copy sum sort map filter upper lower trim
split replace starts_with ends_with fixed`. Angles are in degrees.

## Studio

The **Script** tab lists the world's `.absc` files (new, import, export,
rename, switch off, delete) and five complete sample games — 1v1 shooter, team
battle, zombie waves (NPCs), title screen and shop (GUI), and an obstacle
course that builds itself (map editing). The editor has **Check** (syntax
errors and misspelled events across all files) and **Test run** (plays every
file headlessly for five seconds with two idle players and reports the camera,
weapon, screen items, NPCs, created blocks, messages and printed lines). A
visit to the editor is one undo step.
