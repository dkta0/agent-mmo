# Pretext Manuscript Verse Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace station 04 (`#runes`) of the atmospheric landing page with a pretext-driven manuscript page — body inscription prose wrapping an ASCII illumination drop-cap on the left, with cursor-proximity glow on the illumination.

**Architecture:** Inline ESM dynamic import of `@chenglou/pretext@0.0.7` from esm.sh. DOM render target — one absolutely-positioned `<div class="manuscript-line">` per laid-out line. Variable per-line `maxWidth` computed from current `y` versus the illumination's measured height (lines colliding with illumination are narrower and shifted right; lines below get the full column). Cursor-distance glow driven by a single CSS custom property (`--torch-distance`) updated in the existing pointermove handler. All code lives in the single HEEx file — no esbuild changes, no new assets.

**Tech Stack:** Phoenix 1.7 HEEx, vanilla JS (ESM dynamic import), `@chenglou/pretext@0.0.7`, IBM Plex Mono + Cormorant Garamond.

**Spec:** `docs/superpowers/specs/2026-05-24-pretext-manuscript-verse-design.md`

---

## File map

- **Modify:** `lib/agent_mmo_web/controllers/page_html/home.html.heex` — all CSS, HEEx markup for station 04, and the manuscript-verse IIFE in the existing `<script>` block.
- **Create:** `test/agent_mmo_web/controllers/page_controller_test.exs` — Phoenix controller smoke test for the new manuscript markup. Phoenix's controller test pattern is used elsewhere in this repo (`scenario_controller_test.exs` is the reference).

No other files touched. No new dependencies in `mix.exs`. No new static assets.

---

## Task 1: Gate — confirm copy and illumination art

**Files:** none

This is the user-approval gate from the spec. No code is written, no commit is made until both items are locked. The implementor poses the questions, the user responds, the implementor records the decisions in this plan document (edit Task 1 to record the locked values before moving on).

- [ ] **Step 1: Confirm body inscription copy**

Present the draft to the user and accept either approval or replacement text:

> *We did not ask if it could speak in our tongue.<br />
> We did not ask if it could solve our riddles.<br />
> We asked if it would still be standing<br />
> when the door swung shut behind it — survive.*

Record the final text directly in Task 3, Step 2's HEEx block. If the accent word changes from `survive`, also update Task 5, Step 4's post-process matcher.

- [ ] **Step 2: Confirm illumination ASCII**

Present the proposed illumination (a scaled-down version of station 05's existing torch, ~10 lines tall):

```
     )
   ( ) )
    ( )
     )
   ▓▓▓
   ▓▓▓
    │
    │
    │
   ─────
```

The implementor must verify, before starting Task 3, that:
- The illumination's widest line determines its rendered column width — keep it at 7 characters wide so the body has at least ~30ch of column to wrap into on desktop.
- Glyph classes available from the page's existing CSS: `flame`, `flame-2`, `ember-glow`, `handle`, `ground`. Each line of the illumination should be wrapped in a span using one of these classes (re-use exactly as station 05 does).

Record the final ASCII in Task 3, Step 2's HEEx block.

- [ ] **Step 3: Confirm marginalia gloss in or out**

Either:

> *— attrib. unknown<br />
> first scrawled<br />
> in the cellar*

(or replacement text from the user) — record in Task 3 — **or** drop the `<aside class="manuscript-gloss">` element entirely from Task 3's HEEx block and skip any `.manuscript-gloss` CSS that references it. If dropped, the right side of the manuscript page becomes empty parchment space, which is fine.

- [ ] **Step 4: No commit**

No file changes were made; nothing to commit. Edit this Task 1 in the plan to record the locked decisions in-place before continuing to Task 2.

---

## Task 2: Failing smoke test for manuscript markup

**Files:**
- Create: `test/agent_mmo_web/controllers/page_controller_test.exs`

This is the TDD red phase: assert the new markup exists in the rendered HTML before changing the markup. Test fails because today's home page has no `manuscript-page` class.

- [ ] **Step 1: Write the failing test**

Create `test/agent_mmo_web/controllers/page_controller_test.exs` with:

```elixir
defmodule AgentMmoWeb.PageControllerTest do
  use AgentMmoWeb.ConnCase, async: true

  describe "GET /" do
    test "renders the atmospheric landing page", %{conn: conn} do
      conn = get(conn, "/")
      body = html_response(conn, 200)
      assert body =~ "TAVERNBENCH"
      assert body =~ "may your agent"
    end

    test "renders the manuscript verse station markup", %{conn: conn} do
      conn = get(conn, "/")
      body = html_response(conn, 200)

      # Manuscript page wrapper exists and replaces the old single-quote verse card
      assert body =~ ~s(class="runes-block manuscript-page) or body =~ "manuscript-page"

      # Illumination drop-cap + body + attribution all present in the rendered HTML
      assert body =~ "manuscript-illumination"
      assert body =~ "manuscript-body"
      assert body =~ "INSCRIBED ABOVE THE TAVERN DOOR"
    end
  end
end
```

- [ ] **Step 2: Run the test and verify it fails**

```bash
docker compose exec -T app mix test test/agent_mmo_web/controllers/page_controller_test.exs
```

Expected output: the `renders the atmospheric landing page` test PASSES (existing page has both strings), and `renders the manuscript verse station markup` FAILS with assertion errors about missing `manuscript-page`, `manuscript-illumination`, etc. Both assertions failing is the correct red state.

- [ ] **Step 3: Commit the failing test**

```bash
git add test/agent_mmo_web/controllers/page_controller_test.exs
git commit -m "$(cat <<'EOF'
test(page): add controller smoke tests for atmospheric landing

Adds a basic conn test for GET / asserting both the existing page
strings and the (not-yet-built) manuscript verse markup. The manuscript
assertions fail as expected — implementation follows.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 3: Manuscript markup + CSS (fallback layout, no JS)

**Files:**
- Modify: `lib/agent_mmo_web/controllers/page_html/home.html.heex`

Replace the current `<div class="runes-block">` contents with the manuscript structure and add CSS. No JavaScript yet — the page must render a passable fallback (illumination above, body below) with pretext loaded but inactive.

- [ ] **Step 1: Add manuscript CSS rules**

Open `lib/agent_mmo_web/controllers/page_html/home.html.heex`. Locate the `STATION 04 — Verse` CSS block (search for `/* STATION 04 — Verse */`). Immediately after the existing `.runes-block .attrib .star` rule (right before the `/* STATION 05 — Flame */` comment block), insert:

```css
  /* ============================================================
     Manuscript page — pretext-driven verse layout
     ============================================================ */
  .manuscript-page {
    display: block;
    text-align: left;
    position: relative;
    --torch-distance: 0;
  }

  .manuscript-illumination {
    position: absolute;
    top: 64px;
    left: 72px;
    margin: 0;
    font-family: var(--mono);
    font-size: clamp(14px, 1.4vw, 18px);
    line-height: 1.0;
    color: var(--parchment-mute);
    white-space: pre;
    user-select: none;
    z-index: 2;
  }
  .manuscript-illumination .flame {
    color: var(--torch-bright);
    text-shadow:
      0 0 calc(18px + 16px * var(--torch-distance)) rgba(243,194,102, calc(0.7 + 0.3 * var(--torch-distance))),
      0 0 calc(36px + 32px * var(--torch-distance)) rgba(224,166,74, 0.55);
    animation: flameFlicker 1.8s ease-in-out infinite;
    display: inline-block;
  }
  .manuscript-illumination .flame-2 {
    color: var(--ember);
    text-shadow:
      0 0 calc(16px + 14px * var(--torch-distance)) rgba(255,156,74, 0.7),
      0 0 calc(30px + 28px * var(--torch-distance)) rgba(224,166,74, 0.4);
    animation: flameFlicker 2.1s ease-in-out infinite reverse;
    display: inline-block;
  }
  .manuscript-illumination .ember-glow { color: var(--ember-deep); }
  .manuscript-illumination .handle     { color: var(--parchment-ghost); }
  .manuscript-illumination .ground     { color: var(--parchment-mute); }

  .manuscript-body {
    font-family: var(--serif);
    font-style: italic;
    font-weight: 400;
    font-size: clamp(22px, 3vw, 42px);
    line-height: 1.45;
    letter-spacing: 0.005em;
    color: var(--parchment);
    margin: 0;
  }
  .manuscript-body .torch {
    color: var(--torch);
    font-style: normal;
    font-weight: 500;
    text-shadow: 0 0 24px rgba(243,194,102,0.45);
    animation: glowPulse 5s ease-in-out infinite;
  }

  .manuscript-page.pretext-active .manuscript-body {
    visibility: hidden;
  }

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
  .manuscript-line .torch {
    color: var(--torch);
    font-style: normal;
    font-weight: 500;
    text-shadow: 0 0 24px rgba(243,194,102,0.45);
    animation: glowPulse 5s ease-in-out infinite;
  }

  .manuscript-gloss {
    position: absolute;
    top: 64px;
    right: 72px;
    width: 14ch;
    font-family: var(--mono);
    font-size: 11px;
    letter-spacing: 0.04em;
    color: var(--parchment-mute);
    line-height: 1.5;
    font-style: normal;
  }

  @media (max-width: 880px) {
    .manuscript-illumination {
      position: static;
      margin-bottom: 24px;
    }
    .manuscript-gloss {
      position: static;
      margin-top: 24px;
      width: auto;
      text-align: right;
    }
  }
```

- [ ] **Step 2: Replace the station 04 markup**

In the same file, locate the existing `<section class="station station-runes" id="runes">` block and find this inside it:

```html
      <div class="runes-block reveal r-up">
        <span class="corner-bl"></span>
        <span class="corner-br"></span>
        <p class="verse">
          &ldquo;We do not ask if your model can <em>answer</em>.<br />
          We ask if it can <span class="torch">survive</span>.&rdquo;
        </p>
        <div class="attrib">
          <span class="star">✦</span>
          <span>INSCRIBED ABOVE THE TAVERN DOOR</span>
          <span class="star">✦</span>
        </div>
      </div>
```

Replace it with (substitute final copy/ASCII from Task 1):

```html
      <div class="runes-block manuscript-page reveal r-up" data-pretext-mount>
        <span class="corner-bl"></span>
        <span class="corner-br"></span>

        <pre class="manuscript-illumination" aria-hidden="true"><span class="flame">     )</span>
<span class="flame">   ( ) )</span>
<span class="flame-2">    ( )</span>
<span class="flame">     )</span>
<span class="ember-glow">   ▓▓▓</span>
<span class="ember-glow">   ▓▓▓</span>
<span class="handle">    │</span>
<span class="handle">    │</span>
<span class="handle">    │</span>
<span class="ground">   ─────</span></pre>

        <p class="manuscript-body">
          We did not ask if it could speak in our tongue.
          We did not ask if it could solve our riddles.
          We asked if it would still be standing
          when the door swung shut behind it &mdash; <span class="torch">survive</span>.
        </p>

        <aside class="manuscript-gloss">— attrib. unknown<br />first scrawled<br />in the cellar</aside>

        <div class="attrib">
          <span class="star">✦</span>
          <span>INSCRIBED ABOVE THE TAVERN DOOR</span>
          <span class="star">✦</span>
        </div>
      </div>
```

Notes for the implementor:
- The `<p>` no longer uses `<br />` between sentences. Pretext wraps on whitespace; explicit breaks would force unwanted line splits. The browser fallback (when pretext is inactive) will flow the sentences as one paragraph — which is still readable manuscript prose.
- The `<pre>` keeps each illumination line wrapped in a glyph class span; the inline newlines inside `<pre>` preserve the multi-line ASCII shape.

- [ ] **Step 3: Run the smoke test and verify it passes**

```bash
docker compose exec -T app mix test test/agent_mmo_web/controllers/page_controller_test.exs
```

Expected: both tests PASS. The page now contains `manuscript-page`, `manuscript-illumination`, `manuscript-body`, and the attribution string.

- [ ] **Step 4: Visual smoke check — fallback layout**

Browser-side check while pretext isn't wired up yet. From the host:

```bash
curl -fsS http://127.0.0.1:4100/ | grep -E 'manuscript-illumination|manuscript-body|INSCRIBED' | head -5
```

Expected: three matching lines confirming the markup reached the response body. Visiting `http://localhost:4100/` in a browser and scrolling to station 04: the ASCII torch sits at the top-left of the parchment frame; the body prose sits below or beside it (depending on viewport), with the optional gloss in the right margin. Looks unstyled-by-pretext but coherent.

- [ ] **Step 5: Commit**

```bash
git add lib/agent_mmo_web/controllers/page_html/home.html.heex
git commit -m "$(cat <<'EOF'
feat(landing): manuscript markup + CSS for station 04 verse

Replaces the single-quote verse card with a manuscript-page structure:
an ASCII illumination drop-cap, body inscription prose, an optional
chronicler's gloss, and the existing attribution row. CSS lays out the
illumination absolutely top-left and provides positioning hooks for the
pretext-driven line elements that come next. No JS yet — page renders a
readable fallback (illumination above prose) without pretext.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 4: Pretext boot — initial layout at full column width

**Files:**
- Modify: `lib/agent_mmo_web/controllers/page_html/home.html.heex`

Add the pretext IIFE. This task uses `columnWidth` (no obstacle) to validate the import / measurement / DOM-emit pipeline before adding obstacle logic. Visual after this task: prose lines positioned by JS overlap the illumination (looks broken — expected; Task 5 fixes it).

- [ ] **Step 1: Add the manuscript-verse IIFE**

Open `lib/agent_mmo_web/controllers/page_html/home.html.heex`. Find the closing line of the `rogueBackground` IIFE inside `<script>` (it ends with `})();` right before `</script>`). Immediately after it (still inside the same `<script>` block, before `</script>`), insert:

```javascript
  // ============================================================
  // Pretext manuscript verse — station 04
  // Body prose wraps around the ASCII illumination drop-cap.
  // ============================================================
  (async function manuscriptVerse() {
    const root = document.querySelector('.manuscript-page[data-pretext-mount]');
    if (!root) return;

    const illumination = root.querySelector('.manuscript-illumination');
    const body = root.querySelector('.manuscript-body');
    if (!illumination || !body) return;

    let pretext;
    try {
      pretext = await import('https://esm.sh/@chenglou/pretext@0.0.7');
    } catch (err) {
      // CDN unreachable — leave the fallback <p> visible
      return;
    }

    const GUTTER = 24;
    const ACCENT_WORD = 'survive';

    function buildFontString(el) {
      const cs = getComputedStyle(el);
      // Canvas font shorthand: "[style] [weight] [size] [family]"
      return `${cs.fontStyle} ${cs.fontWeight} ${cs.fontSize} ${cs.fontFamily}`;
    }

    function layoutBody() {
      // Clear any previously rendered lines from a prior layout pass
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

      // Plain text — accent will be wrapped after layout via post-process
      const text = body.textContent.replace(/\s+/g, ' ').trim();

      const prepared = pretext.prepareWithSegments(text, font);

      let cursor = { segmentIndex: 0, graphemeIndex: 0 };
      let y = 0;

      while (true) {
        const maxWidth = columnWidth;          // no obstacle yet — Task 5 adds it
        const startX = 0;
        const range = pretext.layoutNextLineRange(prepared, cursor, maxWidth);
        if (range === null) break;

        const line = pretext.materializeLineRange(prepared, range);
        const el = document.createElement('div');
        el.className = 'manuscript-line';
        el.textContent = line.text;
        el.style.left = (padLeft + startX) + 'px';
        el.style.top  = (padTop + y) + 'px';
        el.style.maxWidth = maxWidth + 'px';
        root.appendChild(el);

        cursor = range.end;
        y += lineHeightPx;
      }

      root.classList.add('pretext-active');
    }

    layoutBody();
  })();
```

- [ ] **Step 2: Run the existing test suite — nothing should break**

```bash
docker compose exec -T app mix test test/agent_mmo_web/controllers/page_controller_test.exs
```

Expected: PASS. (The new JS doesn't affect what's in the rendered HTML — it runs client-side.)

- [ ] **Step 3: Visual check — pretext is laying out lines**

Reload `http://localhost:4100/` in a browser. Scroll to station 04. Open DevTools and verify:
- The `.manuscript-page` element has class `pretext-active`.
- There are multiple sibling `<div class="manuscript-line">` elements with `style="position: absolute; left: 72px; top: ...px"`.
- The original `<p class="manuscript-body">` exists but has `visibility: hidden` computed style.
- The lines visually OVERLAP the illumination (this is expected — Task 5 adds the obstacle).

If lines don't appear at all, open DevTools console — look for failed dynamic import or a thrown error from `prepareWithSegments`. The first call may need a one-character tweak depending on the exact `@chenglou/pretext@0.0.7` API.

- [ ] **Step 4: Commit**

```bash
git add lib/agent_mmo_web/controllers/page_html/home.html.heex
git commit -m "$(cat <<'EOF'
feat(landing): wire pretext to lay out manuscript body lines

Boots @chenglou/pretext from esm.sh as an ESM dynamic import inside the
existing inline <script>. Measures the body's computed font, prepares
segments, walks line ranges at full column width (no obstacle yet), and
materializes each line as an absolutely-positioned <div class="manuscript-line">.
The fallback <p> stays in the DOM with visibility:hidden so screen
readers and search engines still see the prose.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 5: Variable-width wrap around the illumination + accent re-wrap

**Files:**
- Modify: `lib/agent_mmo_web/controllers/page_html/home.html.heex`

Lines that fall in the illumination's vertical range get a shorter `maxWidth` and shifted-right `startX`. After layout, scan rendered lines for the accent word (`survive`) and wrap it in a `<span class="torch">` for the glow effect.

- [ ] **Step 1: Read illumination bounds and apply variable widths**

In the `layoutBody()` function added in Task 4, replace the body of the function from `const rootRect = ...` through the `while` loop with this version:

```javascript
    function layoutBody() {
      root.querySelectorAll('.manuscript-line').forEach(el => el.remove());

      const rootRect = root.getBoundingClientRect();
      const illRect = illumination.getBoundingClientRect();
      const cs = getComputedStyle(root);
      const padLeft = parseFloat(cs.paddingLeft) || 0;
      const padRight = parseFloat(cs.paddingRight) || 0;
      const padTop = parseFloat(cs.paddingTop) || 0;
      const columnWidth = rootRect.width - padLeft - padRight;

      // Illumination's local-coords box inside the manuscript page
      const illLeft = illRect.left - rootRect.left - padLeft;
      const illTop  = illRect.top  - rootRect.top  - padTop;
      const illW    = illRect.width;
      const illH    = illRect.height;

      const bodyCS = getComputedStyle(body);
      const lineHeightPx = parseFloat(bodyCS.lineHeight);
      const font = buildFontString(body);

      const text = body.textContent.replace(/\s+/g, ' ').trim();
      const prepared = pretext.prepareWithSegments(text, font);

      let cursor = { segmentIndex: 0, graphemeIndex: 0 };
      let y = 0;

      while (true) {
        // A line "collides" with the illumination if any part of its line-box
        // overlaps the illumination's vertical range.
        const lineTop    = y;
        const lineBottom = y + lineHeightPx;
        const collides   = lineBottom > illTop && lineTop < (illTop + illH);

        const maxWidth = collides ? (columnWidth - illW - GUTTER) : columnWidth;
        const startX   = collides ? (illLeft + illW + GUTTER) : 0;

        const range = pretext.layoutNextLineRange(prepared, cursor, maxWidth);
        if (range === null) break;

        const line = pretext.materializeLineRange(prepared, range);
        const el = document.createElement('div');
        el.className = 'manuscript-line';
        el.style.left = (padLeft + startX) + 'px';
        el.style.top  = (padTop + y) + 'px';
        el.style.maxWidth = maxWidth + 'px';

        // Post-process: wrap the accent word in a styled span for the glow
        const accentRe = new RegExp(`\\b${ACCENT_WORD}\\b`, 'i');
        if (accentRe.test(line.text)) {
          el.innerHTML = line.text.replace(
            accentRe,
            (match) => `<span class="torch">${match}</span>`
          );
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

- [ ] **Step 2: Reload and verify the wrap**

Reload `http://localhost:4100/` and scroll to station 04. Expected:
- The first three (or so) lines of the inscription are visibly **narrower** than the lines below them — they start to the right of the illumination, not at the left margin.
- The first line below the illumination's bottom edge flushes back to the left margin at full column width.
- The word `survive` glows amber (from `.torch` span) and pulses with `glowPulse`.

If lines below the illumination still appear narrow: the `collides` calculation is wrong — check that `illTop + illH` correctly reflects where the illumination ends inside the manuscript page. If the accent word doesn't glow: open DevTools, inspect a line element, confirm it has `<span class="torch">survive</span>` as inner HTML.

- [ ] **Step 3: Run smoke test — nothing broken on server side**

```bash
docker compose exec -T app mix test test/agent_mmo_web/controllers/page_controller_test.exs
```

Expected: PASS.

- [ ] **Step 4: Commit**

```bash
git add lib/agent_mmo_web/controllers/page_html/home.html.heex
git commit -m "$(cat <<'EOF'
feat(landing): manuscript body wraps the illumination drop-cap

Per-line maxWidth narrows and shifts right while the current y is within
the illumination's vertical span, then flushes to full column width
below it. Post-layout, the accent word ("survive") is wrapped in a
<span class="torch"> inside whichever materialized line contains it,
preserving the existing glow + pulse styling.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 6: Reflow on font-load and window resize

**Files:**
- Modify: `lib/agent_mmo_web/controllers/page_html/home.html.heex`

Pretext measures text via canvas using the font string it's given. If layout runs before the web fonts have loaded, measurements use the fallback font and break once the real font arrives. Add `document.fonts.ready` gate + a debounced resize listener.

- [ ] **Step 1: Gate the initial layout on fonts**

In the manuscript-verse IIFE, replace the bottom of the function (the line that just says `layoutBody();` followed by `})();`) with:

```javascript
    // Wait for the real fonts before measuring — pretext measures via canvas,
    // and a fallback-font measurement will be wrong once the real font lands.
    if (document.fonts && document.fonts.ready) {
      await document.fonts.ready;
    }
    layoutBody();

    let resizeTimer = null;
    window.addEventListener('resize', () => {
      clearTimeout(resizeTimer);
      resizeTimer = setTimeout(layoutBody, 200);
    });
  })();
```

- [ ] **Step 2: Reload + verify font-ready behavior**

Hard-reload `http://localhost:4100/` (Cmd/Ctrl-Shift-R to bypass cache). Open DevTools Network tab, throttle to "Slow 3G" to exaggerate font load time, reload again. Expected:
- Immediately after HTML loads: station 04 shows the fallback layout (illumination above prose) for a brief moment.
- Once `IBM Plex Mono` + `Cormorant Garamond` arrive: pretext runs, lines snap into wrap position.

- [ ] **Step 3: Verify resize reflow**

Restore normal network. Resize the browser window from ~1400px wide down to ~900px and back up. Expected:
- During the drag: lines stay at their old positions (no reflow per resize tick).
- ~200ms after the last resize event: layout recomputes; lines reflow to new column width. Illumination position stays put; body lines re-wrap with new `maxWidth`.

- [ ] **Step 4: Run smoke test**

```bash
docker compose exec -T app mix test test/agent_mmo_web/controllers/page_controller_test.exs
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/agent_mmo_web/controllers/page_html/home.html.heex
git commit -m "$(cat <<'EOF'
feat(landing): manuscript reflows on fonts-ready and resize

Initial layout waits for document.fonts.ready so pretext measures with
the actual Cormorant Garamond metrics rather than the fallback font.
Window resize triggers a 200ms-debounced re-layout, matching the same
debounce pattern already used by the roguelike background.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 7: Cursor-proximity glow on the illumination

**Files:**
- Modify: `lib/agent_mmo_web/controllers/page_html/home.html.heex`

Tap the page's existing `pointermove` listener to update `--torch-distance` on the manuscript page based on cursor proximity to the illumination's center. The CSS in Task 3 already keys `text-shadow` strength off this property — this task only adds the JS that drives it.

- [ ] **Step 1: Extend the existing pointermove handler**

In the same `<script>` block, find the existing handler (search for `pointermove`):

```javascript
  window.addEventListener('pointermove', (e) => {
    mouseX = e.clientX;
    mouseY = e.clientY;
  });
```

Replace that listener with:

```javascript
  const manuscriptRoot = () => document.querySelector('.manuscript-page[data-pretext-mount]');
  const manuscriptIll  = () => document.querySelector('.manuscript-page[data-pretext-mount] .manuscript-illumination');

  // Cache the illumination center; recomputed on scroll/resize because position changes.
  let illCenter = null;
  function refreshIllCenter() {
    const ill = manuscriptIll();
    if (!ill) { illCenter = null; return; }
    const r = ill.getBoundingClientRect();
    illCenter = { x: r.left + r.width / 2, y: r.top + r.height / 2 };
  }
  refreshIllCenter();
  window.addEventListener('scroll', refreshIllCenter, { passive: true });
  window.addEventListener('resize', refreshIllCenter);

  window.addEventListener('pointermove', (e) => {
    mouseX = e.clientX;
    mouseY = e.clientY;

    if (illCenter) {
      const root = manuscriptRoot();
      if (root) {
        const dx = e.clientX - illCenter.x;
        const dy = e.clientY - illCenter.y;
        const dist = Math.sqrt(dx * dx + dy * dy);
        // 0 when far (>360px), 1 when on top (<60px) — smooth ramp
        const NEAR = 60, FAR = 360;
        let t = 1 - (dist - NEAR) / (FAR - NEAR);
        if (t < 0) t = 0;
        if (t > 1) t = 1;
        root.style.setProperty('--torch-distance', t.toFixed(3));
      }
    }
  });
```

- [ ] **Step 2: Reload + verify cursor glow**

Reload `http://localhost:4100/`. Scroll to station 04. Move the cursor slowly toward the illumination (the ASCII torch). Expected:
- When cursor is across the page (>360px from torch center): illumination flame has its baseline glow only.
- As cursor approaches within ~60px of the torch center: the flame's text-shadow visibly intensifies (brighter, wider radius).
- Reverses smoothly as you pull the cursor away. No layout reflow, no jank — pure paint.

If glow doesn't change: in DevTools, inspect `.manuscript-page`, check the computed style for `--torch-distance` — it should be updating between `0` and `1` as the cursor moves.

- [ ] **Step 3: Run smoke test**

```bash
docker compose exec -T app mix test test/agent_mmo_web/controllers/page_controller_test.exs
```

Expected: PASS.

- [ ] **Step 4: Commit**

```bash
git add lib/agent_mmo_web/controllers/page_html/home.html.heex
git commit -m "$(cat <<'EOF'
feat(landing): illumination glow tracks cursor proximity

Extends the page's pointermove handler to update --torch-distance on
the manuscript page (0 = far, 1 = on top, smooth ramp between 60-360px).
CSS keys the illumination flame's text-shadow off the custom property,
so the torch visibly brightens as the cursor approaches it. Same
plumbing scales to a future torchlight-reading-window per the spec's
v2 hooks.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 8: Mobile (<880px) collapse

**Files:**
- Modify: `lib/agent_mmo_web/controllers/page_html/home.html.heex`

Below 880px the drop-cap collapses inline (`position: static`) and the gloss stacks below. The Task 3 CSS already added the media query — this task verifies the JS path works under that layout (effective obstacle width becomes 0, so `collides` is false for all lines).

- [ ] **Step 1: Verify mobile layout in browser**

Open DevTools, switch to device emulation (375×667 iPhone SE preset, or just resize the viewport below 880px). Reload `http://localhost:4100/`. Scroll to station 04. Expected:
- Illumination renders as a normal block at the top (no absolute positioning).
- A 24px gap, then the body inscription flows beneath it at full column width.
- A 24px gap, then the gloss (if kept) renders below the body, right-aligned in mono.
- No overlap. No clipped text. Pretext is still running — lines are still emitted as `.manuscript-line` divs — but every line gets `maxWidth = columnWidth` and `startX = 0` because `collides` is false (the illumination has `position: static`, so its bounding box reads at its in-flow location, not above the body).

- [ ] **Step 2: Verify desktop layout still works**

Switch back to desktop viewport (≥881px). Reload. Expected: full manuscript wrap layout from Task 5.

- [ ] **Step 3: Run smoke test**

```bash
docker compose exec -T app mix test test/agent_mmo_web/controllers/page_controller_test.exs
```

Expected: PASS.

- [ ] **Step 4: Commit if any tweaks were needed**

If Step 1 revealed layout issues (overlap, clipped text), make corrective tweaks to the `@media (max-width: 880px)` block from Task 3 and commit:

```bash
git add lib/agent_mmo_web/controllers/page_html/home.html.heex
git commit -m "fix(landing): mobile collapse for manuscript verse station

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

If no tweaks were needed: no commit, just note in the implementor's handoff message that Task 8 verified clean.

---

## Task 9: Walk the spec's acceptance criteria

**Files:** none

This is the human verification gate from the spec's "Acceptance criteria" section. Walk each item, record pass/fail/notes. No commit at the end — this task produces a status report only.

- [ ] **AC 1:** Station 04 renders a manuscript page with ASCII illumination top-left and 4–6 lines of inscription prose wrapping its right edge.

Visit `http://localhost:4100/#runes`. Inspect visually.

- [ ] **AC 2:** The first ~3 lines of body prose have a visibly shorter line length than the lines below them.

Same view. Measure line widths in DevTools if it's not visually obvious.

- [ ] **AC 3:** Resizing the window re-flows the prose to fit the new column width (no clipped or overlapping text).

Drag-resize browser between 1400px and 900px. Wait for 200ms debounce; verify layout adapts.

- [ ] **AC 4:** Disabling JS still shows a readable verse — illumination above, prose below in standard block flow.

In DevTools settings: "Disable JavaScript" → reload → scroll to station 04. Both the illumination `<pre>` and the body `<p>` are visible; prose is plain (no per-line layout) but readable; attribution row renders.

- [ ] **AC 5:** `.torch` accent spans inside the body retain their glow/text-shadow.

In normal JS-enabled view, the word `survive` glows amber and pulses.

- [ ] **AC 6:** Cursor proximity to the illumination visibly intensifies its glow.

Move cursor near/far from the torch; verify smooth intensity ramp.

- [ ] **AC 7:** No other station's appearance or behavior changes.

Scroll through stations 01 (Threshold), 02 (Doorway), 03 (Wager), 05 (Flame), 06 (Invitation). All should look identical to pre-change.

- [ ] **AC 8:** No new HTTP routes, no new assets in `priv/static/`, no esbuild config changes.

```bash
git diff main --stat
ls priv/static/assets/ 2>/dev/null   # should error: directory doesn't exist
```

Diff should show changes only in `lib/agent_mmo_web/controllers/page_html/home.html.heex` and `test/agent_mmo_web/controllers/page_controller_test.exs`. No new files under `priv/static/assets/`.

- [ ] **Final step: Report status to user**

Summarize: which acceptance criteria passed cleanly, which needed minor tweaks during the walk, any open issues to follow up on. No commit.

---

## Out-of-scope follow-ups (not in this plan)

These are spec'd v2 hooks — do not implement as part of this plan.

- **Torchlight reading window (Option C)** — extend `--torch-distance` plumbing to per-line `maxWidth = chord(cursor, lineY)` for a circular reveal. New plan when ready.
- **Multi-station pretext.** Apply pretext to another station (e.g. expanded inscription on the doorway or threshold). New plan when ready.
- **Rich-inline accents.** Replace the post-process accent matcher with pretext's `prepareRichInline` for multi-accent inscriptions or per-accent font shifts. New plan when ready.

---

## Self-review notes (implementor: read before starting)

1. **Spec coverage:** Every "In scope" bullet from the spec maps to a task (markup → T3, CSS → T3, ESM CDN import → T4, DOM render → T4, illumination drop-cap → T3+T5, body wrap → T5, attribution preserved → T3, optional gloss → T3, cursor-proximity glow → T7, fonts-ready/resize → T6, mobile collapse → T8). Every "Out of scope" item is explicitly absent from all tasks.

2. **API signatures verified:** `prepareWithSegments(text, font, options?)`, `layoutNextLineRange(prepared, cursor, maxWidth)`, `materializeLineRange(prepared, line)` — all confirmed against `src/layout.ts` of `@chenglou/pretext@0.0.7`. Initial cursor is `{ segmentIndex: 0, graphemeIndex: 0 }` per the README's flow-around-image example.

3. **Accent-word post-process is a deliberate simplification.** The README's example uses single-segment plain text; rich-inline would be the "fully correct" path for styled accents, but it's a heavier API surface for a single accent word in a single sentence. This plan post-wraps `survive` in `<span class="torch">` after pretext lays the line. If the inscription gains multiple accents or per-accent font shifts, swap to `prepareRichInline` per the v2 hook above.

4. **Failure modes intentionally silent.** Pretext CDN unreachable, `prepareWithSegments` throws, or `import` rejects → the IIFE's `try`/`catch` swallows it, `.pretext-active` never gets added, and the original `<p class="manuscript-body">` stays visible. That's the intended fallback per the spec.
