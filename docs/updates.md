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
| Install | the app, once the project is chosen | Writes only the files that changed into the project already on this iPad — by itself, or with one tap on **Update** |
| Reopen | **you** | Stop with ■, close the project and open it again, press ▶︎ (Swift Playgrounds keeps an open project as it was when it was opened) |
| Afterwards | the app | Says once what changed, and clears the download. If the old version starts again instead, it says so and shows the steps again |

Ablox Studio does the same from its own repository.

## Updating with one tap (2.1)

The first time, the app asks for its own project once: **Settings › Updates ›
Choose the project in Files** (or the same step on the install sheet), then
the Playgrounds folder (On My iPad or iCloud Drive) and **Ablox**. From then on:

- A new version is downloaded by itself (on Wi-Fi), and goes straight into the
  project, only the files that changed (`ProjectSync`). The banner's **Update**
  button does the same with one tap, downloading first if it has to.
- Swift Playgrounds builds a project as it was when it was opened, so the new
  files count once the project is closed and opened again: stop with ■, go back
  to the list of projects, open Ablox, press ▶︎. Closing Swift Playgrounds
  completely also works, but is not needed.
- The app remembers the version it wrote. If the next launch is still the old
  version, the banner says so and shows the steps again.
- Downloads try three times, waiting 2 and 5 seconds, when the connection drops
  or GitHub is busy, and fall back to GitHub's archive server
  (`codeload.github.com`) if the usual address fails (`UpdateRetry`). What
  still fails goes into **Settings › Problem reports** with the step and error
  code ("download: NSURLErrorDomain -1001"), so a report says exactly why.
- Every written file is read back; a folder that only looked writable is
  reported at once, not at the next build.
- If choosing the project does not work, the install sheet still offers the
  whole project: **Save to Files** (into the Playgrounds folder) or **Send to
  Swift Playgrounds**. That one is built whole, so its first build is slower.

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
automatic updates on finds it within the hour.

Then run `python3 scripts/changelog.py`: it adds the release, notes and all,
to `changelog.json` beside update.json — every version so far, newest first,
which the app shows in Settings → Updates → Update history
(`UpdateHistory`). `scripts/check-release.sh` and a test fail when
changelog.json does not start with update.json's release.

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
