# Updates

Ablox is a Swift Playgrounds project, not an App Store app, so nothing on the
iPad can swap the running app for a new one. Everything short of that is done
for you:

| Step | Who | What happens |
|---|---|---|
| Notice | the app | On launch and every few hours after, reads `update.json` from this repository |
| Download | the app | On Wi-Fi (not in Low Data Mode), downloads the repository as a zip |
| Check | the app | Unzips `Ablox.swiftpm`, checking every file's CRC and refusing any path that would land outside it |
| Back up | the app | Writes a backup of avatar, coins, saved games and worlds — one to share, one kept inside the app |
| Install | **you** | Tap **Install**, then **Send to Swift Playgrounds**, open the new Ablox, press ▶︎ |
| Afterwards | the app | Says once what changed, and clears the download |

Ablox Studio does the same from its own repository.

## Where it looks

`update.json` at the top of the repository, fetched from the raw file server
on the repository's default branch (`HEAD`), so it follows whatever branch is
the default:

```json
{
  "app": "Ablox",
  "version": "1.1",
  "build": 2,
  "protocol": 6,
  "date": "2026-09-26",
  "package": "Ablox.swiftpm",
  "notes": { "en": ["…"], "ja": ["…"] }
}
```

A version is newer when `version` is higher, or the same with a higher
`build`. If `protocol` differs from the app's own network protocol, the update
is **required**: the banner cannot be dismissed, because friends on the new
version cannot play with this one (the lobby says the same for a room hosted
on a newer iPad). A version the player skipped is not offered again until a
newer one comes out.

Everything the app reads from the network is held to limits in
`AppUpdate.swift` (the manifest's size, app name and project folder) and
`ZipArchive.swift` (a zip bomb stops at the size the archive declared; `../`,
absolute paths and drive letters are refused; every file's CRC is checked).
The zip reader and the DEFLATE decoder are this project's own — Apple's
frameworks have no zip reader on iPad — and are tested on Linux against
archives made by Python's `zipfile` and `zlib`, including a flipped byte and a
path that tries to escape. On iPad, Apple's `Compression` decodes first and
the Swift decoder is the fallback.

## Your data across an update

The new project has the same bundle identifier, so Swift Playgrounds gives it
the same data: worlds, coins, avatar and saved games are simply there. In case
something goes wrong anyway, a backup is made before every install; share it
from the install screen, or in **Settings › Saved data** use **Bring back the
backup made before the last update**.

## Publishing a release

```
scripts/release.sh 1.2
```

sets the version in `Package.swift`, `Sources/AppRelease.swift` and
`update.json` together (next build number, today's date, the current
protocol). Write what changed in `update.json`'s `notes`, in English and
Japanese, then commit and push to the default branch. Every iPad with
automatic updates on finds it within a few hours.

`scripts/check-release.sh` — run by CI through
`scripts/check-playgrounds-project.sh` — fails the build if the three places
disagree, if `update.json` names a different protocol than the code speaks, or
if a language's notes are missing.

## What cannot be automatic

- **The install tap.** Only Swift Playgrounds can add a project to itself.
- **The first update to a version with the updater.** A copy from before 1.1
  has no updater; download it once by hand.
- **Games.** These never needed an app update: the catalogue and each game's
  scripts are fetched from GitHub when you play.
