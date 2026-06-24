# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

`website-cicd` is an **aggregator / CI-CD repo**, not an application. It contains almost no
application code of its own — it pulls several independently-maintained projects in as **git
submodules** under `projects/`, builds each with its own toolchain, and stitches the outputs
into a single `dist/` that is deployed to **Cloudflare Pages**. The only first-party content
here is the landing page (`home/index.html`) and the build/deploy glue.

When a task touches a sub-project's *behavior*, the change belongs in that sub-project's own
repo (each has its own `CLAUDE.md`); this repo only orchestrates their builds and pins which
commit of each gets published.

## Commands

```sh
# First checkout (or after the pin changes)
git submodule update --init --recursive

# Build the whole site into ./dist  (needs: node+npm, rust+wasm-pack)
./scripts/build.sh

# Preview locally — serve dist/ at the ROOT so /blog/ /avarta/ /resume/ resolve
npx wrangler pages dev dist          # most faithful to Cloudflare Pages
npx serve dist                       # or any static server
python3 -m http.server 8000 -d dist  # zero-install

# Publish updated sub-project content: bump its submodule pointer here, then push
git -C projects/blog pull            # or check out a specific commit/tag
git add projects/blog && git commit -m "blog: bump" && git push   # → triggers deploy
git submodule update --remote        # bump ALL submodules to their tracked branch tips
```

There is no test suite in this repo. Each sub-project tests itself in its own repo.

## Architecture

### URL → submodule → toolchain

| URL        | Source                       | Build                                            | Output copied to |
| ---------- | ---------------------------- | ------------------------------------------------ | ---------------- |
| `/`        | `home/`                      | none (plain static HTML)                         | `dist/`          |
| `/blog/`   | `projects/blog`              | `npm ci && npm run build` (Astro)                | `dist/blog/`     |
| `/avarta/` | `projects/avarta`            | `wasm-pack build crates/avarta-wasm` → `web/`; `cd web && npm ci && npm run build` | `dist/avarta/` |
| `/resume/` | `projects/resume` (`master`) | `npm ci && npm run build` (Vite — game + static résumé) | `dist/resume/`   |
| `/design-system/` | `design-system/` (this repo) | none (plain CSS) — `cp -R` to dist | `dist/design-system/` |

`build.sh` does a clean build (`rm -rf dist` first). It only runs `git submodule update
--init` when a submodule is **missing**, so a deliberately-modified submodule working tree is
never clobbered — you can hack on `projects/<x>` in place and rerun `./scripts/build.sh`.

### Shared design system → `/design-system/`

`design-system/` is the **single visual source of truth** for the whole family (tokens +
components; see its own `README.md`). `build.sh` does two things with it: (1) copies it to
`dist/design-system/` so consumers load it at runtime with one
`<link href="/design-system/design-system.css">` (works because everything is one
same-origin deploy), and (2) exports `DESIGN_SYSTEM_DIR="$ROOT/design-system"` so the sub-projects'
dev servers can locate it to serve `/design-system/` locally. Every page links the published copy
(the résumé links `tokens.css`; the others `design-system.css`), so a design-system edit
re-deploys site-wide on the next aggregator build with no per-project rebuild. Sub-project
adoption (the `<link>` + restyle) lands in each project's own repo, then its pointer is bumped
here — see `design-system/README.md` § Distribution.

### Why the path stitching works (the key non-obvious bit)

`scripts/build.sh` copies each project's build output into a `dist/<name>/` subfolder. This
only produces correct asset URLs because of each project's base-path config — verify these
before changing mount paths:

- **blog**: Astro `base: '/blog'` (hardcoded in its `astro.config.mjs`) → emits `/blog/...`
  absolute URLs, so it must be served at `/blog/`.
- **resume** (`master`): Vite `base: '/resume/'` in the build → both pages (`index.html` game +
  `resume.html` static) emit `/resume/...` URLs, so they must be served at `/resume/`.
- **avarta**: Vite `base: './'` (relative) → works at any depth.

Changing a project's mount path generally requires changing that project's base config in its
own repo, not just `build.sh`.

### Deploy

`.github/workflows/deploy.yml` builds the combined `dist/` and runs `wrangler pages deploy`.
**Triggers are `push` to this repo's `main` and `workflow_dispatch` only** — pushes to the
sub-project repos do **not** deploy. A submodule-pointer bump committed here is the deploy
trigger. The Pages project name (`codetiger-website`) is hardcoded in the `wrangler pages
deploy --project-name` flag.

- **No manual Pages setup needed.** An idempotent "Ensure Pages project exists" step
  (`wrangler pages project create codetiger-website`) self-bootstraps the project on first
  deploy and no-ops thereafter. Custom domain still has to be added once in the Cloudflare UI.
- **CI tool versions** (match these locally to reproduce a build): Node 24, Rust `stable` with
  the `wasm32-unknown-unknown` target.
- `concurrency: { group: deploy, cancel-in-progress: true }` — a newer deploy cancels an
  in-flight one, so the latest commit always wins.

### Submodules use SSH URLs

`.gitmodules` uses `git@github.com:` URLs. CI therefore loads SSH **deploy keys** via
`webfactory/ssh-agent` *before* `actions/checkout` (one read-only key per submodule repo,
concatenated into the `SSH_SUBMODULE_KEYS` secret). Required CI secrets: `CLOUDFLARE_API_TOKEN`,
`CLOUDFLARE_ACCOUNT_ID`, `SSH_SUBMODULE_KEYS`.

## Important constraints / gotchas

- **resume** (`master`) is a single Vite build: the Three.js *game* (`index.html`) plus a static
  `resume.html` rendered from `resume.json` by a Vite plugin (`src/resume/render.ts`). No Python —
  `build.sh` just runs `npm ci && npm run build`.
- **vishwakarma is intentionally not deployed.** Its `web/public` tile pyramid is ~3.2 GB /
  ~87k files, far over Cloudflare Pages limits (20,000 files, 25 MiB/file). It can be added
  only after the pyramid moves to Cloudflare R2 and the viewer reads it via `VITE_TILE_BASE`.
  Keep total `dist/` under those limits when adding anything.
- **blog `site` config**: `projects/blog`'s `astro.config.mjs` has `site:
  'https://codetiger.github.io'`, which only affects sitemap/RSS/canonical URLs. The production
  domain change must happen in the blog repo, then the submodule pointer bumped here.
