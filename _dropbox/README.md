# Image drop-off

Drop full-resolution source images in this folder and they can be pulled,
downscaled and installed into the site.

Why this exists: the Google Drive connector refuses anything past about 6MB,
and the sandbox network policy blocks every Google domain, so there is no
fallback path to a large Drive file. GitHub is reachable with no practical
size limit.

## Currently waiting on

For the Biodiversity Research Center carousel:

| carousel position | file | size in Drive |
|---|---|---|
| 2 | `ND@7x-100.jpg` | 75.6 MB |
| 4 | `GP@10x-100.jpg` | 78.4 MB |
| 6 | `LS@14x-100.jpg` | 136.0 MB |
| 7 | `Artboard 2@14x-100.jpg` | 22.1 MB |
| 8 | `Artboard 3@14x-100.jpg` | 14.4 MB |

Also blocked, whenever they are wanted:

- `JSL03110-2.jpg`, `JSL03131-2.jpg`, `JSL03157 (1)-2.jpg`, `JSL03206-2.jpg` — Freedom by Design, 6.5–10 MB
- `11-14-mid-vig-2.jpg` — Within the Scape, 6.7 MB
- `ANIMATION.gif` — Planetary Machines, 6.9 MB

## How to add them

GitHub's web uploader accepts files up to 25 MB, which covers the two
Artboards: open this folder on the `image-dropbox` branch, choose
**Add file → Upload files**, drag them in, commit.

The three larger files exceed the web uploader. Attach those to a GitHub
**release** instead (Releases → Draft a new release → drag into *Attach
binaries*) — release assets allow up to 2 GB each and are not stored in
git history, so they do not bloat the repository.

Keep the original filenames either way.

## After they are installed

This branch and folder are temporary and should be deleted, so the large
originals never land in the site's history.
