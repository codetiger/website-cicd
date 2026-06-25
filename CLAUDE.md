# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

`website-cicd` is an **aggregator / CI-CD repo**, not an application. It contains almost no
application code of its own — it pulls several independently-maintained projects in as **git
submodules** under `projects/`, builds each with its own toolchain, and stitches the outputs
into a single `dist/` that is deployed to **Cloudflare Pages**. The only first-party content
here is the landing + projects pages (`home/`), the shared `design-system/`, and the
build/deploy glue (`scripts/build.sh` + `scripts/minify.mjs`).

When a task touches a sub-project's *behavior*, the change belongs in that sub-project's own
repo (each has its own `CLAUDE.md`); this repo only orchestrates their builds and pins which
commit of each gets published.

## Commands

```sh
# First checkout (or after the pin changes)
git submodule update --init --recursive

# Build the whole site into ./dist  (needs: node+npm, rust+wasm-pack)
./scripts/build.sh

# Preview locally — serve dist/ at the ROOT so /blog/ /avarta/ /resume/ /tamil/ /earth/ resolve
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
| `/`        | `home/index.html`            | none (plain static HTML)                         | `dist/`          |
| `/projects/` | `home/projects/`           | none (plain static HTML)                         | `dist/projects/` |
| `/blog/`   | `projects/blog`              | `npm ci && npm run build` (Astro)                | `dist/blog/`     |
| `/avarta/` | `projects/avarta`            | `wasm-pack build crates/avarta-wasm` → `web/`; `cd web && npm ci && npm run build` | `dist/avarta/` |
| `/resume/` | `projects/resume` (`master`) | `npm ci && npm run build` (Vite — game + static résumé) | `dist/resume/`   |
| `/tamil/`  | `projects/tamil`             | `wasm-pack build wasm` → `wasm/pkg`; flat copy of `web/` (no bundler) | `dist/tamil/` |
| `/earth/`  | `projects/vishwakarma`       | `cd web && npm ci && VITE_TILE_BASE=… npm run build` (Vite) | `dist/earth/` |
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
- **earth** (vishwakarma): Vite `base: './'` (relative) → works at any depth.
- **tamil**: no bundler / no base config — `web/index.html` links `css/` + `js/` relatively and
  `web/js/app.js` imports `../pkg/`, so a flat copy under `dist/tamil/` resolves on its own.

Changing a project's mount path generally requires changing that project's base config in its
own repo, not just `build.sh`.

### Production minification

After every project's output is in `dist/`, `build.sh` runs `scripts/minify.mjs`, which walks
`dist/` and minifies **every `*.html` / `*.css` / `*.js`** in place — identifier *mangling*
only, no obfuscation (obfuscation would *grow* files). It is **extension-driven**, so new
first-party files are picked up automatically with no list to maintain. It **skips the
`blog`/`avarta`/`resume`/`earth` mounts** (`EXCLUDE_TOPLEVEL` in the script), whose output is
already minified by their own Vite/Astro bundlers — re-minifying them is wasted work and would
orphan `resume`'s source map. So in practice the pass covers the raw `cp` copies: `home/`,
`design-system/`, and `tamil/`'s static `web/` + its wasm-bindgen glue `.js` (the `.wasm`
binary and non-code files like `.mjs` tooling are skipped — their extension isn't matched).

- **Tooling** lives in a root `package.json` + committed `package-lock.json` (the only npm
  manifest in this repo); the gate runs `npm ci` to install the two devDeps. **esbuild** handles
  CSS/JS (`charset:'utf8'` to keep Tamil text as compact UTF-8, **no bundle** so tamil's ESM
  imports and the dynamic `../pkg` wasm import survive, and modern CSS — OKLCH / `light-dark()` /
  relative-color / `@layer` / nesting — is left intact, never lowered to fallbacks).
  **html-minifier-terser** handles HTML, including inline `<script>` (terser) and `<style>`.
- **Gate:** on by default; `MINIFY=0 ./scripts/build.sh` skips the whole pass *and* its `npm ci`
  for a fast, readable `dist/` when debugging. CI leaves `MINIFY` unset → it minifies.
- **No pre-compression.** Cloudflare Pages applies Brotli/gzip at the edge, so we ship plain
  minified text — no `.br`/`.gz` artifacts.
- **Adding a new bundler-built sub-project?** Add its mount name to `EXCLUDE_TOPLEVEL` so its
  already-minified, source-mapped output isn't re-chewed (you're editing `build.sh` for it anyway).

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
`webfactory/ssh-agent` *before* `actions/checkout`. `webfactory` takes a newline-separated list of
private keys and maps each to its repo by the key's **comment**, which must be the submodule's SSH
URL (e.g. `git@github.com:codetiger/vishwakarma.git`). Required CI secrets: `CLOUDFLARE_API_TOKEN`,
`CLOUDFLARE_ACCOUNT_ID`, `SSH_SUBMODULE_KEYS`, `SSH_SUBMODULE_KEYS_2`.

There are **five** submodule repos, each with a read-only deploy key whose private half lives in a
secret — split across two because Actions secrets are **write-only** (can't be read back to append):
`SSH_SUBMODULE_KEYS` (blog, Avarta, resume) and `SSH_SUBMODULE_KEYS_2` (tamil-yaappu-analyzer,
vishwakarma); `deploy.yml` feeds both. **Adding a submodule means adding its deploy key**
(`gh repo deploy-key add <pub> -R codetiger/<repo>`) **and** appending its private key to one of
these secrets — or the CI checkout fails on that repo.

## Important constraints / gotchas

- **resume** (`master`) is a single Vite build: the Three.js *game* (`index.html`) plus a static
  `resume.html` rendered from `resume.json` by a Vite plugin (`src/resume/render.ts`). No Python —
  `build.sh` just runs `npm ci && npm run build`.
- **vishwakarma (`/earth/`) deploys the viewer only — never its tiles.** The `web/public/pyramid`
  height-tile pyramid is ~3.2 GB / ~87k files, far over Cloudflare Pages limits (20,000 files,
  25 MiB/file), so it is **never bundled**. The viewer streams tiles at runtime from a public
  Cloudflare R2 url via `VITE_TILE_BASE`. The pyramid is **gitignored upstream**, so a clean/CI
  checkout has none and the build is naturally small; a local dev checkout may have one, so
  `build.sh` moves `public/pyramid` aside for the build (restoring it via a `trap`). Set the R2
  base with the **`VISHWAKARMA_TILE_BASE`** env var — locally for `build.sh`, in CI via the
  `vars.VISHWAKARMA_TILE_BASE` GitHub Actions repo variable (passed in `deploy.yml`). Empty/unset
  falls back to the live default baked into `build.sh`: `https://voxel-data.codetiger.in/pyramid/`
  (a public R2 bucket on a custom domain). Keep total `dist/` under the Pages limits when adding
  anything.
- **blog `site` config**: `projects/blog`'s `astro.config.mjs` has `site:
  'https://codetiger.github.io'`, which only affects sitemap/RSS/canonical URLs. The production
  domain change must happen in the blog repo, then the submodule pointer bumped here.
