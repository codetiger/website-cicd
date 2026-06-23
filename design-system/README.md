# codetiger Design System

The single visual source of truth for the **codetiger** website family
(Harishankar Narayanan). It unifies the landing page, the Astro blog, the résumé
(document + game), the Avarta seashell viewer and the Vishwakarma voxel viewer
under one identity, one set of tokens, and one component library.

> Open **[`index.html`](./index.html)** in a browser for the living style guide — every
> token and component, in every state, with a **backdrop** toggle and a **dark/light**
> (ink) toggle.

```
design-system/
├── index.html          ← living style guide (the canonical consumer of the CSS below)
├── tokens.css          ← every design decision as a CSS custom property (dark · light · print)
├── tokens.json         ← machine-readable mirror of tokens.css
├── design-system.css   ← reset + base elements + every component as a reusable class (imports tokens.css)
└── README.md           ← this file
```

No build step, no preprocessor — plain CSS custom properties so the no-build static
résumé, the Astro blog and the Vite viewers can all `<link>` the same files. The CSS is
written in modern, **Baseline** features (all native, no toolchain): **OKLCH** colour,
**`light-dark()`** theming, **relative-colour syntax** (`oklch(from …)`) so borders and
tints derive from one accent seed, and **`@layer`** for clean overrides.
`tokens.json` mirrors `tokens.css`; run `node design-system/check-tokens.mjs`
after editing tokens to confirm they haven't drifted (hand-run only — never wired into a build).

---

## Identity — a deep-navy cinematic console

The whole family shares one look, **derived from the single-page résumé**:

- **Canvas** — near-black navy `#05090f`; surfaces a notch lighter (`#0f1d2e`).
- **Hairlines, not grey borders** — every divider is a *cyan-tinted* 1px line
  (`rgb(140 220 255 / 0.16)`). This is the signature.
- **Blue-white text ladder** — `#e8f3ff` → `#bcd0e6` → `#7e94ad` → `#52677e`.
- **A cyan / gold / mint accent trio** that **glows** rather than casts shadow —
  cyan `#8cdcff`, gold `#ffd166`, mint `#7ef7c8`.
- **Type** — Inter (body) · Space Grotesk (display & wordmark) · JetBrains Mono (data).
- **Signature backdrop** (opt-in) — radial cyan + gold glows over a faint 44px cyan grid.

Depth is built from **cyan hairlines + a notch-lighter surface + soft glow**, not from
heavy drop shadows. Hard shadows are reserved for *floating chrome* (dropdowns, HUD
panels, modals, drawers).

### The accent contract

> **Cyan** = link + hover + focus + current + the single primary action.
> **Gold** = dates, awards, external/contact links.
> **Mint** = platform pills + success.
> Nothing else gets an accent colour.

There is **one identity across all rooms** — no per-app hue divergence. Blog, résumé,
Avarta and Vishwakarma all wear the same navy/cyan skin.

---

## Using the system

### 1. Load the web fonts + the CSS

```html
<link rel="preconnect" href="https://fonts.googleapis.com" />
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin />
<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Space+Grotesk:wght@500;600;700&family=Inter:wght@400;500;600&family=JetBrains+Mono:wght@400;500&display=swap" />

<!-- one file pulls in tokens.css automatically -->
<link rel="stylesheet" href="/design-system/design-system.css" />
```

Each family degrades to a system stack if its web font is unavailable, so the fonts
link is recommended but not required.

### 2. (Optional) turn on the signature backdrop

```html
<body class="brand-backdrop">   <!-- radial glows + 44px cyan grid; drops to flat in print -->
```

Pages are flat navy by default; add `.brand-backdrop` to `<body>` (or a full-bleed
wrapper) for the cinematic backdrop. Good for the landing hero, résumé and viewers;
skip it on long, text-dense blog articles.

### 3. (Optional) switch to ink mode for print/PDF

```html
<html data-theme="light">   <!-- also auto-applied under @media print -->
```

Light mode flips to near-black ink on white, swaps cyan for a dark readable blue, and
drops every glow/gradient. This is what the résumé PDF/paper output uses.

### 4. Use the component classes

```html
<button class="btn btn--primary">Save</button>
<a class="card" href="…"><h3>Title →</h3><p>Body</p></a>
<div class="eyebrow">▸ Experience</div>
<span class="tag tag--chip">Rust</span>      <!-- cyan skill chip -->
<span class="tag pill--mint">iOS</span>      <!-- mint platform pill -->
<article class="prose prose--triangle"> … </article>
<div class="hud-panel"> … </div>
```

See `index.html` for the full catalogue: buttons, links, cards, nav/header (+ floating
viewer header), dropdown, tags/chips/pills, badges, code, blockquote, table, form
fields, slider, hero (glow heading), alerts, pager, author + contact line, footer,
HUD panel and prose.

### 5. Override cleanly (cascade layers)

The whole stylesheet lives in cascade layers, declared in this order:

```css
@layer reset, base, tokens, components, utilities, a11y;
```

Because **layered rules always lose to un-layered rules**, a project that adopts the
system can override any component with its own plain CSS — no specificity battles, no
`!important`:

```css
/* your own stylesheet, loaded after design-system.css */
.btn--primary { border-radius: 0; }   /* wins: it's un-layered, the DS rule is layered */
```

If you *want* the DS to keep winning over part of your CSS, wrap that part in an earlier
layer. The override surface is explicit by design.

### Optional: cross-document view transitions

The site is a same-origin multi-page set of sub-apps (`/`, `/blog/`, `/avarta/`,
`/resume/`), so it's a good fit for native cross-document transitions. This is **not**
shipped in `design-system.css` (it would impose navigation behaviour on every consumer) —
add it per sub-app if you want it:

```css
@view-transition { navigation: auto; }
@media (prefers-reduced-motion: reduce) {
  ::view-transition-group(*), ::view-transition-old(*), ::view-transition-new(*) { animation: none; }
}
```

---

## Token reference (summary)

Full values live in `tokens.css` / `tokens.json`. Colours are authored in **OKLCH** (the
hex below is the exact sRGB equivalent, shown for reference); each themed colour is one
`light-dark(dark, ink)` declaration, and the cyan-tinted borders/tints derive from
`--color-accent` via `oklch(from …)`. Highlights:

- **Surfaces** `--color-bg #05090f` · `--color-bg-elevated #0f1d2e` · `--color-surface-2 #0a1320` · `--color-bg-inset #03060b`
- **Borders (cyan-tinted)** `--color-border` 16% · `-muted` 8% · `-strong` 34% of cyan
- **Text** `--color-fg #e8f3ff` · `-secondary #bcd0e6` · `--color-muted #7e94ad` · `--color-subtle #52677e`
- **Accent** cyan `--color-accent #8cdcff` · `-hover #b8ecff` · gold `--color-accent-2 #ffd166` · mint `--color-accent-3 #7ef7c8`
- **Semantic** success `#7ef7c8` · warning `#ffd166` · danger `#ff8b82` · info `#79c0ff`
- **Type** `--font-sans` Inter · `--font-display` Space Grotesk · `--font-mono` JetBrains Mono; scale `--text-eyebrow 0.7rem` → `--text-display-xl clamp(2rem,6vw,3.5rem)`
- **Spacing** `--space-0..12` (0 → 4rem) + `--space-page` (clamp)
- **Radii** `xs 3` · `sm 5` · `md 6` · `lg 8` · `xl 10` (cards) · `3xl 14` (HUD) · `pill` · `full`
- **Glow** `--glow-text` · `--glow-avatar` · `--glow-accent` · `--glow-gold`
- **Shadows** `sm · md · lg · cockpit · drawer` (floating chrome only)
- **Motion** `--dur-fast 150ms` · `medium 260ms` · `slow 400ms`; `--ease-standard / -out / -emphasized`
- **Z-index** `raised 10 → toast 80`

---

## Do / don’t

- **Do** build depth with cyan hairlines + a notch-lighter surface + glow.
  **Don’t** add drop-shadows to cards, code blocks or prose — shadows are for floating
  chrome only.
- **Do** keep exactly one primary (cyan) button per view. **Don’t** place two side by side.
- **Do** reserve cyan for the contract, gold for dates/external links, mint for pills/success.
  **Don’t** colour decorative text or icons with an accent.
- **Do** keep tags, dates, labels and code in `--font-mono` so they read as data.
- **Do** use `.brand-backdrop` deliberately (hero, résumé, viewers); **don’t** layer the
  44px grid behind long-form article text.
- **Do** restrict `--color-subtle` (#52677e, ~3.4:1) to large/secondary text, borders and
  disabled states. **Don’t** use it for body copy.
- **Do** rely on the global `:focus-visible` cyan outline (it’s overflow-safe).
- **Do** wrap non-essential animation in `prefers-reduced-motion` (base CSS handles the
  global case).

### Accessibility / contrast (verified against the navy canvas `#05090f`)

| Pair | Ratio | Verdict |
| --- | --- | --- |
| `--color-fg #e8f3ff` on `--color-bg` | ≈ 18:1 | AAA |
| `--color-fg-secondary #bcd0e6` on bg | ≈ 13:1 | AAA |
| `--color-muted #7e94ad` on bg | ≈ 6.4:1 | AA (AAA large) |
| `--color-subtle #52677e` on bg | ≈ 3.4:1 | large / non-text only |
| `--color-accent #8cdcff` (cyan) on bg | ≈ 13:1 | AAA |
| `--color-accent-2 #ffd166` (gold) on bg | ≈ 13:1 | AAA |
| `--color-accent-3 #7ef7c8` (mint) on bg | ≈ 14:1 | AAA |
| `--color-danger #ff8b82` on bg | ≈ 9:1 | AAA |

Primary buttons place the dark canvas colour (`--color-bg`) as text on the cyan fill —
≈ 13:1, comfortable. In **ink/print** mode the accent becomes `#0a6db3` (≈ 5.6:1 on
white, AA). Never put accent-coloured text on an accent-soft background without
re-checking.

The system also responds to OS-level user preferences (the default cinematic look is never
weakened — these only activate when the user asks):

- **`prefers-reduced-motion`** — all transitions/animations collapse (handled globally in the reset).
- **`prefers-contrast: more`** — the faint cyan hairlines firm up and `--color-subtle` lifts to clear AA.
- **`prefers-reduced-transparency`** — the frosted HUD panels, floating header and overlay go opaque (no `backdrop-filter`).
- **`forced-colors: active`** (Windows High Contrast) — glows/gradients are dropped and every surface/control gets a real system-coloured border + outline. The cinematic look is **intentionally** flattened: the user has asked the OS to own colour, and legibility wins.

---

## Per-project adoption

The whole family now shares one skin, so adoption is mostly: load the fonts, link the
CSS, set the cyan/gold/mint accents via the tokens, and swap bespoke values for tokens.
Sub-project visual changes belong in **that project’s own repo** (each has its own
`CLAUDE.md`); this aggregator only orchestrates builds and pins which commit publishes.
After aligning a sub-project, bump its submodule pointer here to deploy.

| Project | Backdrop | Notes |
| --- | --- | --- |
| **résumé doc** (`projects/resume`, `master`) | on | The seed — already this exact palette. Promote its inline vars to the shared tokens; keep its `@media print` ink mode (now standardised here). Re-run `python3 build.py`. |
| **home** (`home/index.html`) | hero only | Re-base from GitHub-grey to the navy/cyan tokens; brand + hero h1 use Space Grotesk + `--glow-text`; cards/dropdown/footer map 1:1. |
| **blog** (`projects/blog`) | off (flat) | Adopt tokens; keep 1.075rem/1.8 prose. Cyan links, ▸ bullets optional. Skip the grid backdrop behind articles. |
| **résumé game** (Vite branch) | on | Already cockpit-native — formalise on `--hud-panel`/`--hud-line`/`--glow-*`. Ensure `prefers-reduced-motion` everywhere. |
| **Avarta** (`Avarta/web`) | on | Titlebar → `.site-header--float`; sliders → Slider (cyan `accent-color`); palette → color wells; status → Badge. |
| **Vishwakarma** (`vishwakarma/web`) | on | Route all panel chrome through `.hud-panel`; align error red to `--color-danger`. Adopt now so it’s consistent when it ships (post-R2). |

### Optional: publish the style guide

To serve the guide at `/design-system/`, add `cp -r design-system dist/design-system`
to `scripts/build.sh`. It then doubles as a visual regression surface — eyeball every
component after a token change.
