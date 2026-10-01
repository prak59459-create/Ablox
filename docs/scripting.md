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
respawn(p) button(p, id) input(p, id, text) chat(p, text) loaded(p) emote(p, name)
use(p, item) choice(p, answer, number) buy(p, item, price) countdown(label, p)`.

**Globals**: `players npcs find_player block blocks create_block create_npc
distance raycast time after every cancel announce sound chat fade shake
end_round restart_round weapon ui_text ui_button ui_panel ui_image ui_bar
ui_input ui_set ui_remove ui_clear particles music speak countdown leaderboard
show_leaderboard leaderboard_top game world`.

**Characters** (players and NPCs): `name id is_npc health max_health alive
score team position x y z yaw look velocity weapon ammo speed jump gravity
frozen color head_color leg_color size hat ride ride_color visible`, and `give take reload
teleport damage heal kill respawn launch look_at`. Players only: `camera
camera_distance fov controls default_ui camera_look camera_reset message sound
chat fade shake ui_* saved save`. NPCs only: `move_to follow stop jump_now shoot say
destroy`. Any other name stores a value on the character (`p.kills = 0`).
`n.say("Hello!")` shows a speech bubble over the NPC's head for a few seconds,
the same white bubble players get when they chat, and puts the line in the
chat under the NPC's name.
`p.ride = "car"` draws the character riding something — `car`, `sports`,
`truck`, `kart`, `bike`, `scooter`, `jetpack` or `hoverboard` (`none` to get
off) — in `p.ride_color`. It is only the look: set `p.speed` as well.

**Blocks**: `name id position x y z size rotation color material shape visible
solid tags opacity behavior label label_height label_size label_range animation
animation_speed parent`, and `move move_to rotate clone destroy`. Only a
block with a behavior (`trigger`, `hazard`, `checkpoint`, `bounce`,
`collectible`, …) is reported by the iPad when touched, so a script-made coin
needs `create_block({…, behavior: "trigger"})` for `on touch` to see it.
A trigger is also something you walk *through*, never stand on: a floor tile
that has to hold people up and still know who is on it stays an ordinary
block, and `on tick` works out the tile under each player from `p.x` and `p.z`.

**Words over a block**: `b.label = "Shop"` floats words over the block,
always facing the camera (`\n` starts a new line). A list gives up to four
lines, each text or `{text, color}`:
`b.label = [{text: "Rare", color: "#3B82F6"}, "Pizza Cat", {text: "$15/s", color: "#22C55E"}]`.
`b.label_height` is how far above the block (studs), `b.label_size` how big
(1 is usual) and `b.label_range` how far away it still shows; `b.label = nil`
takes the words away. `create_block({…, label: "…"})` works too. The nearest
48 are drawn; an iPad that has not updated shows the block without them (2.2).

**Blocks that hang from others and move by themselves**:
`create_block({parent: body, position: {x: 0, y: 1, z: 0}, …})` hangs a block
from another: `position` is measured from it, and the block moves, turns and
goes away with it (one `move_to` on the body carries a whole model). `b.parent`
reads it. `b.animation = "dance"` makes a block move by itself on every iPad,
with nothing sent over the network — `spin`, `sway`, `dance`, `bounce`, `pulse`
or `wobble`, at `b.animation_speed` (1 is usual); it turns and stretches the
block (and what hangs from it) without moving it, so `move_to` still carries it
along. `nil` stops it. An iPad that has not updated shows it still (2.2).

**World**: `gravity sky sky_top sky_bottom light sun sun_yaw ground
ground_color fall_height weather time day_length sky_style effect shadows
music`. Blocks also have `particles` (a kind, or nil) and `image` (the name of
one of the world's pictures). **Game**: `respawn_time friendly_fire time
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

**More helpers** (the searches and small tools most games wrote for
themselves):

- Finding: `nearest_player(from, max)` (not counting `from` itself),
  `players_near(from, radius)` (nearest first), `random_player()`,
  `alive_players()`, `team_players("red")`, `ranking()` (highest score first),
  `nearest_block(from, tag)` and `blocks_near(from, radius, tag)`. `from` is a
  player, NPC, block or `{x, y, z}`; knocked-out players are left out.
- Numbers: `int average median gcd smoothstep inverse_lerp remap`,
  `approach(x, target, step)` (never passes the target; numbers or positions),
  `wrap(370, 0, 360)` is 10, `snap(7.3, 2)` is 8 (positions snap too),
  `angle_diff(350, 10)` is 20.
- Chance: `chance(25)` is true 25 times in 100; `random_float(1, 2)`;
  `pick_weighted({common: 70, rare: 25, epic: 5})` gives a name, and a list of
  weights gives a position. All use the world's seeded randomness.
- Lists: `unique flatten zip first last chunk repeat`, and with a function
  `find any all reduce count min_by max_by sort_by group_by`. `count` also
  counts a value, or a piece of text in some text.
- Maps: `values entries merge`, and `get(p.saved, "coins", 0)` — a value or a
  default, even when the map is still nil.
- Text: `pad_left(7, 3, "0")` is "007", `pad_right capitalize words lines`,
  `format("{} has {} coins", p.name, 5)`, `comma(1234567)` is "1,234,567",
  `short_number(1500)` is "1.5K" (K, M, B, T), `time_text(65)` is "1:05".
- Directions: `forward(yaw)` is the way a yaw faces, `yaw_to(a, b)` the yaw
  that faces from a to b (so `n.yaw = yaw_to(n, p)`), `direction(a, b)`,
  `rotate_y(v, degrees)` (positive turns right, as yaw does) and
  `angle_between(a, b)`.
- Colours: `rgb(255, 128, 0)` and `hsv(120, 1, 1)` make "#RRGGBB" text,
  `mix_color("red", "blue", 0.5)` is part way between, `random_color()` is a
  bright one. `hsv(time() * 60 % 360, 1, 1)` goes round the rainbow.

A script may still use any of these names for its own variables and
functions (`let count = 0`, `func find(…)`); its own wins, as it did before
they existed.

Positions, counts and numbers of digits are safe with any number: `nan` or
`10^300` as a list position reads nil, and as a size is a "too big" error.
Before 1.5 a few of these stopped the whole app.

## Ready-made parts

Things most games build by hand, as one line each. The screens are drawn by
the app and their buttons come back to the host as reserved ids (`__use:…`,
`__buy:…`), handled before `on button` sees them.

```lua
on join(p)
  p.coins = 100
  p.give_item("Key", 1, "🔑")              -- a bar at the bottom; tapping runs on use
  p.waypoint(block("Door"), "The door")    -- an arrow to follow, with the distance
  countdown(90, "Time left")               -- a big timer; at 0 runs on countdown
end

on use(p, item)
  if item == "Key" and distance(p, block("Door")) < 4 then
    p.take_item("Key")
    p.dialog("Guard", "You found the way out!", ["Shop", "Bye"])
  end
end

on choice(p, answer, n)
  if answer == "Shop" then
    p.shop("Armoury", [{name: "Sword", price: 50, icon: "⚔️"}, {name: "Shield", price: 80}],
           {currency: "coins"})        -- spends p.coins; "score" spends the score
  end
end

on buy(p, item, price)                  -- already paid
  p.give_item(item)
  particles("confetti", p, {amount: 60})
  sound("win", {volume: 0.8, pitch: 1.2})
end

on countdown(label, p)
  for q in players() do leaderboard("coins", q, q.coins) end
  show_leaderboard("coins")
end
```

- **Leaderboards** keep each player's best (`{lower: true}` for times) on the
  host's iPad between games; `leaderboard` returns the player's place.
- **Music** is made on the iPad: `calm adventure spooky race boss shop party
  space`. `music("off")` is quiet; `music(nil)` goes back to the world's own
  (`world.music`). Players set its volume in Settings.
- **Sounds** can be louder, softer, higher or lower: `sound("coin", {volume,
  pitch})`. There are 30 of them (`coin jump powerup explosion splash door click
  whoosh win lose magic pop bell laser alarm drum` and the older ones).
- **Particles**: `fire smoke sparkles confetti rain snow bubbles hearts stars
  leaves magic dust`, as a puff or `{seconds: 5}` of them, anywhere, or
  `b.particles = "fire"` for a block that keeps burning.
- **speak(text)** reads a line aloud for players who switched on *Read
  characters' lines aloud*; the same setting reads dialog boxes.
- **The world**: `world.weather` (`clear rain snow fog storm`), `world.time`
  (the hour) and `world.day_length` (minutes a day takes; 0 stands still),
  `world.sky_style` (`gradient clouds sunset stars aurora space`),
  `world.effect` (`none bloom vivid warm cool noir retro dream`) and
  `world.shadows`. The day is counted on every iPad's own clock from when it
  started, so everyone sees the same sky without it being sent.

Blocks can do more without a script too: **ladders** (climb), **doors** (open
when walked into), **moving platforms** (carry whoever stands on them),
**vehicles** (touch to ride faster; *Get out* to leave) and **pushable**
blocks, and the natural materials `wood stone brick grass sand ice water`
(swim in water). A world using any of these is saved as format 2, which an
iPad that has not updated will not open; everything else stays format 1.

## Saving progress

`p.save("coins", 120)` keeps a value on that player's own iPad, and
`p.saved` (a map) reads everything they have saved in this world — next
session, and in anyone's room, because a catalogue game keeps its world id
whoever hosts it. `p.save("coins")` forgets a key.

```lua
on loaded(p)                 -- their saved data has arrived
  p.coins = p.saved.coins or 0
end

on button(p, id)
  if id == "buy" then
    p.coins = p.coins - 10
    p.save("coins", p.coins)  -- cheap: sent back at most once a second
  end
end
```

- The data arrives a moment after `on join`, so read it in `on loaded(p)`.
  Until then `p.saved` is nil and `p.save` returns false without saving, so
  a new session can never overwrite older progress with its defaults.
- Numbers, text, true/false and lists and maps of those can be saved — not
  players, blocks or functions. Up to 200 names and 64 KB per world.
- Nothing is saved in Studio's play test, and NPCs have nothing to save.
- It is the player's own data, sent by their iPad: fine for progress and
  unlocks, but a determined player could edit it, so it is not a place for
  anything other players rely on.

The catalogue kit (`lib/kit.absc` in the games repository) does this for
you: coins, quests and badges are kept automatically, and a game lists its
own progress with `kit_keep(["fans", "best"])`.

## Studio

The **Script** tab lists the world's `.absc` files (new, import, export,
rename, switch off, delete) and five complete sample games — 1v1 shooter, team
battle, zombie waves (NPCs), title screen and shop (GUI), and an obstacle
course that builds itself (map editing). The editor has **Check** (syntax
errors and misspelled events across all files) and **Test run** (plays every
file headlessly for five seconds with two idle players and reports the camera,
weapon, screen items, NPCs, created blocks, messages and printed lines). A
visit to the editor is one undo step.
