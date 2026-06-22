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

# Build the whole site into ./dist  (needs: node+npm, python3, rust+wasm-pack)
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
| `/avarta/` | `projects/avarta`            | `wasm-pack build` → `cd web && npm run build`    | `dist/avarta/`   |
| `/resume/` | `projects/resume` (`master`) | `python3 build.py` (Jinja2)                      | `dist/resume/`   |

### Why the path stitching works (the key non-obvious bit)

`scripts/build.sh` copies each project's build output into a `dist/<name>/` subfolder. This
only produces correct asset URLs because of each project's base-path config — verify these
before changing mount paths:

- **blog**: Astro `base: '/blog'` (hardcoded in its `astro.config.mjs`) → emits `/blog/...`
  absolute URLs, so it must be served at `/blog/`.
- **resume** (`master`): `build.py` emits a single **self-contained** `public/index.html`
  (assets base64-inlined) → works at any path.
- **avarta**: Vite `base: './'` (relative) → works at any depth.

Changing a project's mount path generally requires changing that project's base config in its
own repo, not just `build.sh`.

### Deploy

`.github/workflows/deploy.yml` builds the combined `dist/` and runs `wrangler pages deploy`.
**Triggers are `push` to this repo's `main` and `workflow_dispatch` only** — pushes to the
sub-project repos do **not** deploy. A submodule-pointer bump committed here is the deploy
trigger. The Pages project name (`codetiger-website`) is hardcoded in the `wrangler pages
deploy --project-name` flag.

### Submodules use SSH URLs

`.gitmodules` uses `git@github.com:` URLs. CI therefore loads SSH **deploy keys** via
`webfactory/ssh-agent` *before* `actions/checkout` (one read-only key per submodule repo,
concatenated into the `SSH_SUBMODULE_KEYS` secret). Required CI secrets: `CLOUDFLARE_API_TOKEN`,
`CLOUDFLARE_ACCOUNT_ID`, `SSH_SUBMODULE_KEYS`.

## Important constraints / gotchas

- **resume is pinned to `master`** (the simple static Python résumé). A richer Three.js résumé
  *game* (Vite, base `/resume/`) lives on an unmerged branch — if it lands on `master`, the
  resume build step in `build.sh` must switch to the Python+`npm run build` (Vite) flow.
- **vishwakarma is intentionally not deployed.** Its `web/public` tile pyramid is ~3.2 GB /
  ~87k files, far over Cloudflare Pages limits (20,000 files, 25 MiB/file). It can be added
  only after the pyramid moves to Cloudflare R2 and the viewer reads it via `VITE_TILE_BASE`.
  Keep total `dist/` under those limits when adding anything.
- **blog `site` config**: `projects/blog`'s `astro.config.mjs` has `site:
  'https://codetiger.github.io'`, which only affects sitemap/RSS/canonical URLs. The production
  domain change must happen in the blog repo, then the submodule pointer bumped here.
