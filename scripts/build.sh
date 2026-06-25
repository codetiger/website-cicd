#!/usr/bin/env bash
# Build the combined personal website into ./dist.
#
# Each sub-project is a git submodule under projects/ and is built with its own
# toolchain, then its output is copied under a flat top-level path:
#
#   /          home/                  this repo (plain static HTML)
#   /blog/     projects/blog          Astro, base "/blog"
#   /avarta/   projects/avarta        Rust+wasm -> Vite, relative base "./"
#   /resume/   projects/resume        Three.js + Vite game (base "/resume/") + static résumé (one Vite build)
#   /tamil/    projects/tamil         Rust+wasm static site (no bundler), relative paths
#   /earth/    projects/vishwakarma   Vite voxel viewer (relative base), tiles streamed from R2
#
# Requires on PATH: node + npm, rust + wasm-pack (for Avarta's & Tamil's wasm).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST="$ROOT/dist"
# Single source of truth for the shared design system. Published to /design-system/
# below and linked at runtime by every page (home/blog/avarta/resume). Exported so the
# sub-projects' dev servers can find it to serve locally (overrides their default lookup).
export DESIGN_SYSTEM_DIR="$ROOT/design-system"
cd "$ROOT"

# Ensure submodules are checked out. No-op in CI (actions/checkout already did
# it) and skipped when they're present, so a deliberately-modified submodule
# working tree is never clobbered.
if [ ! -f projects/blog/package.json ] \
  || [ ! -f projects/avarta/web/package.json ] \
  || [ ! -f projects/resume/package.json ] \
  || [ ! -f projects/tamil/wasm/Cargo.toml ] \
  || [ ! -f projects/vishwakarma/web/package.json ]; then
  echo "==> Initializing submodules"
  git submodule update --init --recursive
fi

echo "==> Cleaning $DIST"
rm -rf "$DIST"
mkdir -p "$DIST"

echo "==> Home page -> /"
cp -R "$ROOT/home/." "$DIST/"

echo "==> design system -> /design-system/"
# Serve the whole folder so tokens.css + design-system.css are linkable at
# /design-system/... (the relative @import "./tokens.css" keeps resolving) and the
# living style guide (index.html) is browsable as a visual-regression surface.
mkdir -p "$DIST/design-system"
cp -R "$DESIGN_SYSTEM_DIR/." "$DIST/design-system/"

echo "==> blog (Astro) -> /blog/"
(
  cd "$ROOT/projects/blog"
  npm ci
  npm run build
)
mkdir -p "$DIST/blog"
cp -R "$ROOT/projects/blog/dist/." "$DIST/blog/"

echo "==> avarta (Rust wasm + Vite) -> /avarta/"
(
  cd "$ROOT/projects/avarta"
  # --out-dir is relative to the crate dir (crates/avarta-wasm), so this lands in
  # web/pkg, exactly as Avarta's own deploy workflow does it.
  wasm-pack build crates/avarta-wasm --target web --release --out-dir ../../web/pkg
  cd web
  npm ci
  npm run build
)
mkdir -p "$DIST/avarta"
cp -R "$ROOT/projects/avarta/web/dist/." "$DIST/avarta/"

echo "==> resume (Three.js game + static résumé, Vite) -> /resume/"
(
  cd "$ROOT/projects/resume"
  npm ci
  # One `vite build` emits both pages: the Three.js game (index.html) and the static
  # résumé (resume.html, rendered from resume.json by a Vite plugin). Base is '/resume/'
  # and publicDir is 'assets', so the output lands in dist/ ready to serve at /resume/.
  npm run build
)
mkdir -p "$DIST/resume"
cp -R "$ROOT/projects/resume/dist/." "$DIST/resume/"

echo "==> tamil grammar analyzer (Rust wasm) -> /tamil/"
# Static site, no bundler: index.html links css/ + js/ relatively and js/app.js imports
# ../pkg/, so a flat copy under dist/tamil/ resolves correctly. Mirrors the project's own
# deploy-pages.yml, minus the optional esbuild minification (assets shipped as-is).
(
  cd "$ROOT/projects/tamil"
  # wasm-pack's --out-dir is relative to the crate dir (wasm/), so this lands in wasm/pkg.
  wasm-pack build wasm --target web --release --out-dir pkg
)
mkdir -p "$DIST/tamil/pkg"
cp "$ROOT/projects/tamil/web/index.html" "$DIST/tamil/"
cp -R "$ROOT/projects/tamil/web/css" "$ROOT/projects/tamil/web/js" "$DIST/tamil/"
cp "$ROOT/projects/tamil/wasm/pkg/tamil_yaappu_wasm.js" \
   "$ROOT/projects/tamil/wasm/pkg/tamil_yaappu_wasm_bg.wasm" "$DIST/tamil/pkg/"

echo "==> earth in voxels (Vite viewer; tiles from R2) -> /earth/"
# The 3.2 GB tile pyramid is NOT bundled — the viewer streams it at runtime from VITE_TILE_BASE
# (a public Cloudflare R2 url). The pyramid is gitignored upstream, so a clean/CI checkout has
# none; a local dev checkout may, so we move it aside for the build to keep dist/earth small.
# Tiles are served from a public Cloudflare R2 bucket (voxel-data) via a custom domain. The base
# must end in a slash and hold manifest.json + tiles/. Override per-build via the
# VISHWAKARMA_TILE_BASE env var (wired in deploy.yml); the default below is the live base.
: "${VISHWAKARMA_TILE_BASE:=https://voxel-data.codetiger.in/pyramid/}"
(
  cd "$ROOT/projects/vishwakarma/web"
  if [ -d public/pyramid ]; then
    mv public/pyramid ../pyramid.aside
    trap 'mv "$ROOT/projects/vishwakarma/pyramid.aside" "$ROOT/projects/vishwakarma/web/public/pyramid"' EXIT
  fi
  npm ci
  VITE_TILE_BASE="$VISHWAKARMA_TILE_BASE" npm run build
)
mkdir -p "$DIST/earth"
cp -R "$ROOT/projects/vishwakarma/web/dist/." "$DIST/earth/"

# Minify every *.html/*.css/*.js in dist/ (identifier mangling only, no obfuscation).
# scripts/minify.mjs walks dist/ by extension and skips the blog/avarta/resume/earth
# mounts, which already ship minified from their own Vite/Astro builds. MINIFY=0 skips
# the whole pass for a fast, readable dist/ when debugging locally; npm ci sits inside
# the gate so that debug path doesn't install the minifier deps.
if [ "${MINIFY:-1}" != "0" ]; then
  echo "==> Minifying first-party static assets"
  npm ci
  node "$ROOT/scripts/minify.mjs"
else
  echo "==> MINIFY=0 — skipping minification (dist/ left un-minified)"
fi

echo "==> Done. Combined site is in $DIST"
