# Ablox Games

The public list of worlds people have published for
[Ablox](https://github.com/prak59459-create/Ablox).

This repository *is* the server. Ablox reads `index.json` from it over HTTPS
and downloads the worlds and covers it names — there is no backend, no account
and no upload form. Publishing a game is a pull request, which is also the
review step an upload form would not have.

> **Copy this folder into a new, public repository** and point the app at it:
> Ablox → Settings → Game list. The app ships expecting
> `prak59459-create/AbloxGames`.

## Layout

```
index.json                       the list the app reads
games/
  sky-temple/
    world.ablox                  the world, exactly as Ablox Studio saved it
    cover.png                    1200 × 675
    main.absc                    optional: script files, listed under "scripts"
    listing.json                 this game's entry, for convenience
```

Nothing else is read. Anything else in the repository is ignored.

## Adding a game

1. In **Ablox Studio**, open the world and tap the **publish** button in the
   toolbar (the document-with-an-arrow icon).
2. Studio writes three files into a folder named after the game: `world.ablox`,
   `cover.png` (drawn from the world) and `listing.json`.
3. Put that folder under `games/` in a fork of this repository.
4. Paste the contents of `listing.json` into the `games` array in `index.json`.
5. Open a pull request.

Once it is merged, the game appears in everyone's **Games** tab. There is no
publish delay — the app reads the file directly.

## What a listing looks like

```json
{
  "id" : "sky-temple",
  "title" : "Sky Temple",
  "author" : "Mika",
  "summary" : "Climb the towers and reach the gate.",
  "world" : "games/sky-temple/world.ablox",
  "cover" : "games/sky-temple/cover.png",
  "tags" : ["obstacle", "medium"],
  "blockCount" : 210,
  "maxPlayers" : 4,
  "schemaVersion" : 1,
  "updatedAt" : "2026-09-19T00:00:00Z"
}
```

| Field | Rules |
|---|---|
| `id` | lowercase ASCII letters, digits and single hyphens, ≤ 64 characters. It is a folder name on people's iPads, so it must be unique in this repository. |
| `title` | ≤ 60 characters, not empty |
| `author` | ≤ 40 characters, may be empty |
| `summary` | ≤ 280 characters |
| `world` | a path inside this repository, ending `.ablox` or `.json` |
| `cover` | optional, ending `.png`, `.jpg` or `.jpeg` |
| `scripts` | optional list of `.absc` files in this repository, run with the world (up to 32, 1 MB each) |
| `tags` | at most 8, each ≤ 24 characters |
| `blockCount` | the real number — the app compares it and says so if it is wrong |
| `schemaVersion` | the world file's own version. An app too old to read it shows the game greyed out rather than failing. |

The app **refuses** a listing whose path leaves this repository, names another
host, or points at a hidden file. Those rules are enforced on the iPad, not
here, so a mistake in a pull request cannot reach anyone.

## Reviewing a pull request

The app is read by children, so the bar is not only "does it parse":

- **Open the world in Studio and walk it.** A game that cannot be finished is
  the most common problem and the one no check catches.
- The cover should be a picture of the world, not something else.
- The title, summary and tags should say what the game is, in language
  suitable for a classroom.
- `blockCount` should match. Studio fills it in; a hand-edited entry often
  does not.

## Limits

These are enforced by the app, so a listing that exceeds them is simply not
shown:

| | |
|---|---|
| `index.json` | 2 MB, 1000 games |
| a world file | 8 MB, 5000 parts |
| a cover | 4 MB |

## Licence

Each game belongs to whoever made it. By opening a pull request you are saying
the world is yours to share and that others may download and play it.
