# website-cicd

Builds and deploys [codetiger](https://github.com/codetiger)'s personal website as a
**single package** to **Cloudflare Pages**. The individual pieces stay in their own repos
and are pulled in here as **git submodules**; this repo builds each with its own toolchain
and stitches the outputs into one `dist/` served under flat top-level paths.

## Site layout

| URL               | Source (submodule)             | Toolchain                                   |
| ----------------- | ------------------------------ | ------------------------------------------- |
| `/`               | `home/` (this repo)            | plain static HTML                           |
| `/projects/`      | `home/projects/` (this repo)   | plain static HTML                           |
| `/blog/`          | `projects/blog`                | Astro (base `/blog`)                        |
| `/avarta/`        | `projects/avarta`              | Rust + wasm-pack → Vite (relative base)     |
| `/resume/`        | `projects/resume` (`master`)   | Vite — Three.js game + static résumé        |
| `/tamil/`         | `projects/tamil`               | Rust + wasm-pack → static site (no bundler) |
| `/earth/`         | `projects/vishwakarma`         | Vite voxel viewer (tiles streamed from R2)  |
| `/design-system/` | `design-system/` (this repo)   | plain CSS — shared tokens + components       |

After all outputs are stitched into `dist/`, the build minifies every `*.html`/`*.css`/`*.js`
in place (mangling only, no obfuscation), skipping the already-minified Astro/Vite mounts. See
[*Production minification*](#production-minification) below.

> **Earth tiles are never bundled.** Vishwakarma's height-tile pyramid is ~3.2 GB / ~87k files,
> far over Cloudflare Pages limits (20,000 files, 25 MiB/file). The deployed viewer streams tiles
> at runtime from a public Cloudflare R2 URL via `VITE_TILE_BASE` (the pyramid is gitignored, so
> a clean checkout has none); override the base with the `VISHWAKARMA_TILE_BASE` env var.

## Local build

Prerequisites: **Node + npm** and **Rust + [wasm-pack](https://rustwasm.github.io/wasm-pack/)**
(for Avarta's and Tamil's WebAssembly). The minifier's npm deps install automatically.

```sh
# 1. Clone with submodules (or: git submodule update --init --recursive)
git clone --recurse-submodules git@github.com:codetiger/website-cicd.git
cd website-cicd

# 2. Build everything into ./dist  (set MINIFY=0 for a readable, un-minified dist/)
./scripts/build.sh

# 3. Preview the combined site
npx wrangler pages dev dist     # or: npx serve dist
```

Open `/`, then click through `/projects/`, `/blog/`, `/avarta/`, `/resume/`, `/tamil/`,
`/earth/`, and `/design-system/` and confirm assets load with no 404s.

### Production minification

As its final step, `./scripts/build.sh` runs `scripts/minify.mjs`, which walks `dist/` and
minifies **every `*.html`/`*.css`/`*.js`** in place — identifier mangling only, never
obfuscation (which would *grow* files). It's extension-driven, so new first-party files need no
config. It **skips the `blog`/`avarta`/`resume`/`earth` mounts**, which already ship minified
from their own Astro/Vite bundlers (re-minifying would orphan resume's source map), so the pass
effectively covers `home/`, `design-system/`, and `tamil/`'s static assets. esbuild handles
CSS/JS (no bundling, modern CSS left intact); html-minifier-terser handles HTML. Cloudflare Pages
applies Brotli/gzip at the edge, so nothing is pre-compressed. Set `MINIFY=0` to skip the pass.

## Deploying

A push to `main` (or a manual **Run workflow**) triggers
[`.github/workflows/deploy.yml`](.github/workflows/deploy.yml): it builds the combined
`dist/` and runs `wrangler pages deploy`. **Pushes to the sub-project repos do not deploy
anything** — see *Publishing sub-project updates* below.

### One-time Cloudflare setup

1. Create the Pages project (name must match `--project-name` in the workflow, currently
   `codetiger-website`):
   ```sh
   npx wrangler pages project create codetiger-website
   ```
2. Add these **GitHub Actions secrets** to this repo:
   - `CLOUDFLARE_API_TOKEN` — token scoped **Account → Cloudflare Pages → Edit**.
   - `CLOUDFLARE_ACCOUNT_ID` — your Cloudflare account ID.
   - `SSH_SUBMODULE_KEYS` and `SSH_SUBMODULE_KEYS_2` — read-only SSH **deploy keys** for the
     five submodules, split across two secrets (below).
3. After the first deploy, add your **custom domain** under the Pages project's *Custom
   domains* tab (Cloudflare manages DNS automatically if the zone is on Cloudflare).

### Submodule SSH deploy keys (`SSH_SUBMODULE_KEYS` + `SSH_SUBMODULE_KEYS_2`)

`.gitmodules` uses SSH URLs, so CI needs SSH access to clone them. Create one **read-only
deploy key per submodule repo** (a single deploy key cannot span repos). The key's **comment
must be the submodule's SSH URL** — `webfactory/ssh-agent` maps each key to its repo by comment:

```sh
ssh-keygen -t ed25519 -f blog_key    -N "" -C "git@github.com:codetiger/blog.git"
ssh-keygen -t ed25519 -f avarta_key  -N "" -C "git@github.com:codetiger/Avarta.git"
ssh-keygen -t ed25519 -f resume_key  -N "" -C "git@github.com:codetiger/resume.git"
ssh-keygen -t ed25519 -f tamil_key   -N "" -C "git@github.com:codetiger/tamil-yaappu-analyzer.git"
ssh-keygen -t ed25519 -f earth_key   -N "" -C "git@github.com:codetiger/vishwakarma.git"
```

- Add each **`*_key.pub`** to the matching repo: *Settings → Deploy keys → Add deploy key*
  (read-only) — e.g. `gh repo deploy-key add blog_key.pub -R codetiger/blog`.
- Concatenate the **private** keys into two secrets (Actions secrets are write-only, so they're
  split to allow appending later): `SSH_SUBMODULE_KEYS` = blog + avarta + resume,
  `SSH_SUBMODULE_KEYS_2` = tamil + vishwakarma. `deploy.yml` feeds both to `webfactory/ssh-agent`,
  which loads multiple keys from each secret.

## Publishing sub-project updates

Sub-repo pushes don't deploy. To publish new content from a sub-project, bump its pointer
in this repo and push:

```sh
git -C projects/blog pull          # or check out the desired commit/tag
git add projects/blog
git commit -m "blog: bump"
git push                           # → triggers a deploy
```

`git submodule update --remote` bumps all tracked submodules to their branch tips at once
(`resume` tracks `master`; `blog`, `avarta`, `tamil`, and `vishwakarma` track `main`).

## Notes

- **Blog canonical URLs:** `projects/blog`'s `astro.config.mjs` has
  `site: 'https://codetiger.github.io'`, which only affects sitemap/RSS/canonical URLs.
  Update it to the production domain **in the blog repo**, then bump the submodule pointer.
  Routing works regardless.
- **resume branch:** pinned to `master` (the published static résumé). The Three.js résumé
  *game* lives on an unmerged branch; switch the submodule pointer if/when it lands on `master`.
