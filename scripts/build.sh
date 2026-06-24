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
#
# Requires on PATH: node + npm, rust + wasm-pack (for Avarta's wasm).
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
  || [ ! -f projects/resume/package.json ]; then
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

echo "==> Done. Combined site is in $DIST"
