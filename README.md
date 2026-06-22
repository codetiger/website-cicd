# website-cicd

Builds and deploys [codetiger](https://github.com/codetiger)'s personal website as a
**single package** to **Cloudflare Pages**. The individual pieces stay in their own repos
and are pulled in here as **git submodules**; this repo builds each with its own toolchain
and stitches the outputs into one `dist/` served under flat top-level paths.

## Site layout

| URL          | Source (submodule)             | Toolchain                              |
| ------------ | ------------------------------ | -------------------------------------- |
| `/`          | `home/` (this repo)            | plain static HTML                      |
| `/blog/`     | `projects/blog`                | Astro (base `/blog`)                   |
| `/avarta/`   | `projects/avarta`              | Rust + wasm-pack → Vite (relative base)|
| `/resume/`   | `projects/resume` (`master`)   | Python/Jinja2 → self-contained HTML    |

> **Vishwakarma** is intentionally not deployed yet: its height-tile pyramid is ~3.2 GB /
> ~87k files, far over Cloudflare Pages limits (20,000 files, 25 MiB/file). Wire it in once
> the pyramid is hosted on Cloudflare R2 and the viewer points at it via `VITE_TILE_BASE`.

## Local build

Prerequisites: **Node + npm**, **Python 3**, and **Rust + [wasm-pack](https://rustwasm.github.io/wasm-pack/)**
(for Avarta's WebAssembly).

```sh
# 1. Clone with submodules (or: git submodule update --init --recursive)
git clone --recurse-submodules git@github.com:codetiger/website-cicd.git
cd website-cicd

# 2. Build everything into ./dist
./scripts/build.sh

# 3. Preview the combined site
npx wrangler pages dev dist     # or: npx serve dist
```

Open `/`, then click through `/blog/`, `/avarta/`, and `/resume/` and confirm assets load
with no 404s.

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
   - `SSH_SUBMODULE_KEYS` — read-only SSH **deploy keys** for the submodules (below).
3. After the first deploy, add your **custom domain** under the Pages project's *Custom
   domains* tab (Cloudflare manages DNS automatically if the zone is on Cloudflare).

### Submodule SSH deploy keys (`SSH_SUBMODULE_KEYS`)

`.gitmodules` uses SSH URLs, so CI needs SSH access to clone them. Create one **read-only
deploy key per submodule repo** (a single deploy key cannot span repos):

```sh
ssh-keygen -t ed25519 -f blog_key   -N "" -C "website-cicd blog"
ssh-keygen -t ed25519 -f avarta_key -N "" -C "website-cicd avarta"
ssh-keygen -t ed25519 -f resume_key -N "" -C "website-cicd resume"
```

- Add each **`*_key.pub`** to the matching repo: *Settings → Deploy keys → Add deploy key*
  (read-only).
- Concatenate the three **private** keys into the `SSH_SUBMODULE_KEYS` secret (the
  `webfactory/ssh-agent` action loads multiple keys from one secret).

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
(`blog`/`avarta` track `main`, `resume` tracks `master`).

## Notes

- **Blog canonical URLs:** `projects/blog`'s `astro.config.mjs` has
  `site: 'https://codetiger.github.io'`, which only affects sitemap/RSS/canonical URLs.
  Update it to the production domain **in the blog repo**, then bump the submodule pointer.
  Routing works regardless.
- **resume branch:** pinned to `master` (the published static résumé). The Three.js résumé
  *game* lives on an unmerged branch; switch the submodule pointer if/when it lands on `master`.
