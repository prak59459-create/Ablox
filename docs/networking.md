# Networking

Ablox connects iPads directly. There is no server, no account, and nothing
leaves the local network.

## The shape of a session

One iPad **hosts**. It opens an `NWListener`, advertises `_ablox._tcp` over
Bonjour, and shows a six-character room code. Other iPads **browse** with
`NWBrowser`, see the world in their Play tab, and connect — with one tap if the
room is public, or by typing the code if it is private (see below).

```
  Host iPad                                  Guest iPad
  ─────────                                  ──────────
  NWListener (TLS-PSK)                       NWBrowser
  advertises _ablox._tcp   ── Bonjour ──▶    sees "Taro's World, 2/8"
         ▲                                        │
         │                                        │ NWConnection (TLS-PSK)
         └──────────── TLS 1.3 handshake ─────────┘
                       (PSK from room code)
                              │
                     handshake ▶ ◀ handshake
                     worldSnapshot ▶
                     roster ▶
                              │
                   ◀ playerTransform (15 Hz) ▶
                   ◀ eventTrigger / eventEffect ▶
```

## Security model, stated plainly

### What Ablox does

TLS 1.3 with a **pre-shared key**. The host displays a room code; both sides
stretch it with PBKDF2 into a 32-byte key, and the TLS handshake only
completes if both derived the same one.

```
salt = "ablox.psk.v2:" + sessionSalt        (16 random bytes, hex, in the TXT record)
PSK  = PBKDF2-HMAC-SHA256(password: roomCode, salt: salt, rounds: 120 000)
```

Room codes use a 30-character alphabet with no `I`, `L`, `O`, `U`, `0` or `1`,
so a code read across a table cannot be mistyped into a *different valid* code.
Six characters is about 29 bits.

29 bits is not much against a computer. Someone who records a handshake can
try every code offline; with a single HMAC (protocol 5 and earlier) that took
seconds. The stretching makes each guess cost 120 000 hashes — about a tenth
of a second on an iPad, paid once when the room opens and once per join — so
the same search takes years of one machine's time. The salt is new every
session and is not a secret: it only makes sure nobody can precompute a table
of every code's key once and reuse it on every room.

### Why not certificates

The obvious reading of the brief — "use `NWParameters.tls`" — means handing the
listener a `sec_identity_t`: a server certificate and private key. On iPad,
inside Swift Playgrounds, there is nowhere to get one. No provisioning profile
carries a certificate, there is no Keychain entry to import into, and
generating a self-signed identity at runtime needs `SecItemAdd` with a
keychain-access-group entitlement the sandbox does not grant.

The usual workaround is to have clients trust any certificate the host
presents. That is TLS with the authentication removed: anyone on the Wi-Fi can
present their own certificate and become a man in the middle. A pre-shared key
is strictly better here — it is what Apple's own peer-to-peer samples use.

### What this buys

- **Confidentiality and integrity.** Real TLS 1.3 AES-GCM. A sniffer on the
  café Wi-Fi sees ciphertext.
- **Mutual authentication.** Both ends prove they know the code. A stranger
  cannot join, and cannot impersonate the host to a joining player.
- **No infrastructure.** Two iPads and nothing else. It works over shared
  Wi-Fi, and over AWDL peer-to-peer when there is no Wi-Fi at all.

### What it does not buy

- **The code is the whole secret.** Anyone who learns it can join and can
  decrypt that session. Codes are per-session, but a shoulder surfer is in.
- **Stretching slows guessing, it does not stop it.** A determined attacker
  with a recording and a lot of computers could still get there. For a
  session that lasts an afternoon, that is far past the point of mattering.
- **No forward secrecy against a leaked code.** Someone who records traffic
  *and* later learns the code can decrypt the recording. Ephemeral
  Diffie-Hellman would fix this; it needs certificates, which is where we came
  in.
- **Peers are trusted once joined.** See "trust boundaries" below.
- **A public room gives the code away.** That is what public means; see
  "public and private rooms".

For *children building worlds together in the same room*, this is the right
trade. It would not be for anything carrying real personal data, and Ablox
carries none: a display name, some colours, and where a cube is.

## Trust boundaries

The host is authoritative for **rules and scores**. Clients report raw
observations ("I touched block X") and receive resolved effects ("you gained 10
points"). A client never tells the host what its own score is.

The host validates what it can:

| Check | Where |
|---|---|
| A peer may only move its own avatar | `AbloxHost.handle`, `playerTransform` |
| A peer may only report events as itself | `AbloxHost.handle`, `eventTrigger` |
| Host-authored packet kinds are ignored from clients | `AbloxHost.handle`, default case |
| World edits only accepted in a Studio session | `AbloxHost.handle`, `worldDelta` |
| Protocol version must match, with a readable error | `AbloxHost.handleHandshake` |
| Oversized messages drop the connection | `StreamReassembler`, `AbloxFramer` |
| Chat is length-clamped before it is stored | `ChatPayload.init` |
| Relayed chat carries the real sender and the name the host knows them by | `AbloxHost.handle`, `chat` |
| Nothing but a handshake is read, or sent, before the handshake | `AbloxHost.handle`, `relay` |
| Nobody may join as the host; a connection keeps its first identity | `AbloxHost.handleHandshake`, `PeerConnection` |
| Names, sizes and colours are made safe before anyone sees them | `AvatarProfile.sanitizedForNetwork` |
| NaN or absurd positions and speeds are dropped | `PlayerTransformPayload.isPlausible` |
| Each kind of packet has a rate limit; a flood cuts the connection | `PacketBudget` |
| Connections that never finish getting in time out after 10 s | `AbloxHost.accept` |
| An address that fails 15 times in a minute waits 2 minutes | `AttemptLimiter` |
| At most 6 connections may be getting in at once | `AbloxHost.accept` |
| Saved data is bounded both ways (keys, size, depth) | `SaveData` |

The rate limits are a token bucket per packet kind and per connection. Steady
play never comes near them — transforms are allowed at 40 a second against the
15 a client sends, chat at a sustained one and a half lines a second with room
for a burst of six. A packet over the limit is dropped before the game or
anyone else sees it; 300 drops in ten seconds means the connection is broken
or hostile, and it is closed. The tests for all of this are in
`NetworkSafetyTests`.

What the host does **not** do is verify that a reported position is physically
reachable. A modified client could teleport its own avatar. Fixing that means
server-side movement simulation with reconciliation, which is a large amount of
machinery to stop a child from cheating at a game they are hosting for their
own friends. It is a deliberate omission, not an oversight.

Avatar transforms are **peer-authoritative and host-relayed**: each client owns
its own avatar and the host forwards it. That keeps latency at one hop on a
local mesh.

## Wire format

Every message is a 33-byte binary header followed by a compact JSON body.

```
 offset  size  field
      0     1  kind          PacketKind
      1    16  senderID      raw UUID bytes
     17     4  sequence      big-endian, wraps
     21     8  timestampMs   big-endian
     29     4  payloadLength big-endian
```

JSON for the body because worlds should be readable and debuggable, and because
`Codable` makes evolution cheap. Binary for the header because
`playerTransform` goes out fifteen times a second per player, and base64-ing a
payload inside an outer JSON envelope would waste a third of every packet on
encoding overhead.

Framing is an `NWProtocolFramer` (`AbloxFramer`), so `receiveMessage` delivers
exactly one whole packet with its parsed header attached. The identical
length-prefix logic also lives in `StreamReassembler`, which exists so the
nasty cases can be unit-tested without a device: a header split across two
reads, several packets in one read, a truncated tail, a byte-at-a-time stream,
and a peer announcing a 4 GB payload.

### Packet kinds

| Kind | Direction | Reliability |
|---|---|---|
| `handshake` | both | must arrive |
| `worldSnapshot` | host → client | must arrive |
| `worldDelta` | both (Studio) | must arrive |
| `playerTransform` | client → host → all | supersedable |
| `roster` | host → client | must arrive |
| `eventTrigger` | client → host | must arrive |
| `eventEffect` | host → client | must arrive |
| `chat` | both | must arrive |
| `ping` / `pong` | both | supersedable |
| `leave` | both | best effort |
| `playerInput` | client → host | must arrive |

`playerInput` (protocol version 2; text boxes added in 3) carries a fire,
reload, screen-button or text-box press for the world's scripts. Like `eventTrigger` it is a claim, not a result:
a shot says where it came from and which way, and the host decides what it hit
— see [`scripting.md`](scripting.md).

Only `playerTransform` is dropped when it arrives out of order — the next one
supersedes it anyway. Everything else is delivered regardless of sequence,
because losing a world edit would desync the world permanently.

`isSequence(_:newerThan:)` compares in the wrapping half-space, so sequence 1
is correctly newer than 0xFFFFFFFF.

## Public and private rooms

The host picks one when the room opens, and can switch at any time from the
room code at the top of the screen. Players already inside stay either way.

- **Private** (the default, and the only choice for Studio co-editing): the
  code is only on the host's screen. The room is listed nearby with a lock, and
  joining asks for the code.
- **Public**: the TXT record also carries the code (`access=public`,
  `code=…`), so the lobby joins with one tap. The connection is still TLS with
  the same key — a sniffer still sees ciphertext — but anyone in Bonjour range
  can read the code, so anyone nearby can come in. That is the point.

A host that predates the setting sends neither key and is treated as private,
which is what it always was. `setPublic(_:)` re-advertises the TXT record, and
browsers pick the change up without reconnecting.

## Discovery details

The Bonjour TXT record carries world name, host name, player count, capacity,
mode, protocol version, the session's key salt and whether the room is public
(with its code, if so). That is what lets the lobby show a useful row —
"Taro's World · 3/8 players" — *before* anyone connects. A host running a build
that predates a key falls back to a default rather than failing to list.

`includePeerToPeer = true` on both the listener and browser parameters lets two
iPads connect over AWDL with no shared Wi-Fi at all.

## Failure messages

`-9836` tells a twelve-year-old nothing. `PeerConnection.describe(_:)` maps
`NWError` onto sentences: a TLS handshake failure becomes *"Could not connect —
check the room code is the same on both iPads."*, `ECONNREFUSED` becomes
*"That iPad is no longer hosting."*, and a denied local-network policy becomes
an instruction naming the exact Settings panel.

## Tuning

| Setting | Value | Why |
|---|---|---|
| Transform rate | 15 Hz | Smooth with client interpolation; leaves Wi-Fi headroom |
| Host tick | 10 Hz | Timers and proximity are "did this become true" checks, not simulation |
| Ping | every 2 s | Enough for a lobby latency reading |
| `noDelay` | on | Nagle would batch transforms into visible stutter |
| Keepalive | 2 s idle, 3 probes | Notice a sleeping iPad quickly |
| `connectionDropTime` | 5 s | Drop a peer that walked away |
| Max payload | 8 MB | A big world snapshot fits; anything larger is a bug or an attack |
| Key stretching | PBKDF2, 120 000 rounds | ~0.1 s per join; each offline guess costs the same |
| Handshake deadline | 10 s | A connection that never says hello does not hold a place |
| Pending connections | 6 at once | One device cannot tie up the host |
