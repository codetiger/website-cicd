#!/usr/bin/env node
/* =============================================================================
   check-tokens.mjs — keep tokens.json honest against tokens.css. NO build step,
   NO dependencies; run it BY HAND whenever you touch tokens:

     node design-system/check-tokens.mjs

   It is intentionally NOT wired into scripts/build.sh or CI — the design system
   stays no-build. It reconciles token NAMES (not resolved values, which now use
   light-dark()/relative-colour and can't be string-compared): every custom
   property declared in tokens.css must appear as a `--name` key somewhere in
   tokens.json, and vice-versa. That catches the realistic drift — a token added,
   renamed, or removed in one file but not the other. Exit code 1 on any mismatch.
   ========================================================================== */
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

const here = dirname(fileURLToPath(import.meta.url));

// --- tokens.css: every `--name:` declaration + every `@property --name` --------
//     (comments stripped first so prose like `--line` can't be miscounted) -------
const css = readFileSync(join(here, "tokens.css"), "utf8").replace(/\/\*[\s\S]*?\*\//g, "");
const cssNames = new Set([
  ...[...css.matchAll(/(--[a-z0-9-]+)\s*:/gi)].map((m) => m[1]),
  ...[...css.matchAll(/@property\s+(--[a-z0-9-]+)/gi)].map((m) => m[1]),
]);

// --- tokens.json: every key that looks like a `--token` name, at any depth ------
const json = JSON.parse(readFileSync(join(here, "tokens.json"), "utf8"));
const jsonNames = new Set();
(function walk(node) {
  if (!node || typeof node !== "object") return;
  for (const [k, v] of Object.entries(node)) {
    if (k.startsWith("--")) jsonNames.add(k);
    walk(v);
  }
})(json);

const missingInJson = [...cssNames].filter((n) => !jsonNames.has(n)).sort();
const extraInJson = [...jsonNames].filter((n) => !cssNames.has(n)).sort();

const report = (label, list) => {
  if (!list.length) return;
  console.error(`\n${label} (${list.length}):`);
  for (const n of list) console.error(`  ${n}`);
};

if (missingInJson.length || extraInJson.length) {
  console.error("✗ tokens.json is out of sync with tokens.css");
  report("Declared in tokens.css but missing from tokens.json", missingInJson);
  report("Present in tokens.json but not declared in tokens.css", extraInJson);
  console.error("");
  process.exit(1);
}

console.log(`✓ tokens.json in sync with tokens.css — ${cssNames.size} tokens matched`);
