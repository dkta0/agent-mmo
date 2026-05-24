# Pretext Manuscript Verse — Station 04 Redesign

**Date:** 2026-05-24
**Surface:** `lib/agent_mmo_web/controllers/page_html/home.html.heex`, station `#runes` (Station 04)
**Library:** [pretext](https://github.com/chenglou/pretext) — variable-width text measurement/layout, DOM/Canvas/SVG render
**Status:** Design approved (Sections 1–3), pending user review of this written spec

---

## Goal

Replace the current single-quote verse card at station 04 with a real illuminated-manuscript page: an ASCII drop-cap illumination on the left, body inscription prose wrapping tightly around its right edge, optional chronicler's gloss in the right margin. Pretext does the variable-per-line-width layout that this requires.

Net effect: the verse station goes from "a card with a quote" to "a page you've just turned in someone's codex." The rest of the page is untouched.

## Why pretext

Pretext's single load-bearing capability for this design is `layoutNextLineRange(maxWidth)` returning wrapped lines under a per-line variable max-width — i.e. text that flows around obstacles. CSS `shape-outside` can approximate this for floats but breaks down for pixel-tight ASCII shapes and doesn't survive the kind of text-shadow/glow styling this page uses. Pretext also avoids DOM reflow on measurement, so resize/font-ready recomputes are cheap.

## In scope

- Station 04 (`#runes`) only.
- Pretext loaded via ESM CDN (`esm.sh/pretext` preferred, `unpkg.com/pretext?module` fallback). No build-pipeline changes.
- DOM render target (lines emitted as absolutely-positioned children). Preserves existing `.torch` span styling, glow, italic — pretext does not own paint.
- ASCII illumination block (~10 lines tall) as drop-cap, left-aligned.
- Body inscription prose (4–6 lines, Cormorant italic) wrapping the illumination's right edge for as long as it occupies vertical space; full-width for lines below.
- Existing attribution row (`✦ INSCRIBED ABOVE THE TAVERN DOOR ✦`) preserved at the page's foot.
- Optional thin marginalia gloss in mono, right margin — a one-word/short-phrase footnote on a key term. Can ship without it; it's atmospheric extra credit.
- Cursor-proximity glow intensification on the illumination only. Implemented via a single CSS custom property (`--torch-distance`) updated in the existing pointermove handler; CSS keys glow off the property.
- Recompute layout on three triggers: initial mount, `document.fonts.ready`, debounced window resize (200ms).
- Responsive: below 880px, drop-cap collapses inline at start of paragraph and marginalia stacks beneath; pretext still runs with effective obstacle width 0.

## Out of scope (explicit)

- All other stations (Threshold, Doorway, Wager, Flame, Invitation).
- Canvas or SVG render targets.
- Full cursor-reactive prose reflow (torchlight reading window — kept as v2 hook, see below).
- New pages, routes, or controllers.
- esbuild / asset pipeline / `priv/static/assets/` additions — *unless* pretext is not available on esm.sh at implementation time. In that case vendoring a single `pretext.js` under `priv/static/assets/` and extending `AgentMmoWeb.static_paths` is in scope as a contingency. No esbuild changes either way.
- Per-frame reflow. No reflow on scroll, no reflow on mouse-move.
- New copy for any other section. New marginalia glyphs beyond what's already on the page.

## Architecture

### Markup contract (server-rendered HEEx)

```html
<div class="manuscript-page" data-pretext-mount>
  <pre class="manuscript-illumination" aria-hidden="true">
    [ASCII torch + flame, ~10 lines, styled with existing .flame / .ember-glow / .handle / .ground spans ]
  </pre>
  <p class="manuscript-body">
    [4–6 lines of inscription prose with inline <span class="torch">…</span> accents]
  </p>
  <aside class="manuscript-gloss">
    [optional: one short chronicler's note]
  </aside>
  <div class="attrib">
    <span class="star">✦</span>
    <span>INSCRIBED ABOVE THE TAVERN DOOR</span>
    <span class="star">✦</span>
  </div>
</div>
```

The `<p class="manuscript-body">` is the authoritative source-of-truth content. Pretext reads its text + inline span structure, lays it into positioned line elements, and toggles the original `<p>` to `visibility: hidden` (kept in DOM for accessibility). Search engines, screen readers, and JS-off users see the prose as a normal paragraph.

### Pretext layout algorithm

Per line N (top-down):

```
y = N * lineHeight
if y + lineHeight < illuminationHeight:
    maxWidth = columnWidth - illuminationWidth - gutter
    startX  = illuminationWidth + gutter
else:
    maxWidth = columnWidth
    startX  = 0
```

Where:
- `columnWidth` = computed inner width of `.manuscript-page` (read once from `getBoundingClientRect`)
- `illuminationWidth/Height` = `.manuscript-illumination`'s bounding box (read once after fonts ready)
- `gutter` = a 24px breathing margin between illumination and body
- `lineHeight` = derived from Cormorant Garamond computed metrics via pretext's `measureLineStats`

Pretext API surface used: `prepareWithSegments()`, `layoutNextLineRange(maxWidth)`, `materializeLineRange()`. No rich-inline helpers needed — inline spans are preserved via DOM render.

### CSS-side responsibilities

- `.manuscript-page`: relative-positioned, holds illumination + body + gloss in a single coordinate space.
- `.manuscript-illumination`: absolutely positioned top-left, fixed pre-known width/height (set via JS once after measurement). Mono, `--torch` color, existing flame-flicker keyframes apply.
- `.manuscript-body`: visibility-hidden once pretext mounts; pretext-laid lines are siblings positioned absolutely with class `.manuscript-line`.
- `.manuscript-line`: absolutely positioned, inherits Cormorant italic from `.manuscript-body`. Inline `.torch` spans render with their glow/text-shadow.
- `.manuscript-gloss`: absolutely positioned right margin, mono small, `--parchment-mute`.
- `--torch-distance` custom property on `.manuscript-page` drives illumination glow strength (0 = far, 1 = on top). CSS keys `text-shadow`/`opacity` of `.manuscript-illumination .flame` off it.

### JS-side responsibilities (single inline IIFE in the existing `<script>` block)

1. Wait for `document.fonts.ready`.
2. Resolve pretext via dynamic `import('https://esm.sh/pretext')`.
3. Measure `.manuscript-illumination` bounds + `.manuscript-page` inner width.
4. Call `prepareWithSegments(bodyText, inlineSpans)`.
5. Walk lines via `layoutNextLineRange`, supplying per-line `maxWidth` per the algorithm above.
6. Materialize each line as a positioned DOM element with `class="manuscript-line"`, append to `.manuscript-page`, hide original `<p>`.
7. Add resize listener (debounced 200ms) that re-runs steps 3–6.
8. On the existing pointermove handler, compute distance from cursor to illumination center, set `--torch-distance` (clamped 0..1).
9. If pretext import fails or `prepareWithSegments` throws: catch silently, leave the original `<p>` visible — the fallback layout is the design's safety net.

### Failure modes

| Failure | Effect | Mitigation |
|---|---|---|
| Pretext CDN unreachable | Original `<p>` stays visible. Plain block wrap under illumination. | No mitigation needed; fallback is intentional. |
| Pretext throws on measure | Same as above. | Same as above. |
| JS disabled entirely | Original `<p>` plus illumination render. No glow reactivity. | Same fallback. |
| Fonts slow to load | Brief fallback flash before pretext recomputes. | Acceptable; `document.fonts.ready` gates the first run. |
| `--torch-distance` not supported | No glow reactivity; static glow keyframes still play. | Acceptable; design degrades gracefully. |
| Sub-880px viewport | Illumination collapses inline; pretext effective obstacle is 0. | Media query handles layout; pretext path runs the same code. |

### Accessibility

- Original `<p class="manuscript-body">` stays in the DOM with `visibility: hidden` (NOT `display: none`) so screen readers and Google read the prose normally.
- Illumination has `aria-hidden="true"` — decorative ASCII.
- Marginalia gloss is read in document order after the body; that's the right order for context.

## Copy

Body inscription draft (4 lines, the actual text to be approved separately during implementation):

> *We did not ask if it could speak in our tongue.<br />
> We did not ask if it could solve our riddles.<br />
> We asked if it would still be standing<br />
> when the door swung shut behind it.*

The `survive` semantic carries over from the prior single-line verse; the expanded form earns the manuscript treatment by saying more without saying anything about the product.

Optional gloss (right margin, mono small):

> *— attrib. unknown<br />
> first scrawled<br />
> in the cellar*

Both copy blocks above are working drafts. Copy review is the first step of the implementation plan — implementation does not start before the user signs off on the final body inscription and (if kept) gloss text. Spec-level intent is fixed; the wording can move.

## v2 hooks (deliberately left in place)

- **Multi-station pretext use.** Pretext is loaded once for the page. Adding it to another station is two lines (import the same module, call `prepareWithSegments` on that station's body).
- **Torchlight reading window (Option C).** The `--torch-distance` plumbing already exists. To extend to a reading-window: per-line `maxWidth` becomes a function of cursor position (chord-width through a circle centered on the cursor), recomputed on `pointermove` at a throttled cadence (~30fps). The existing reflow path supports it; only the obstacle-width function changes.
- **Codex sub-page.** Manuscript CSS classes are namespaced (`.manuscript-*`) so a hypothetical `/chronicle` or `/codex` route can reuse the same styling without collision.

## Risks / open questions

- **Pretext CDN availability on esm.sh.** Needs verification at implementation time that the package is published and ESM-importable. Vendoring fallback is a single file under `priv/static/assets/pretext.js` + adding `assets` to `AgentMmoWeb.static_paths`.
- **Pretext API drift.** The README at the time of writing lists `prepareWithSegments` / `layoutNextLineRange` / `materializeLineRange`. If the published version's API differs, the algorithm above stays — only function names move.
- **ASCII illumination width consistency.** The illumination is rendered as a `<pre>` block in monospace; its computed width depends on the user's monospace font fallback. Implementation should measure post-mount rather than assume.

## Acceptance criteria

1. Station 04 renders a manuscript page with an ASCII illumination top-left and 4–6 lines of inscription prose wrapping its right edge.
2. The first ~3 lines of body prose have a visibly shorter line length than the lines below them.
3. Resizing the window re-flows the prose to fit the new column width (no clipped or overlapping text).
4. Disabling JS still shows a readable verse — illumination above, prose below in standard block flow.
5. `.torch` accent spans inside the body retain their glow/text-shadow.
6. Cursor proximity to the illumination visibly intensifies its glow.
7. No other station's appearance or behavior changes.
8. No new HTTP routes, no new assets in `priv/static/`, no esbuild config changes.
