# Torchlight Reading Window Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace Option A's static wrap-around-illumination on station 04 with a cursor-driven torchlight reading window — body inscription at base 0.18 opacity, lines under the cursor reflow per rAF to fit chord-widths through a 160px radius circle centered on the cursor, full opacity inside the disk fading to base at the rim.

**Architecture:** Refactor the existing `manuscriptVerse` IIFE in the single HEEx file to maintain a pool of `.manuscript-line` divs and a `prepared` pretext state computed once at fonts-ready. A new `layoutFrame()` runs inside the existing global `tick()` rAF loop, gated by a 2px cursor-movement quantizer. Per-line logic branches between OUT (static, dim, full column) and IN (chord-width, bright, centered on cursor X) modes based on the line's vertical distance from the cursor. Falls back to static full-opacity prose under reduced-motion, mobile, or off-viewport conditions.

**Tech Stack:** Phoenix 1.7 HEEx, vanilla JS (existing inline pattern), `@chenglou/pretext@0.0.7` (already loaded), no esbuild/asset changes.

**Spec:** `docs/superpowers/specs/2026-05-24-torchlight-reading-window-design.md`

**Predecessor:** Option A (manuscript verse) — already shipped. Last relevant commits on `main`:
- `420e038` — midpoint collide predicate (will be retired by this plan)
- `39deef5` — cursor lag + diagnostic console.log (will be retired by this plan)
- `5eddb88` — T7 cursor-proximity glow (will be retired by this plan)
- `40ea6a3` — fonts-ready + resize reflow (kept; extended)
- `0b8461d` — wrap-around-illumination (will be retired by this plan)
- `36cc144` — pretext bootstrap (kept; refactored)
- `ccbdc03` — manuscript markup + CSS (kept; CSS extended)

---

## File map

- **Modify:** `lib/agent_mmo_web/controllers/page_html/home.html.heex` — all CSS, all JS (still inline; no extraction).
- **No new files.** No test additions — the existing controller smoke test (`test/agent_mmo_web/controllers/page_controller_test.exs`) keeps asserting the markup is server-rendered; the rAF reading window is client-side and tested via visual acceptance.

---

## Task 1: Retire Option A's wrap/glow plumbing

**Files:**
- Modify: `lib/agent_mmo_web/controllers/page_html/home.html.heex`

This task is destructive — it removes code that's currently working. The goal: collapse to the simplest possible static state (prose at full opacity, full column width, below the illumination, no cursor-reactive glow, no wrap-around-illumination collision) before building the reading window on top.

After this task, the manuscript verse station will look "worse" than Option A — a plain block of italic prose below the torch. That's intentional. T3+ rebuild the per-frame layout machinery, and T5+ add the reading-window magic.

- [ ] **Step 1: Remove `--torch-distance` from the illumination's flame text-shadow**

In `lib/agent_mmo_web/controllers/page_html/home.html.heex`, find `.manuscript-illumination .flame` (around line 562). Replace its body with:

```css
  .manuscript-illumination .flame {
    color: var(--torch-bright);
    text-shadow:
      0 0 18px rgba(243,194,102, 0.7),
      0 0 36px rgba(224,166,74, 0.55);
    animation: flameFlicker 1.8s ease-in-out infinite;
    display: inline-block;
  }
```

And `.manuscript-illumination .flame-2`:

```css
  .manuscript-illumination .flame-2 {
    color: var(--ember);
    text-shadow:
      0 0 16px rgba(255,156,74, 0.7),
      0 0 30px rgba(224,166,74, 0.4);
    animation: flameFlicker 2.1s ease-in-out infinite reverse;
    display: inline-block;
  }
```

- [ ] **Step 2: Remove the `--torch-distance` custom property declaration**

Find `.manuscript-page` CSS rule (around line 540). Remove the line `--torch-distance: 0;` — the rule body becomes:

```css
  .manuscript-page {
    display: block;
    text-align: left;
    position: relative;
  }
```

- [ ] **Step 3: Retire `maybeUpdateTorchDistance`, `lastTorchDistance`, and `illCenter`**

Find the cursor-tracking block in the inline `<script>` (search for `refreshManuscriptRefs`). Replace the entire block — from the comment `// Cache the manuscript root + illumination center.` through the end of `maybeUpdateTorchDistance` function definition — with:

```javascript
  // Cache the manuscript root element. Reading window relies on this for
  // per-frame cursor-coordinate-to-local-space transforms.
  let manuscriptRootEl = null;
  function refreshManuscriptRefs() {
    manuscriptRootEl = document.querySelector('.manuscript-page[data-pretext-mount]');
  }
  refreshManuscriptRefs();
  window.addEventListener('scroll', refreshManuscriptRefs, { passive: true });
  window.addEventListener('resize', refreshManuscriptRefs);

  window.addEventListener('pointermove', (e) => {
    mouseX = e.clientX;
    mouseY = e.clientY;
  });
```

- [ ] **Step 4: Remove the `maybeUpdateTorchDistance()` call from `tick()`**

Find the `tick()` function. Remove the line `maybeUpdateTorchDistance();` (the rAF loop should now just do its torchlight + cursor transforms, no torch-distance work).

- [ ] **Step 5: Strip illumination collision logic, clamps, and diagnostic log from `layoutBody`**

Find the `manuscriptVerse` IIFE. Inside, find `function layoutBody()` and replace the entire function body with this simplified version:

```javascript
    function layoutBody() {
      root.querySelectorAll('.manuscript-line').forEach(el => el.remove());

      const rootRect = root.getBoundingClientRect();
      const cs = getComputedStyle(root);
      const padLeft = parseFloat(cs.paddingLeft) || 0;
      const padRight = parseFloat(cs.paddingRight) || 0;
      const padTop = parseFloat(cs.paddingTop) || 0;
      const columnWidth = rootRect.width - padLeft - padRight;

      const bodyCS = getComputedStyle(body);
      const lineHeightPx = parseFloat(bodyCS.lineHeight);
      const font = buildFontString(body);

      const text = body.textContent.replace(/\s+/g, ' ').trim();
      const prepared = pretext.prepareWithSegments(text, font);

      let cursor = { segmentIndex: 0, graphemeIndex: 0 };
      let y = 0;

      while (true) {
        const range = pretext.layoutNextLineRange(prepared, cursor, columnWidth);
        if (range === null) break;

        const line = pretext.materializeLineRange(prepared, range);
        const el = document.createElement('div');
        el.className = 'manuscript-line';
        el.style.left = padLeft + 'px';
        el.style.top  = (padTop + y) + 'px';
        el.style.maxWidth = columnWidth + 'px';

        const accentRe = /\bsurvive\b/i;
        if (accentRe.test(line.text)) {
          el.innerHTML = line.text.replace(accentRe, m => `<span class="torch">${m}</span>`);
        } else {
          el.textContent = line.text;
        }

        root.appendChild(el);

        cursor = range.end;
        y += lineHeightPx;
      }

      root.classList.add('pretext-active');
    }
```

Removed: illumination's `getBoundingClientRect`, `illLeft`/`illTop`/`illW`/`illH` variables, the `Math.min`/`Math.max` clamps on `illW` and `maxWidth`, the `window.__manuscriptLogged` console.log block, the midpoint-collide predicate, the IN/OUT mode branching. Result: every line lays out at `columnWidth` starting at `padLeft`. Prose appears as a plain block below the illumination.

- [ ] **Step 6: Run the controller smoke test**

```bash
docker compose exec -T -e MIX_ENV=test app mix test test/agent_mmo_web/controllers/page_controller_test.exs
```

Expected: 2 tests, 0 failures. The server-rendered markup is unchanged; only client-side JS and CSS shifted.

- [ ] **Step 7: Verify the rendered HTML still contains the manuscript markup**

```bash
curl -fsS http://127.0.0.1:4100/ | grep -cE 'manuscript-page|manuscript-illumination|manuscript-body|INSCRIBED ABOVE THE TAVERN DOOR'
```

Expected: at least 4 matches.

- [ ] **Step 8: Visual sanity check (optional)**

Reload `http://localhost:4100/#runes`. Expected: the manuscript page renders, the illumination is at top-left, and the body inscription appears as a plain italic paragraph BELOW the illumination (the wrap-around-torch effect from Option A is gone). The cursor-proximity glow on the flame is gone — the flame just flickers with its static text-shadow. This is the intended "demolished" state.

- [ ] **Step 9: Commit**

```bash
git add lib/agent_mmo_web/controllers/page_html/home.html.heex
git commit -m "$(cat <<'EOF'
refactor(landing): retire option-A wrap/glow plumbing

Strips Option A's cursor-proximity glow on the manuscript illumination
(--torch-distance custom property + calc()-driven text-shadows on flame
spans), the wrap-around-illumination collision logic in layoutBody, the
midpoint-collide predicate, the safety clamps on illW/maxWidth, the
diagnostic console.log, the lastTorchDistance/illCenter cache, and the
maybeUpdateTorchDistance function. layoutBody now lays out body prose
at full column width as a plain block under the illumination — visual
regression from Option A is intentional. The torchlight reading window
spec (v2) rebuilds the per-frame layout machinery from this baseline.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 2: Add CSS for opacity transition + reduced-motion override

**Files:**
- Modify: `lib/agent_mmo_web/controllers/page_html/home.html.heex`

The reading window will rapidly transition lines between OUT mode (opacity 0.18) and IN mode (opacity up to 1.0) as the cursor moves. A short 80ms `transition: opacity` softens single-frame mode flips. `prefers-reduced-motion: reduce` overrides this to force full opacity.

- [ ] **Step 1: Add transition to `.manuscript-line` and reduced-motion override**

Find the `.manuscript-line` rule in the manuscript CSS block (search for `.manuscript-line {`). It currently looks like:

```css
  .manuscript-line {
    position: absolute;
    font-family: var(--serif);
    font-style: italic;
    font-weight: 400;
    font-size: clamp(22px, 3vw, 42px);
    line-height: 1.45;
    letter-spacing: 0.005em;
    color: var(--parchment);
    pointer-events: none;
    white-space: nowrap;
  }
```

Replace it with:

```css
  .manuscript-line {
    position: absolute;
    font-family: var(--serif);
    font-style: italic;
    font-weight: 400;
    font-size: clamp(22px, 3vw, 42px);
    line-height: 1.45;
    letter-spacing: 0.005em;
    color: var(--parchment);
    pointer-events: none;
    white-space: nowrap;
    opacity: 1;
    transition: opacity 80ms linear;
  }

  @media (prefers-reduced-motion: reduce) {
    .manuscript-line {
      transition: none;
      opacity: 1 !important;
    }
  }
```

The `opacity: 1` default keeps T1's static-rendered prose at full opacity (no surprise dimming after this CSS lands).

- [ ] **Step 2: Smoke test**

```bash
docker compose exec -T -e MIX_ENV=test app mix test test/agent_mmo_web/controllers/page_controller_test.exs
```

Expected: 2 tests, 0 failures.

- [ ] **Step 3: Confirm rules are in rendered HTML**

```bash
curl -fsS http://127.0.0.1:4100/ | grep -cE 'transition: opacity 80ms|prefers-reduced-motion: reduce'
```

Expected: at least 2 matches.

- [ ] **Step 4: Commit**

```bash
git add lib/agent_mmo_web/controllers/page_html/home.html.heex
git commit -m "$(cat <<'EOF'
feat(landing): add manuscript-line opacity transition + reduced-motion

Sets a default opacity:1 on .manuscript-line and an 80ms linear
transition on opacity so single-frame IN<->OUT mode flips during
cursor reading-window reflow render smoothly rather than snapping.
Reduced-motion media query forces opacity:1 and disables transitions.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 3: Refactor to layoutFrame with closure state + line pool

**Files:**
- Modify: `lib/agent_mmo_web/controllers/page_html/home.html.heex`

Lift state out of `layoutBody` into the IIFE's closure so it persists across rAF ticks, pre-create a pool of `.manuscript-line` divs (`N_LINES_MAX = 20`), and rename `layoutBody` → `layoutFrame`. `prepared` is computed once at fonts-ready (not per call). For now `layoutFrame` keeps the static-full-width path (no cursor logic yet) — same visual as T1's output, different architecture.

- [ ] **Step 1: Replace the manuscript-verse IIFE body**

Find the `(async function manuscriptVerse() { ... })();` IIFE in the inline `<script>`. Replace its ENTIRE body (everything between the opening `{` after `manuscriptVerse()` and the closing `})();`) with this:

```javascript
    const root = document.querySelector('.manuscript-page[data-pretext-mount]');
    if (!root) return;

    const illumination = root.querySelector('.manuscript-illumination');
    const body = root.querySelector('.manuscript-body');
    if (!illumination || !body) return;

    let pretext;
    try {
      pretext = await import('https://esm.sh/@chenglou/pretext@0.0.7');
    } catch (err) {
      return; // CDN unreachable — leave the fallback <p> visible
    }

    // ---- Constants ----
    const R              = 160;       // cursor circle radius, px
    const MIN_WIDTH      = 40;        // chord-width floor
    const N_LINES_MAX    = 20;        // pool size
    const BASE_OPACITY   = 0.18;
    const QUANTIZE_PX    = 2;         // skip layoutFrame if cursor moved <2px

    // ---- Closure state ----
    let prepared       = null;
    let columnWidth    = 0;
    let lineHeightPx   = 0;
    let padLeft        = 0;
    let padTop         = 0;
    let rootRect       = null;
    let cursorXLocal   = null;
    let cursorYLocal   = null;
    let lineEls        = [];
    let lastCursorX    = -9999;
    let lastCursorY    = -9999;
    let lastUseStatic  = null;

    function buildFontString(el) {
      const cs = getComputedStyle(el);
      return `${cs.fontStyle} ${cs.fontWeight} ${cs.fontSize} ${cs.fontFamily}`;
    }

    function init() {
      // Compute layout-dependent constants
      rootRect = root.getBoundingClientRect();
      const cs = getComputedStyle(root);
      padLeft = parseFloat(cs.paddingLeft) || 0;
      padTop  = parseFloat(cs.paddingTop)  || 0;
      const padRight = parseFloat(cs.paddingRight) || 0;
      columnWidth = rootRect.width - padLeft - padRight;

      const bodyCS = getComputedStyle(body);
      lineHeightPx = parseFloat(bodyCS.lineHeight);

      // Prepare pretext once with current font
      const text = body.textContent.replace(/\s+/g, ' ').trim();
      const font = buildFontString(body);
      prepared = pretext.prepareWithSegments(text, font);

      // Ensure line pool exists
      while (lineEls.length < N_LINES_MAX) {
        const el = document.createElement('div');
        el.className = 'manuscript-line';
        el.style.display = 'none';
        root.appendChild(el);
        lineEls.push(el);
      }

      root.classList.add('pretext-active');
    }

    function layoutFrame() {
      if (!prepared) return;

      // useStatic path: static full-column-width, full opacity. This is what
      // reduced-motion, mobile, off-viewport, and no-cursor users see — and
      // also what shows until T5 wires up the cursor-aware IN/OUT modes.
      const useStatic = true;

      let cur = { segmentIndex: 0, graphemeIndex: 0 };
      let y = 0;
      let lineIdx = 0;

      while (lineIdx < N_LINES_MAX) {
        const maxWidth = columnWidth;
        const startX   = 0;
        const opacity  = 1.0;

        const range = pretext.layoutNextLineRange(prepared, cur, maxWidth);
        if (range === null) {
          // Hide remaining pool slots
          for (let k = lineIdx; k < N_LINES_MAX; k++) {
            lineEls[k].style.display = 'none';
          }
          return;
        }

        const line = pretext.materializeLineRange(prepared, range);
        const el = lineEls[lineIdx];
        el.style.display  = 'block';
        el.style.left     = (padLeft + startX) + 'px';
        el.style.top      = (padTop + y) + 'px';
        el.style.maxWidth = maxWidth + 'px';
        el.style.opacity  = opacity.toFixed(3);

        const accentRe = /\bsurvive\b/i;
        if (accentRe.test(line.text)) {
          el.innerHTML = line.text.replace(accentRe, m => `<span class="torch">${m}</span>`);
        } else {
          el.textContent = line.text;
        }

        cur = range.end;
        y += lineHeightPx;
        lineIdx++;
      }
    }

    // Wait for fonts so canvas measurement uses the real metrics
    if (document.fonts && document.fonts.ready) {
      await document.fonts.ready;
    }

    init();
    layoutFrame();

    let resizeTimer = null;
    window.addEventListener('resize', () => {
      clearTimeout(resizeTimer);
      resizeTimer = setTimeout(() => {
        init();
        layoutFrame();
      }, 200);
    });
```

- [ ] **Step 2: Smoke test**

```bash
docker compose exec -T -e MIX_ENV=test app mix test test/agent_mmo_web/controllers/page_controller_test.exs
```

Expected: 2 tests, 0 failures.

- [ ] **Step 3: Verify rendered HTML contains the new code**

```bash
curl -fsS http://127.0.0.1:4100/ | grep -cE 'N_LINES_MAX|BASE_OPACITY|layoutFrame|init\(\)|lineEls\.push'
```

Expected: at least 5 matches.

- [ ] **Step 4: Visual sanity (optional)**

Reload `/#runes`. Expected: prose appears identical to T1's output — full opacity, full column width, plain block below the illumination. DevTools should now show `<div class="manuscript-line" style="display: block; ...">` siblings inside `.manuscript-page`, AND some `<div class="manuscript-line" style="display: none;">` siblings at the end (the unused pool slots).

- [ ] **Step 5: Commit**

```bash
git add lib/agent_mmo_web/controllers/page_html/home.html.heex
git commit -m "$(cat <<'EOF'
refactor(landing): hoist manuscript state + line pool for per-frame layout

Moves the manuscript-verse IIFE state (prepared pretext, layout
constants, padding cache, line-height) out of layoutBody into the
closure so it persists across calls. Pre-creates a pool of 20
.manuscript-line divs at init and recycles them — no appendChild/
remove per call. Renames layoutBody to layoutFrame in anticipation
of per-rAF invocation. Behavior unchanged: prose still renders
statically at full opacity and full column width.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 4: Add cursor tracking + matchMedia + IntersectionObserver

**Files:**
- Modify: `lib/agent_mmo_web/controllers/page_html/home.html.heex`

Wire up the inputs that gate IN/OUT mode but don't change behavior yet — `layoutFrame`'s `useStatic` still hardcoded `true` at this point. Visual: unchanged from T3.

- [ ] **Step 1: Add state variables for the new inputs**

Inside the `manuscriptVerse` IIFE, right after the existing closure-state declarations (the `let prepared = null; ... let lineEls = [];` block), add:

```javascript
    let reducedMotion  = false;
    let mobile         = false;
    let inViewport     = false;
```

So the state block reads:

```javascript
    let prepared       = null;
    let columnWidth    = 0;
    let lineHeightPx   = 0;
    let padLeft        = 0;
    let padTop         = 0;
    let rootRect       = null;
    let cursorXLocal   = null;
    let cursorYLocal   = null;
    let lineEls        = [];
    let lastCursorX    = -9999;
    let lastCursorY    = -9999;
    let lastUseStatic  = null;
    let reducedMotion  = false;
    let mobile         = false;
    let inViewport     = false;
```

- [ ] **Step 2: Add matchMedia + IntersectionObserver setup**

After the `init()` function definition and BEFORE the `function layoutFrame()` definition, add:

```javascript
    const reducedMotionMQ = window.matchMedia('(prefers-reduced-motion: reduce)');
    reducedMotion = reducedMotionMQ.matches;
    reducedMotionMQ.addEventListener('change', e => { reducedMotion = e.matches; });

    const mobileMQ = window.matchMedia('(max-width: 880px)');
    mobile = mobileMQ.matches;
    mobileMQ.addEventListener('change', e => { mobile = e.matches; });

    const viewportIO = new IntersectionObserver((entries) => {
      for (const entry of entries) inViewport = entry.isIntersecting;
    }, { threshold: 0 });
```

And after `init()` is called (just before `layoutFrame()` first runs), call:

```javascript
    viewportIO.observe(root);
```

So the post-fonts-ready block reads:

```javascript
    init();
    viewportIO.observe(root);
    layoutFrame();
```

- [ ] **Step 3: Track cursor position in local manuscript-page coords**

Find the existing pointermove handler at the top of the `<script>` block (the one that just sets `mouseX = e.clientX; mouseY = e.clientY;`). REPLACE it with:

```javascript
  window.addEventListener('pointermove', (e) => {
    mouseX = e.clientX;
    mouseY = e.clientY;

    // If the manuscript root has been measured, derive local-space cursor
    // coords for the reading-window reflow. Null them out when the cursor
    // is outside the manuscript-page's bounding box so the OUT-mode path
    // can detect "cursor not present."
    if (manuscriptRootEl) {
      const r = manuscriptRootEl.getBoundingClientRect();
      if (e.clientX >= r.left && e.clientX <= r.right &&
          e.clientY >= r.top  && e.clientY <= r.bottom) {
        // Local coords use the same offset model the manuscript IIFE uses:
        // (clientCoord - rect-edge - padding). Padding is fetched lazily;
        // the manuscript IIFE caches its own padLeft/padTop, so we just
        // expose the rect-relative coords here and let the IIFE finish
        // the transform.
        window.__manuscriptCursor = {
          x: e.clientX - r.left,
          y: e.clientY - r.top
        };
      } else {
        window.__manuscriptCursor = null;
      }
    }
  });
```

Note: the cursor coords are exposed on `window.__manuscriptCursor` as the bridge between the global pointermove handler and the manuscript IIFE's closure scope. Alternative — extract the IIFE's state to a sibling object — but the global handler/IIFE split is the existing pattern.

- [ ] **Step 4: Pick up the cursor coords inside the IIFE**

Inside the `manuscriptVerse` IIFE, after the matchMedia setup but BEFORE `layoutFrame` is defined, add a small consumer:

```javascript
    // Read cursor coords (set by the global pointermove handler) and translate
    // from rootRect-relative to local-content-space (padding subtracted).
    function refreshCursorLocal() {
      const c = window.__manuscriptCursor;
      if (c == null) {
        cursorXLocal = null;
        cursorYLocal = null;
        return;
      }
      cursorXLocal = c.x - padLeft;
      cursorYLocal = c.y - padTop;
    }
```

This function will be called every rAF tick once T6 hooks it in. For now, it's defined but unused.

- [ ] **Step 5: Smoke test**

```bash
docker compose exec -T -e MIX_ENV=test app mix test test/agent_mmo_web/controllers/page_controller_test.exs
```

Expected: 2 tests, 0 failures.

- [ ] **Step 6: Confirm new code reached the rendered HTML**

```bash
curl -fsS http://127.0.0.1:4100/ | grep -cE 'reducedMotionMQ|mobileMQ|viewportIO|__manuscriptCursor|refreshCursorLocal'
```

Expected: at least 5 matches.

- [ ] **Step 7: Visual sanity**

Reload `/#runes`. Expected: visually identical to T3 — prose at full opacity, full column width. Cursor movement should already be updating `window.__manuscriptCursor` (verify in DevTools console: `window.__manuscriptCursor` should be an object when the cursor is over the manuscript, `null` when not), but the IIFE doesn't use it yet so layout is unchanged.

- [ ] **Step 8: Commit**

```bash
git add lib/agent_mmo_web/controllers/page_html/home.html.heex
git commit -m "$(cat <<'EOF'
feat(landing): track cursor-over-manuscript + media-query gates

Adds matchMedia listeners for prefers-reduced-motion and max-width 880px,
an IntersectionObserver on the manuscript root for in-viewport gating,
and a global pointermove path that exposes rootRect-relative cursor
coords on window.__manuscriptCursor (or null when cursor is outside the
manuscript page). Plus refreshCursorLocal() inside the IIFE to translate
rootRect-relative to padding-adjusted local space.

State machinery only — layoutFrame still hardcodes useStatic = true, so
visual behavior is unchanged from T3.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 5: Add IN/OUT mode logic to `layoutFrame`

**Files:**
- Modify: `lib/agent_mmo_web/controllers/page_html/home.html.heex`

Activate the actual reading window. Per-line: dy = distance from line's vertical midpoint to cursor's Y. If dy > R or no cursor / reducedMotion / mobile / !inViewport, line stays in OUT mode (full column width, dim 0.18). Otherwise IN mode: maxWidth = max(chord, MIN_WIDTH), startX = cursorXLocal − maxWidth/2 (clamped to column bounds), opacity = BASE_OPACITY + (1 − BASE_OPACITY)·(1 − dy/R). At this point `layoutFrame` is still called once at init + on resize — T6 will run it per rAF tick.

- [ ] **Step 1: Replace `layoutFrame` with the cursor-aware version**

Find `function layoutFrame()` inside the `manuscriptVerse` IIFE (added in T3). Replace its ENTIRE body with:

```javascript
    function layoutFrame() {
      if (!prepared) return;

      refreshCursorLocal();

      const useStatic = reducedMotion || mobile || !inViewport
                     || cursorXLocal == null || cursorYLocal == null;

      let cur = { segmentIndex: 0, graphemeIndex: 0 };
      let y = 0;
      let lineIdx = 0;

      while (lineIdx < N_LINES_MAX) {
        const lineMidY = y + lineHeightPx / 2;
        let maxWidth, startX, opacity;

        if (useStatic) {
          maxWidth = columnWidth;
          startX   = 0;
          opacity  = 1.0;
        } else {
          const dy = Math.abs(lineMidY - cursorYLocal);
          if (dy > R) {
            maxWidth = columnWidth;
            startX   = 0;
            opacity  = BASE_OPACITY;
          } else {
            const chord = 2 * Math.sqrt(R*R - dy*dy);
            maxWidth = Math.max(chord, MIN_WIDTH);
            startX   = cursorXLocal - maxWidth / 2;
            // Clamp startX so the line stays inside the column
            if (startX < 0) startX = 0;
            if (startX + maxWidth > columnWidth) startX = columnWidth - maxWidth;
            // Smooth opacity from full at the center to BASE at the rim
            opacity = BASE_OPACITY + (1.0 - BASE_OPACITY) * (1.0 - dy / R);
          }
        }

        const range = pretext.layoutNextLineRange(prepared, cur, maxWidth);
        if (range === null) {
          for (let k = lineIdx; k < N_LINES_MAX; k++) {
            lineEls[k].style.display = 'none';
          }
          return;
        }

        const line = pretext.materializeLineRange(prepared, range);
        const el = lineEls[lineIdx];
        el.style.display  = 'block';
        el.style.left     = (padLeft + startX) + 'px';
        el.style.top      = (padTop + y) + 'px';
        el.style.maxWidth = maxWidth + 'px';
        el.style.opacity  = opacity.toFixed(3);

        const accentRe = /\bsurvive\b/i;
        if (accentRe.test(line.text)) {
          el.innerHTML = line.text.replace(accentRe, m => `<span class="torch">${m}</span>`);
        } else {
          el.textContent = line.text;
        }

        cur = range.end;
        y += lineHeightPx;
        lineIdx++;
      }
    }
```

- [ ] **Step 2: Smoke test**

```bash
docker compose exec -T -e MIX_ENV=test app mix test test/agent_mmo_web/controllers/page_controller_test.exs
```

Expected: 2 tests, 0 failures.

- [ ] **Step 3: Visual check — limited because we're not per-rAF yet**

Reload `/#runes`. Move the cursor over the manuscript page, then move it away, then RESIZE the browser window (this triggers init() + layoutFrame()). Expected sequence:

- After page load (cursor not yet over manuscript): prose at BASE_OPACITY (0.18) full column width, since `useStatic = false` and dy > R for every line.
- After resize while cursor over manuscript: brief moment where prose reflows to fit chord widths around the cursor's last-known position.

Per-rAF reflow comes in T6 — until then you can only see the cursor-aware mode by triggering a resize.

NOTE: at this point a static-loaded page with the cursor NOT over the manuscript shows the prose at low opacity (0.18). Looks like a regression from T3. T6 fixes this by making `useStatic = true` whenever cursor is absent — but actually that's already the case because `cursorXLocal == null` triggers useStatic. Verify the logic: on initial page load, `window.__manuscriptCursor` is undefined, `refreshCursorLocal()` sets `cursorXLocal = null`, `useStatic = ... || cursorXLocal == null` = true → opacity 1.0. ✓ Should look full opacity until cursor first enters the manuscript.

- [ ] **Step 4: Commit**

```bash
git add lib/agent_mmo_web/controllers/page_html/home.html.heex
git commit -m "$(cat <<'EOF'
feat(landing): wire IN/OUT mode logic in layoutFrame

Per line: distance from line midpoint to cursor Y decides mode. IN mode
(within radius R, cursor present, not mobile/reduced-motion/off-viewport)
uses chord-width as maxWidth, centers the line on cursor X (clamped to
column), and ramps opacity from 1.0 at center to BASE_OPACITY at rim.
OUT mode (anything else with cursor present) uses full column width at
BASE_OPACITY. useStatic fallback (no cursor, reduced-motion, mobile,
off-viewport) uses full opacity static layout.

Not yet rAF-driven — layoutFrame still only fires on init + resize. T6
hooks it into the global tick loop for per-frame reflow.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 6: Hook layoutFrame into the global rAF tick with 2px quantization

**Files:**
- Modify: `lib/agent_mmo_web/controllers/page_html/home.html.heex`

Move per-frame invocation into the global `tick()` rAF loop that already drives the cursor + torchlight halo. Quantize: only re-layout if cursor moved ≥ 2px since last frame OR `useStatic` flipped. The IIFE's `layoutFrame` becomes the rAF callback for everything reading-window-related; the standalone init+layoutFrame call at IIFE start stays (for the first render before any cursor movement).

- [ ] **Step 1: Expose `layoutFrame` to the outer scope**

The `manuscriptVerse` IIFE is an async function; its inner `layoutFrame` isn't visible to the top-level `tick()`. Bridge it via a module-level callback:

Inside the IIFE, AFTER `layoutFrame` is defined and BEFORE the `init()` call, add:

```javascript
    window.__manuscriptLayoutFrame = layoutFrame;
```

(Same single-global-bridge pattern as `window.__manuscriptCursor`.)

- [ ] **Step 2: Add quantized invocation inside `tick()`**

Find the existing `tick()` function (it currently does the torchlight + cursor transform updates). Add this BEFORE the `requestAnimationFrame(tick);` line at the end:

```javascript
    // Per-rAF reading-window reflow. Quantize to avoid pretext work when
    // the cursor hasn't meaningfully moved.
    if (window.__manuscriptLayoutFrame) {
      const c = window.__manuscriptCursor;
      const cx = c ? c.x : null;
      const cy = c ? c.y : null;
      const movedX = Math.abs((cx == null ? -9999 : cx) - (window.__lastManuscriptCursorX == null ? -9999 : window.__lastManuscriptCursorX));
      const movedY = Math.abs((cy == null ? -9999 : cy) - (window.__lastManuscriptCursorY == null ? -9999 : window.__lastManuscriptCursorY));
      const cursorEnteredOrLeft = (cx == null) !== (window.__lastManuscriptCursorX == null);
      if (cursorEnteredOrLeft || movedX >= 2 || movedY >= 2) {
        window.__lastManuscriptCursorX = cx;
        window.__lastManuscriptCursorY = cy;
        window.__manuscriptLayoutFrame();
      }
    }
```

So the full `tick()` becomes:

```javascript
  function tick() {
    tlX += (mouseX - tlX) * 0.06;
    tlY += (mouseY - tlY) * 0.06;
    cX  += (mouseX - cX) * 0.4;
    cY  += (mouseY - cY) * 0.4;
    if (torchlight) torchlight.style.transform = `translate(calc(-50% + ${tlX}px), calc(-50% + ${tlY}px))`;
    if (cursor)     cursor.style.transform     = `translate(calc(-50% + ${cX}px), calc(-50% + ${cY}px))`;

    if (window.__manuscriptLayoutFrame) {
      const c = window.__manuscriptCursor;
      const cx = c ? c.x : null;
      const cy = c ? c.y : null;
      const movedX = Math.abs((cx == null ? -9999 : cx) - (window.__lastManuscriptCursorX == null ? -9999 : window.__lastManuscriptCursorX));
      const movedY = Math.abs((cy == null ? -9999 : cy) - (window.__lastManuscriptCursorY == null ? -9999 : window.__lastManuscriptCursorY));
      const cursorEnteredOrLeft = (cx == null) !== (window.__lastManuscriptCursorX == null);
      if (cursorEnteredOrLeft || movedX >= 2 || movedY >= 2) {
        window.__lastManuscriptCursorX = cx;
        window.__lastManuscriptCursorY = cy;
        window.__manuscriptLayoutFrame();
      }
    }

    requestAnimationFrame(tick);
  }
```

- [ ] **Step 3: Smoke test**

```bash
docker compose exec -T -e MIX_ENV=test app mix test test/agent_mmo_web/controllers/page_controller_test.exs
```

Expected: 2 tests, 0 failures.

- [ ] **Step 4: Visual check — full reading window now active**

Reload `/#runes`. Expected:

1. On page load (no cursor over manuscript): prose at full opacity, full column width.
2. Move cursor INTO the manuscript-page: prose dims to 0.18 EXCEPT inside a ~320px circle around your cursor, where lines reflow to chord-width and are at full opacity.
3. Move cursor around: lines inside the cursor circle reflow per frame, opacity smoothly ramps at the rim.
4. Move cursor OFF the manuscript-page: prose flashes back to full opacity, full column width.

If anything looks broken, inspect `window.__manuscriptCursor` in DevTools to confirm cursor coords are being captured, and `window.__manuscriptLayoutFrame` to confirm the bridge is set.

- [ ] **Step 5: Quick HTTP sanity**

```bash
curl -fsS http://127.0.0.1:4100/ | grep -cE '__manuscriptLayoutFrame|__lastManuscriptCursor|cursorEnteredOrLeft'
```

Expected: at least 3 matches.

- [ ] **Step 6: Commit**

```bash
git add lib/agent_mmo_web/controllers/page_html/home.html.heex
git commit -m "$(cat <<'EOF'
feat(landing): per-rAF reading window reflow

Bridges manuscriptVerse IIFE's layoutFrame to the global tick() rAF
loop via window.__manuscriptLayoutFrame. Each rAF tick checks if the
cursor moved >=2px or if cursor entered/left the manuscript page; if
so, runs layoutFrame for a fresh chord-width reflow. The 2px quantizer
prevents pretext work when the cursor is stationary.

Cursor over the manuscript now reveals a circular reading window with
lines reflowing in real time around the cursor's vertical position;
cursor off the manuscript restores full-opacity static layout.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 7: Verify mobile + reduced-motion + JS-off fallback paths

**Files:** none unless tweaks needed.

The fallback branches were wired up in T4–T5 but never visually verified. This task walks each one.

- [ ] **Step 1: Mobile (≤880px viewport) fallback**

Open DevTools, switch to a 375×667 mobile preset (iPhone SE) or just resize the viewport below 880px. Reload `/#runes`. Expected:

- Manuscript page renders below the chrome with the illumination as a static `position: static` block at the top (Option A's mobile media query for `.manuscript-illumination` still applies).
- Body prose appears at full opacity 1.0, full column width.
- Moving a touch / pointer over the manuscript does NOT trigger the reading-window reflow.

- [ ] **Step 2: Reduced-motion fallback**

Switch the DevTools "Rendering" panel to emulate `prefers-reduced-motion: reduce` (or set it via your OS's accessibility preferences). Reload `/#runes` at desktop viewport (≥881px). Expected:

- Prose at full opacity, full column width, static layout.
- Moving the cursor over the manuscript does NOT trigger reflow. The `.manuscript-line { transition: opacity 80ms linear; }` rule is overridden by `@media (prefers-reduced-motion: reduce) { .manuscript-line { transition: none; opacity: 1 !important; } }`.

- [ ] **Step 3: JS-disabled fallback**

In DevTools settings, enable "Disable JavaScript." Reload `/#runes`. Expected:

- The original `<p class="manuscript-body">` renders as plain italic block prose (no pretext, no reading window).
- The illumination ASCII renders at its CSS-positioned location.
- The attribution row renders below.

This works because `.manuscript-page.pretext-active .manuscript-body { visibility: hidden; }` only triggers when JS sets the `pretext-active` class — which never happens with JS off.

- [ ] **Step 4: Off-viewport (IntersectionObserver gate)**

Reload normally (JS on, no reduced motion, desktop viewport). Scroll DOWN until the manuscript page is fully out of view, then move your cursor around. Expected: no perceivable layout work (the IntersectionObserver should mark `inViewport = false`, triggering `useStatic = true`, so `layoutFrame` does the static path).

Inspect `window.__manuscriptLayoutFrame` while off-viewport — calling it manually should produce the full-opacity static layout (you can verify by scrolling BACK into view and seeing the prose start at full opacity before the next cursor movement re-engages the reading window).

- [ ] **Step 5: Commit if any fallback tweaks were needed**

If Steps 1–4 surfaced any issues, fix them and commit:

```bash
git add lib/agent_mmo_web/controllers/page_html/home.html.heex
git commit -m "fix(landing): reading-window fallback path corrections

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

If no tweaks were needed, no commit — just note in the implementor's handoff message that T7 verified clean.

---

## Task 8: Acceptance criteria walkthrough

**Files:** none — verification only.

Walk each of the 12 acceptance criteria from the spec, recording pass/fail/notes. No commit.

- [ ] **AC 1:** Cursor resting over the manuscript page reveals a circle of full-opacity prose centered on cursor; rest of prose at ~0.18 opacity at full column width.

- [ ] **AC 2:** Moving the cursor reflows lines inside the disk in real time. Line widths change as cursor moves; text centered on cursor X.

- [ ] **AC 3:** Cursor OFF the manuscript-page → all lines at full opacity, full column width, static.

- [ ] **AC 4:** Illumination ASCII renders at top-left, no longer affects body layout (body lines flow underneath it, dimmed in OUT mode).

- [ ] **AC 5:** Illumination's flame no longer brightens when cursor approaches (T7 proximity glow gone).

- [ ] **AC 6:** Accent word `survive` still glows amber + pulses inside whichever materialized line contains it.

- [ ] **AC 7:** Resize reflows the layout; reading window adapts to new geometry afterward.

- [ ] **AC 8:** With `prefers-reduced-motion: reduce`: prose full opacity, static, no per-frame reflow.

- [ ] **AC 9:** Viewport ≤ 880px: same as AC 8.

- [ ] **AC 10:** JS disabled: original `<p>` visible at full opacity.

- [ ] **AC 11:** No other station's appearance or behavior changes (Threshold, Doorway, Wager, Flame, Invitation).

- [ ] **AC 12:** Shell verification of scope:

```bash
git diff main --stat
ls priv/static/assets/ 2>/dev/null
git diff main -- mix.exs
git diff main -- lib/agent_mmo_web/router.ex
```

Diff should show changes only in `lib/agent_mmo_web/controllers/page_html/home.html.heex`. `priv/static/assets/` should still not exist. `mix.exs` and `router.ex` diffs should be empty.

- [ ] **Final step:** Report status to user — which ACs passed cleanly, which needed tweaks, any open issues. No commit.

---

## Out-of-scope follow-ups (not in this plan)

- Multi-station reading windows (extend to Threshold, Doorway, etc.). Each station with prose could be eligible.
- Tunable controls (radius, base opacity) as URL params or developer console toggles.
- Touch-screen reading mechanic (tap-to-reveal? hold-to-read?) — touch UX is genuinely a different design problem.
- Migrate accent post-process from regex to pretext's `prepareRichInline` API — still a v2 hook for multi-accent inscriptions.

---

## Self-review notes (implementor: read before starting)

1. **Spec coverage:** Every "In scope" bullet from the spec maps to a task (retirements → T1, opacity transition → T2, pool + closure state → T3, matchMedia/IO/cursor tracking → T4, IN/OUT mode → T5, per-rAF integration → T6, fallback verification → T7, ACs → T8). Every "Out of scope" item from the spec is absent from all tasks.

2. **Global bridge pattern:** The plan uses `window.__manuscriptCursor` and `window.__manuscriptLayoutFrame` to bridge the global `<script>` scope and the `manuscriptVerse` IIFE closure. This mirrors the existing pattern of top-level scope (cursor + torchlight rAF) talking to inline IIFEs (rogueBackground, manuscriptVerse) via shared state and global functions. Cleaner alternatives (module pattern, event bus) would diverge from the established file pattern.

3. **2px quantizer threshold (T6):** Picked to roughly match the existing cursor's hardware-event cadence on most pointing devices. Pretext layout work is cheap (~1ms/call) but skipping no-op frames during stationary cursor saves cumulative CPU. Tunable.

4. **N_LINES_MAX = 20:** At narrow chord widths the locked 4-sentence inscription can multiply to ~15 lines. 20 gives headroom. If overflow becomes a real risk, the loop's terminal `range === null` branch hides unused slots; if more than 20 lines are needed, the tail of the prose is silently dropped. The spec acknowledges this as a known limit.

5. **Test discipline:** The only automated test (`test/agent_mmo_web/controllers/page_controller_test.exs`) verifies server-rendered markup, which is unchanged by this plan. All behavior is visual. T8's acceptance walk is the test. Headless browser testing was considered and rejected (no Wallaby setup, headless Chrome not installed in dev env).

6. **rAF + 200ms-debounced resize coexist:** T3's resize listener still re-runs `init()` + `layoutFrame()`. T6 additionally invokes `layoutFrame()` per rAF. There's no conflict because both paths read from the same closure state; the worst case is one redundant layoutFrame call within 200ms of a resize. Cheap.
