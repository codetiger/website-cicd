#!/usr/bin/env node
// Production minifier — runs over dist/ after build.sh has stitched everything in.
//
// EXTENSION-DRIVEN (future-proof): every *.html / *.css / *.js found under dist/ is
// minified in place, so new first-party files (home, design-system, tamil) need no
// edit here. The ONLY thing kept explicit is the small, rarely-changing set of mounts
// whose output is ALREADY minified by its own Vite/Astro bundler — those are skipped:
//
//   dist/blog  dist/avarta  dist/resume  dist/earth
//
// Re-minifying them would be wasted work and would break things (e.g. resume ships a
// source map — re-minifying strips its //# sourceMappingURL and orphans the .map).
// Adding a new bundler-built sub-project means adding its mount to EXCLUDE_TOPLEVEL
// (and you're editing build.sh for it anyway). Everything else — home's pages, the
// hand-authored design system, tamil's static web/ + its wasm-bindgen glue .js — is
// fair game. The .wasm binary and non-code files (.mjs tooling, .json, .map, fonts,
// images) are skipped automatically because their extension isn't in EXT.
//
// Tooling (mangle-only; deliberately no heavy obfuscation — that would inflate size):
//   CSS  -> esbuild transform (conservative: strips whitespace/comments, never
//           rewrites OKLCH / light-dark() / relative-color / @layer / nesting, and
//           leaves @import "./tokens.css" intact so it keeps resolving).
//   JS   -> esbuild transform, NO bundle: preserves every import/export specifier
//           verbatim (tamil's ./components/…, ../pkg/… dynamic import) and only
//           mangles local identifiers.
//   HTML -> html-minifier-terser (esbuild can't do HTML): collapses markup and
//           minifies inline <script> via terser + inline <style> via clean-css.
import { readdir, readFile, writeFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import path from 'node:path';
import { transform as esbuildTransform } from 'esbuild';
import { minify as minifyHtml } from 'html-minifier-terser';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const DIST = path.join(ROOT, 'dist');

// Top-level dist/ dirs whose contents are already minified by their own bundler.
const EXCLUDE_TOPLEVEL = new Set(['blog', 'avarta', 'resume', 'earth']);
// extension -> minifier kind
const EXT = { '.html': 'html', '.css': 'css', '.js': 'js' };

// html-minifier-terser: also minify the inline <script> (terser mangle — size-reducing)
// and inline <style> (clean-css). The inline CSS in our HTML is plain layout CSS, safe
// for clean-css; modern-syntax CSS lives only in standalone .css files (handled by
// esbuild). Keep attributes that JS / a11y read.
const HTML_OPTS = {
  collapseWhitespace: true,
  conservativeCollapse: false,
  removeComments: true,
  minifyCSS: true,
  minifyJS: true,
  removeRedundantAttributes: false,  // keep type="module", type="text/css", etc.
  collapseBooleanAttributes: false,  // keep disabled / aria-* / data-* intact
  keepClosingSlash: true,
  decodeEntities: false,
};

// Walk dist/ and collect minifiable files, pruning the already-minified mounts at the
// top level only (a nested dir that happens to share a name is NOT excluded).
async function collect(dir, rel = '') {
  const found = [];
  const entries = await readdir(dir, { withFileTypes: true });
  for (const e of entries) {
    const childRel = rel ? `${rel}/${e.name}` : e.name;
    if (e.isDirectory()) {
      if (rel === '' && EXCLUDE_TOPLEVEL.has(e.name)) continue;
      found.push(...await collect(path.join(dir, e.name), childRel));
    } else if (e.isFile()) {
      const kind = EXT[path.extname(e.name).toLowerCase()];
      if (kind) found.push({ rel: childRel, kind });
    }
  }
  return found;
}

let failed = 0;
let savedBytes = 0;
const bytes = (s) => Buffer.byteLength(s, 'utf8');

async function minifyOne({ rel, kind }) {
  const file = path.join(DIST, rel);
  let src;
  try {
    src = await readFile(file, 'utf8');
  } catch (err) {
    failed++;
    console.error(`!! minify: cannot read ${rel} — ${err.message}`);
    return;
  }
  const before = bytes(src);
  try {
    let out;
    if (kind === 'html') {
      out = await minifyHtml(src, HTML_OPTS);
    } else if (kind === 'css') {
      // charset:'utf8' keeps non-ASCII (e.g. Tamil content) as compact UTF-8 bytes
      // instead of esbuild's default \uXXXX escapes (which would grow the file).
      ({ code: out } = await esbuildTransform(src, { loader: 'css', minify: true, charset: 'utf8' }));
    } else {
      // No `bundle` — transform() keeps import/export specifiers verbatim.
      // charset:'utf8' keeps Tamil string literals as UTF-8 (not \uXXXX).
      ({ code: out } = await esbuildTransform(src, { loader: 'js', format: 'esm', minify: true, charset: 'utf8' }));
    }
    await writeFile(file, out);
    const after = bytes(out);
    savedBytes += before - after;
    const pct = before ? Math.round((1 - after / before) * 100) : 0;
    console.log(`   ${rel}  ${before} -> ${after} B  (-${pct}%)`);
  } catch (err) {
    failed++;
    console.error(`!! minify failed (${kind}): ${rel} — ${err.message}`);
  }
}

// Process css, then js, then html (tidy grouped log); order is otherwise irrelevant.
const order = { css: 0, js: 1, html: 2 };
const targets = (await collect(DIST)).sort(
  (a, b) => order[a.kind] - order[b.kind] || a.rel.localeCompare(b.rel),
);

for (const t of targets) await minifyOne(t);

console.log(`==> Minified ${targets.length} files, ~${(savedBytes / 1024).toFixed(1)} KB saved`);
if (failed) {
  console.error(`==> Minification had ${failed} failure(s) — aborting build`);
  process.exit(1);
}
