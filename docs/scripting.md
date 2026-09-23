# AbloxScript

A small scripting language for Ablox worlds, written in Ablox Studio and run
by whichever iPad hosts the game. It covers what the rule pickers cannot:
first-person shooters, teams, weapons, timers, and a screen GUI.

> 日本語版: [`scripting.ja.md`](scripting.ja.md) — the guide for people
> making games. This page is the reference and the reasoning.

## Why not Swift?

The obvious request, and the one iOS rules out. Running Swift typed on an iPad
means compiling it on the iPad, and an App Store app may not generate or load
native code at runtime; Swift Playgrounds can do it only because it *is* the
compiler. JavaScriptCore was the other candidate. It was turned down because:

- it cannot run under `swift test` on Linux, where every other rule of the
  game is tested;
- it has no public way to stop an infinite loop, and scripts run on the host —
  the one iPad everyone else's game depends on;
- its error messages are written for programmers, in English.

So AbloxScript is a tree-walking interpreter in plain Swift
(`AbloxCore/Script*.swift`): about the size of a Lua subset, with errors in
English and Japanese that say what to do.

## Safety

Worlds come from strangers through the game list. Every limit below is a test
in `ScriptLanguageTests` or `GameRuntimeTests`.

| Limit | Value | Why |
|---|---|---|
| Steps per handler call | 50,000 | An endless loop stops within a frame or two, with an error on its line |
| Call depth | 100 | Runaway recursion is an error, not a crash |
| List / map size | 10,000 | A script cannot exhaust the host's memory |
| Text length | 100,000 | Same |
| Timers | 200 | `every` inside `on tick` would otherwise grow forever |
| Screen items per player | 24 | Readable on an iPad, and bounded |
| Weapon numbers | clamped | A fire rate of a million would be a million raycasts |

There is no file, network or clock access: the only way out of a script is the
game API. A handler that errors is reported once and the game carries on.

## How it runs

```
client iPad                         host iPad
───────────                         ─────────
fire button ── playerInput ──────▶  GameRuntime
                                      ├─ EventMachine (rules, scores)
                                      ├─ ScriptInterpreter (the world's script)
                                      └─ Hitscan / ArmedState (shots)
◀────────────── eventEffect ──────  EventAction.script(ScriptEffect)
ScriptedPlayerState → HUD, camera, weapon
```

- **Host-authoritative.** A client says where it fired from and which way; the
  host checks the fire rate (with 35% jitter allowance), the ammo, that the
  muzzle is within 2.5 m of where it believes the shooter's eyes are, and then
  decides what the shot met. Blocks stop shots.
- **One effect path.** Everything a script does to a player — HUD, camera,
  weapon, health, ammo, tracers — rides `EventAction.script`, targeted or
  broadcast by the same `groupedIntoPayloads()` as rule effects.
- **Late joiners** get the shared screen items replayed, then `on join`.
- **Protocol version 2** added `PacketKind.playerInput` (12) and the script
  effects. Older iPads are refused at the handshake with a readable message.

`GameRuntime` owns both the rule machine and the script so they share one
world and one set of players: a script setting `p.score` trips a
`scoreReached` rule, and a rule teleport moves the player where the next shot
will look.

## The language

```lua
let score = 0
if score > 3 then … elif … else … end
while ready do … end
for i in 1 to 10 do … end        -- counts down too: for i in 10 to 1
for p in players() do … end
func add(a, b) return a + b end
let f = func(x) return x * 2 end
[1, 2, 3]   {x: 1, y: 2}   list[1]   map.x   map["x"]
-- comment      # comment
```

Lists start at 1. `nil` and `false` are the only false values. `+` joins text
when either side is text. `a or "default"` returns an operand. Identifiers may
be in any script, so `let 点数 = 0` works. The lexer accepts the curly quotes
the iPad keyboard inserts and full-width symbols from a Japanese keyboard.

## Reference

Studio shows this beside the editor (`ScriptReference.swift`), and a test
fails if an event or function is missing from it.

### Events

`start()`, `tick(dt)`, `join(p)`, `leave(p)`, `touch(p, block)`,
`tap(p, block)`, `fire(p)`, `hit(victim, attacker, damage)` — return a number
to change the damage, `hit_block(p, block)`, `death(victim, killer)`,
`respawn(p)`, `button(p, id)`.

### Globals

`players()`, `block(name)`, `blocks(tag)`, `distance(a, b)`, `time()`,
`after(s, f)`, `every(s, f)`, `cancel(id)`, `announce(text, s)`,
`sound(name)`, `end_round(text)`, `weapon(name, {…})`,
`hud_text(id, text, {…})`, `hud_bar(id, value, max, {…})`,
`hud_button(id, label, {…})`, `hud_remove(id)`, `hud_clear()`,
`game.respawn_time`, `game.friendly_fire`, `game.time`, `game.round_over`.

Standard library: `print type str num floor ceil round abs sqrt sin cos min
max clamp random len append remove contains keys join shuffle upper lower
trim split`.

### Players

Read: `name id health max_health alive score team position yaw weapon ammo
camera speed jump`. Set: `health max_health score team camera speed jump
ammo`, plus any name of your own (`p.kills = 0`). Call: `give take reload
teleport damage heal kill respawn message sound hud_text hud_bar hud_button
hud_remove hud_clear`.

### Blocks

Read: `name id position visible solid color tags`. Set: `visible solid
color`. Call: `move(x, y, z, seconds)`.

### Weapons

Presets `blaster`, `rifle`, `shotgun`, `pistol`. `weapon("sniper",
{model: "rifle", damage: 90})` starts from the model and changes what it
names: `damage rate range ammo reload spread model`.

### Screen items

Options: `at` (`top_left top top_right left center right bottom_left bottom
bottom_right`), `color` (a name in English or Japanese, or `#RRGGBB`),
`size` (`small medium large`). Anchors rather than pixels, because a script
written on one iPad is played on every size of another.

## Studio

The **Script** tab opens the editor: **Check** parses and flags handlers for
events that never happen (`on joni` → "did you mean `on join`?"); **Test run**
plays the script headlessly for five seconds with two idle players and reports
the camera, weapon, screen items, messages and printed lines. The samples in
the **Examples** menu are played by `ScriptSampleTests` on every test run.
