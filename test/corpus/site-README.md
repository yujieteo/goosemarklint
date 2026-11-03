# site

This is the personal website of Teo Yu Jie, at https://teoyujie.org/. It holds a home page of selected explorations, the beam diagram tool, the
privacy and support pages of Lullapixie and Marklove, the OpenPGP key of contact@teoyujie.org, and the
template of the log at `/log`.
`REQUIREMENTS.md` says what the site must do.

| Path | Holds |
| --- | --- |
| `public/` | Everything the server serves, as it is served. |
| `beamdiag/` | The beam diagram creator, a Goose program that builds to WebAssembly. `beamdiag/REQUIREMENTS.md` is its contract. |
| `wallpaper/` | The wallpaper maker, a Goose program (`wallpaper.goose`) with a C host (`host.c`) that builds to WebAssembly. `wasm.sha256` is the hash of its sources. |
| `public/fonts/` | The site fonts, Inter (Google Fonts v20, variable) and IBM Plex Mono (weight 400), with their OFL licences. |
| `public/shared/kowalski.css` | The tokens and interaction rules of the site look. `public/style.css` imports it. |
| `public/play/beamdiag/` | The built beam page. `index.html` and `beamdiag.wasm.gz` come from `scripts/build-beam.sh`. Never edit them by hand. |
| `public/play/wallpaper/` | The wallpaper page. `wallpaper.wasm.gz` comes from `scripts/build-wallpaper.sh`. Never edit it by hand. |
| `media-plan.md` | The master copy of the media plan. The pond app edits it. |
| `scripts/build-beam.sh [folder]` | Builds the beam page into `public/play/beamdiag/` or into the folder. |
| `scripts/build-wallpaper.sh` | Builds the wallpaper module with `goose` and `emcc` and writes `wallpaper/wasm.sha256`. |
| `scripts/check.sh [--replay [--accept]]` | Installs from `bun.lock`, then runs `tsc --noEmit` (strict) and `knip` over the TypeScript, then `scripts/check-site.ts`: pages and WKD key files exist, links resolve, the home page keeps its links and each selected exploration has a kind, a title and a link, the log template has one entries slot, each essay figure has a caption and alt text, the home page and beam page first loads are inside their gzipped budgets (100 KB and 590 KB), TypeScript has no comment without an `https://` source and no `any`, non-null assertion, cast or type argument on a DOM query. It also checks that `scripts/*.sh`, `wallpaper/` and the `beamdiag/` sources have no comments (source credits excepted), that `beamdiag/` builds the committed beam page, that the wallpaper module matches its sources, and that `bun test` and `beamdiag/test.goose` (built with ASan and UBSan) pass. It needs `bun`, `node`, `cc` and the beam build tools. It stops if `beamdiag/c/test.sha256` does not match the test inputs: then set `GOOSE` to make `beamdiag/c/test.c` again. With `--replay` it also captures the inputs of `bun test` and replays them on `main` and on `HEAD` (`scripts/replay.ts`); it fails on any output difference unless `--accept` is given. |
| `scripts/deploy.sh` | Runs the check, sends `public/` as a tar archive to deploy@10.8.0.1 over the VPN, then tests the URLs. |

The beam build needs `emcc`, `cc` and `gzip`, and `bun` 1.4.4 when `GOOSE` is set. It uses the Goose C committed in `beamdiag/c/`. It stops if `beamdiag/c.sha256` does not match the Goose inputs: then set `GOOSE` to make the C again.

The wallpaper build needs `goose` and `emcc`. Set `GOOSE` and `EMCC` to use other binaries.

The site before 2026-10-18 (notebooks, stories, Play tools, the engine) is at the tag `old-site`.
