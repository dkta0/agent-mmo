# Torchlight Reading Window — Station 04 v2

**Date:** 2026-05-24
**Surface:** `lib/agent_mmo_web/controllers/page_html/home.html.heex`, station `#runes` (Station 04)
**Library:** [`@chenglou/pretext@0.0.7`](https://github.com/chenglou/pretext) (already loaded for Option A)
**Predecessor:** [`docs/superpowers/specs/2026-05-24-pretext-manuscript-verse-design.md`](./2026-05-24-pretext-manuscript-verse-design.md) (Option A — already shipped)
**Status:** Design approved (Sections 1–2), pending user review of this written spec

---

## Goal

Replace Option A's static wrap-around-illumination on station 04 with a cursor-following torchlight reading window. The body inscription renders at low opacity (≈0.18) by default. A circular region centered on the cursor renders the prose at full opacity AND reflows the lines so that each line's `maxWidth` is the chord-width through the cursor's circle at that line's Y. Lines outside the cursor's vertical reach stay at full column width and dim opacity. The cursor is the reading lens; the page becomes "you can only read what your light reaches."

The illumination (ASCII torch) stays drawn at top-left as a decorative anchor but no longer acts as a wrap obstacle and no longer has cursor-proximity glow. The cursor itself is now the focal element.

## Why pretext (still)

Pretext's `prepareWithSegments` + `layoutNextLineRange(prepared, cursor, maxWidth)` is what makes per-rAF reflow tractable: `prepareWithSegments` runs once (canvas-measured), then per-frame `layoutNextLineRange` calls are cheap line-break math against the cached widths. The cost is bounded by the number of visible lines (≤ ~20) at 60fps. Without pretext's prepare/layout separation, per-frame text wrap would require canvas remeasurement each frame.

## In scope

- Station 04 (`#runes`) only.
- Per-rAF cursor-driven reflow of the body inscription. Cursor circle radius `R = 160px` (tunable constant — set once, no UI to change).
- Two-mode line layout per frame:
  - **OUT mode** (line's vertical midpoint is more than `R` from cursor's Y, or cursor is outside the manuscript-page): line at full column width, opacity 0.18, statically positioned at the static `y`.
  - **IN mode** (line's midpoint is within `R` of cursor's Y AND cursor is inside the manuscript-page): line's `maxWidth = max(chord, MIN_WIDTH=40)` where `chord = 2 * sqrt(R² - dy²)`, `startX = cursorXLocal - maxWidth/2`, opacity smoothly ramps from `1.0` at the cursor's Y to `0.18` at the disk's vertical rim.
- Pool of pre-created `.manuscript-line` divs (up to `N_LINES_MAX = 20`); per-frame reuse — no `appendChild` / `remove` per rAF.
- Cursor coords transformed to local manuscript-page space using the existing `rootRect` cached refresh path (scroll + resize listeners already in place from Option A).
- Removal of Option A's wrap-around-illumination collision logic. The illumination becomes a pure decorative element with no layout influence.
- Removal of Option A's `--torch-distance` cursor-proximity glow on the illumination (T7 in Option A's plan). The cursor IS the focal element now.
- Activation gate: rAF loop runs only when the manuscript-page is in the viewport (existing IntersectionObserver pattern from station-index plumbing).
- `prefers-reduced-motion: reduce` short-circuit: prose at full opacity 1.0, statically laid out at full column width, no rAF reflow, no opacity ramp.
- Mobile (≤880px): no hover cursor, so reading window disabled — prose at full opacity 1.0, statically laid out at full column width (same as reduced-motion behavior). Illumination's `position: static` mobile collapse from Option A stays.
- Body copy: unchanged from Option A's locked inscription.
- Smoke test extension: `test/agent_mmo_web/controllers/page_controller_test.exs` already asserts the manuscript markup. The reading window is purely client-side, so server-side assertions don't need to change.

## Out of scope (explicit)

- Any other station.
- Changes to body inscription copy.
- Changes to the illumination ASCII art.
- Marginalia gloss (still dropped per Option A's gate decision).
- Per-character glow effects, halos around the cursor circle's edge (the disk is defined by the chord-reflow + opacity ramp; no separate glow element).
- Touch-device reflow (no cursor on touch).
- Multi-station pretext reading windows.
- Animation transitions between OUT and IN modes (the opacity ramp inside the disk handles the visual smoothness; lines crossing the disk boundary just snap between modes — acceptable at 60fps).

## Architecture

### State (closure inside `manuscriptVerse` IIFE)

```javascript
let prepared       = null;                 // pretext result, computed once
let columnWidth    = 0;                    // cached on resize
let lineHeightPx   = 0;                    // cached on resize
let padLeft        = 0;
let padTop         = 0;
let rootRect       = null;                 // cached on resize/scroll
let cursorXLocal   = null;                 // null = no cursor (initial / off-page)
let cursorYLocal   = null;
let lineEls        = [];                   // pool of N_LINES_MAX divs
let reducedMotion  = false;                // matchMedia
let mobile         = false;                // matchMedia(max-width: 880px)
let rafActive      = false;                // currently in rAF loop?
let inViewport     = false;                // manuscript-page intersecting viewport?
```

### Constants

```javascript
const R              = 160;                // cursor circle radius, px
const MIN_WIDTH      = 40;                 // floor for chord-width
const N_LINES_MAX    = 20;
const BASE_OPACITY   = 0.18;
```

### Initialization (runs once after fonts.ready)

1. `prepared = pretext.prepareWithSegments(body.textContent.replace(/\s+/g, ' ').trim(), buildFontString(body))`
2. Read `columnWidth, lineHeightPx, padLeft, padTop, rootRect` from current layout
3. Pre-create `N_LINES_MAX` `.manuscript-line` divs as children of `root`, all `display: none` initially
4. Hide the source `<p class="manuscript-body">` (`root.classList.add('pretext-active')` — already styled in CSS to set `visibility: hidden`)
5. Attach matchMedia listeners for `(prefers-reduced-motion: reduce)` and `(max-width: 880px)`
6. Attach IntersectionObserver to `root` with `threshold: 0` — updates `inViewport`
7. Attach pointermove listener (already there from existing IIFE) — updates `cursorXLocal/Y` (local coords) when cursor is inside `rootRect`, else nulls them
8. Start rAF loop conditionally

### Per-frame layout (`layoutFrame`)

Called inside the existing global rAF tick (the one that already drives the cursor + torchlight halo) so we don't run two rAF loops in parallel. Cost-bound: ~10 lines × pretext layout call ≈ 1ms per frame on commodity hardware.

```javascript
function layoutFrame() {
  if (!prepared) return;

  const useStatic = reducedMotion || mobile || !inViewport
                 || cursorXLocal == null || cursorYLocal == null;

  let cursor = { segmentIndex: 0, graphemeIndex: 0 };
  let y = 0;
  let lineIdx = 0;

  while (lineIdx < N_LINES_MAX) {
    const lineMidY = y + lineHeightPx / 2;
    let mode, maxWidth, startX, opacity;

    if (useStatic) {
      // Fallback modes: prose readable plainly (reduced-motion, mobile, off-page).
      mode = 'OUT';
      maxWidth = columnWidth;
      startX = 0;
      opacity = 1.0;
    } else {
      const dy = Math.abs(lineMidY - cursorYLocal);
      if (dy > R) {
        mode = 'OUT';
        maxWidth = columnWidth;
        startX = 0;
        opacity = BASE_OPACITY;
      } else {
        const chord = 2 * Math.sqrt(R*R - dy*dy);
        maxWidth = Math.max(chord, MIN_WIDTH);
        startX = cursorXLocal - maxWidth/2;
        // Clamp startX so the line doesn't extend past the column edges
        if (startX < 0) startX = 0;
        if (startX + maxWidth > columnWidth) startX = columnWidth - maxWidth;
        // Smooth opacity ramp from full (at center) to BASE_OPACITY (at rim)
        opacity = BASE_OPACITY + (1.0 - BASE_OPACITY) * (1.0 - dy / R);
      }
    }

    const range = pretext.layoutNextLineRange(prepared, cursor, maxWidth);
    if (range === null) {
      // All prose laid out — hide remaining pool slots
      for (let k = lineIdx; k < N_LINES_MAX; k++) {
        if (lineEls[k]) lineEls[k].style.display = 'none';
      }
      return;
    }

    const line = pretext.materializeLineRange(prepared, range);
    const el = lineEls[lineIdx];
    el.style.display = 'block';
    el.style.left    = (padLeft + startX) + 'px';
    el.style.top     = (padTop + y) + 'px';
    el.style.maxWidth = maxWidth + 'px';
    el.style.opacity = opacity.toFixed(3);

    // Accent post-process (carried over from Option A)
    const accentRe = /\bsurvive\b/i;
    if (accentRe.test(line.text)) {
      el.innerHTML = line.text.replace(accentRe, m => `<span class="torch">${m}</span>`);
    } else {
      el.textContent = line.text;
    }

    cursor = range.end;
    y += lineHeightPx;
    lineIdx++;
  }
  // If we ran out of slots, the remaining prose is dropped. N_LINES_MAX = 20
  // should comfortably accommodate the locked 4-sentence inscription even at
  // narrow chord widths.
}
```

### rAF integration

Hook into the existing `tick()` rAF loop (defined near the top of the `<script>` block, already running). Add `layoutFrame()` AFTER the cursor + torchlight transforms. The same 60fps cap covers both. Quantization: only call `layoutFrame()` if cursor moved >2px since last frame OR mode is transitioning (e.g., cursor just entered/left the manuscript-page). Without quantization, we'd run pretext layout even when the cursor is stationary — wasted work.

### CSS additions (new, on top of Option A's manuscript CSS)

```css
.manuscript-line {
  transition: opacity 80ms linear;  /* smooth IN↔OUT transitions when crossing the disk edge */
}

@media (prefers-reduced-motion: reduce) {
  .manuscript-line {
    transition: none;
    opacity: 1 !important;
  }
}
```

The transition is intentionally short — long enough to smooth single-frame mode flips, short enough not to lag the live reflow.

### CSS removals from Option A

The cursor-proximity glow rules on `.manuscript-illumination .flame` and `.manuscript-illumination .flame-2` revert from their Option-A T7 form (with `--torch-distance` mixed into text-shadow `calc()`) back to plain static text-shadows. The `--torch-distance` custom property usage is removed entirely.

### JS removals from Option A

- The pointermove handler block stops computing torch-distance.
- The `tick()` no longer calls `maybeUpdateTorchDistance()`.
- The `refreshManuscriptRefs` function gets simplified (no longer needs to track `illCenter` — the cursor's own position drives everything now).
- The `lastTorchDistance` variable disappears.
- The midpoint-collide predicate inside `layoutBody` is dead code — `layoutBody` itself is replaced by `layoutFrame` + initialization steps.
- The diagnostic console.log added in commit `39deef5` gets removed.

### Failure modes

| Failure | Effect | Mitigation |
|---|---|---|
| Pretext CDN unreachable | Original `<p>` stays visible at full opacity; no reading window. | Existing try/catch around `import()`; intentional. |
| Pretext throws on prepare | Same as above. | Same try/catch. |
| Fonts slow to load | Brief fallback flash before pretext initializes. | `await document.fonts.ready` gate (carried over from Option A). |
| Cursor never moves over the page | Prose stays at `BASE_OPACITY` everywhere. User sees a dim verse without realizing the reading mechanic. | Acceptable — the cursor-following torchlight halo from the atmospheric design draws the eye toward cursor movement. Discoverability is sufficient. |
| `prefers-reduced-motion: reduce` | Prose at full opacity, static, no rAF reflow. | Built-in. |
| Viewport ≤ 880px | Same as reduced-motion. | Built-in. |
| Cursor moves at >120 fps (high-refresh display) | rAF cap still 60fps for the layout work; cursor smoothing remains crisp because that's a transform-only path. | Acceptable. |

### Accessibility

- The source `<p class="manuscript-body">` stays in the DOM with `visibility: hidden` (carried over from Option A) — screen readers and search engines still get the prose in natural order.
- `prefers-reduced-motion: reduce` short-circuits the per-frame reflow.
- Mobile / touch: full-opacity static fallback ensures the prose is readable without a cursor.
- The reading mechanic is a progressive enhancement — never gates access to the content.

## Performance budget

- `pretext.layoutNextLineRange` per visible line per rAF tick: empirical ~0.05ms each from pretext's own benchmark guidance. At 20 lines per frame × 60fps = 60ms/sec of pretext work = ~6% of a single core's wall-clock at typical CPUs. Headroom acceptable.
- DOM updates per frame: ~6 style writes × 20 elements = 120 property writes. Browsers batch these into a single style invalidation pass per rAF — cheap.
- Quantization (≥2px cursor movement) cuts this in half during typical drift / hover.
- No layout thrashing: we never READ layout properties inside the rAF — only write `style.left/top/maxWidth/opacity/display/textContent/innerHTML`.

## Risks / open questions

- **MIN_WIDTH = 40px** picked as a guess. At the disk's vertical rim, `chord` approaches zero — and pretext given `maxWidth < ~3 chars` returns single-character lines, like we saw earlier this session. 40px gives pretext enough room to fit 2–3 short words at worst. Acceptable jitter at the rim; implementor can tune up/down.
- **R = 160px** picked as a guess. The body's line-height is ~55px at desktop font size, so a 320px diameter covers ~5 lines vertically. Tunable.
- **N_LINES_MAX = 20** is conservative. The locked 4-sentence body at full column width fits in 4–5 lines; at narrow chord widths near the disk rim, line count can multiply. 20 is the soft cap — anything past that gets dropped. Spec-level guarantee: locked inscription will not overflow 20 lines at any reasonable cursor position.
- **Opacity transition timing (80ms)** trades smoothness against feeling laggy. Sub-100ms is below human notice threshold but smooths single-frame mode flips when the cursor's vertical rim crosses a line boundary. Tunable.
- **Cursor coordinates while scrolling**: pointermove updates `clientX/Y`; converting to local manuscript-page coords requires `rootRect`. On scroll, `rootRect` changes but pointermove may not fire if the cursor is stationary. We refresh `rootRect` on the scroll listener (already there from Option A); the rAF loop reads the cached value. There may be a one-frame lag between scroll end and rAF re-render — acceptable.

## Acceptance criteria

1. Visiting `/#runes` and resting the cursor over the manuscript page reveals a circle of full-opacity prose centered on the cursor; the rest of the prose is at low opacity (~0.18) statically laid out at full column width.
2. Moving the cursor smoothly reflows the lines inside the disk — line widths change as the cursor moves, with text always centered on the cursor's X.
3. Moving the cursor OFF the manuscript page restores all lines to the dim static (full column) layout.
4. The illumination ASCII art still renders at its top-left position but no longer affects the body layout (lines flow underneath it, dimmed).
5. The illumination's flame no longer brightens when the cursor approaches it (T7's proximity glow is gone).
6. The accent word `survive` still glows amber and pulses inside whichever materialized line contains it.
7. Resize reflows the static layout; reading window adapts seamlessly afterward.
8. With `prefers-reduced-motion: reduce` set: prose at full opacity, static, no per-frame reflow.
9. At viewport ≤ 880px: prose at full opacity, static, no per-frame reflow.
10. With JS disabled: original `<p>` visible at full opacity (existing Option A fallback).
11. No other station's appearance or behavior changes.
12. No new HTTP routes, no new assets in `priv/static/`, no esbuild config changes.

## What this spec deliberately retires from Option A

- T7's cursor-proximity glow on the illumination — replaced by the cursor reading window's own opacity ramp.
- The wrap-around-illumination collision logic — illumination is decorative only.
- The `--torch-distance` CSS custom property and its `calc()` integration in the flame's text-shadow.
- The midpoint-collide predicate (commit `420e038`) — dead with the wrap logic.
- The diagnostic `console.log` in `layoutBody` (commit `39deef5`) — measurements served their purpose.

The remainder of Option A — manuscript markup, illumination drop-cap, base CSS, the smoke test, the pretext bootstrap and prepare path, the resize + fonts-ready triggers — all stays.
