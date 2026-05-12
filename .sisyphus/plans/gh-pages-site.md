# AI Model Price Tracker — GitHub Pages Site

## TL;DR

> **Quick Summary**: Add a lightweight GitHub Pages static site to the ai-model-tracker repo. Phase 1 makes Nim emit versioned JSON data files. Phase 2 adds a vanilla HTML+JS frontend in `docs/` with sortable/filterable table, uPlot price history charts, and provider filtering — all under 50KB gzipped. Inspired by `simonw/llm-prices`.
>
> **Deliverables**:
> - `docs/data/current.json` — versioned current-model registry
> - `docs/data/history.json` — per-model price history (backfill + incremental)
> - `docs/index.html` — dark-theme static site with all model data
> - `docs/assets/app.js` — fetching, table, charts, state, theme
> - `docs/assets/style.css` — dark theme CSS
> - `docs/CNAME` — custom domain config
> - Updated `.github/workflows/update.yml` — `fetch-depth: 0`, concurrency, jq validation
> - Backfill script: `scripts/backfill-history.nim`
>
> **Estimated Effort**: Medium
> **Parallel Execution**: YES — 4 waves
> **Critical Path**: JSON schema → Nim JSON emission → frontend → CI polish

---

## Context

### Original Request
Build a high-quality-but-lightweight GitHub Pages site for the AI model price tracker. Sortable/filterable table of 367 models, per-model price history charts, provider pages. Dark theme. No build step, no framework — vanilla HTML+JS. Inspired by `simonw/llm-prices`.

### Interview Summary
**Key Decisions**:
- **Architecture**: Vanilla HTML + JS, single `index.html`, zero build step, `docs/` folder on `main` branch
- **Chart library**: uPlot (~15KB gzip) — best-in-class time-series, built-in crosshair/zoom/legend
- **Table**: Vanilla JS sortable/filterable (~40 lines, patterned after simonw/llm-prices)
- **Theme**: Dark by default, CSS variables + `prefers-color-scheme` + manual toggle with localStorage
- **History**: One-time backfill from git log → incremental append on each CI run
- **Chart scale**: Log scale default (prices span 4 orders of magnitude)
- **Mobile**: Responsive column hiding (model/name/price visible, less important columns hidden)
- **Domain**: Custom domain via Cloudflare (spagserv.uk) — recommended subdomain: `models.spagserv.uk`
- **Currency**: `$/Mtok` (per million tokens) repo-wide
- **Data**: Nim emits JSON additively — no breakage of existing markdown output

**Metis Review**:

**Critical gaps resolved**:
- History generation: One-time backfill script (`scripts/backfill-history.nim`) extracts 21 snapshots from git log → `history.json`. CI then appends incrementally.
- CI needs `actions/checkout@v4` with `fetch-depth: 0` for git log mining on backfill (and `fetch-depth: 1` for normal CI runs once backfilled).
- Custom domain: `docs/CNAME` file + Cloudflare DNS CNAME to `mrspaghatti.github.io`.

**Guardrails applied** (see Must NOT):
- No build step, npm, or package.json for frontend
- No JS framework (React/Vue/Svelte/Alpine/htmx)
- No CSS framework (Tailwind, Bootstrap)
- No chart libraries beyond uPlot
- No icon libraries — inline SVG only, max 5 icons
- No web fonts — system stack only
- No animations beyond: theme toggle fade (≤150ms), table sort indicator
- No per-model HTML pages in v1
- No image assets (logos, screenshots) in v1
- No modification of existing markdown output — JSON emission is additive only

---

## Work Objectives

### Core Objective
Add a versioned JSON data pipeline and lightweight GitHub Pages frontend to the existing ai-model-tracker Nim generator and CI workflow.

### Definition of Done
- [ ] `curl https://models.spagserv.uk/` returns 200 with `<title>` matching `*Model Price*`
- [ ] `curl https://models.spagserv.uk/data/current.json` returns 200, `Content-Type: application/json`, valid versioned schema, ≥360 models
- [ ] Playwright: table renders 360+ rows within 2s of page load
- [ ] Playwright: sort by price works (ascending/descending)
- [ ] Playwright: filter by "claude" shows only matching rows (case-insensitive)
- [ ] Playwright: click row → uPlot chart renders with non-zero dimensions
- [ ] Playwright: toggle theme → localStorage persists across reload
- [ ] Playwright: `#provider=anthropic` URL hash pre-filters table
- [ ] `wc -c docs/index.html docs/assets/style.css docs/assets/app.js | tail -1` → gzipped total < 50KB
- [ ] CI run with no API changes does NOT create a commit (`git diff --staged --quiet` exits 0)
- [ ] CI run with API changes commits both markdown AND JSON atomically

### Must Have
- Versioned JSON schema (`version: 1`, `generated_at`, `models` array)
- Per-model price history with `from_date`/`to_date`/`prompt_price`/`completion_price`
- Dark theme with `prefers-color-scheme` default + manual toggle + localStorage
- uPlot line chart: log-scale Y, prompt+completion lines, hover tooltip
- URL hash state for shareable filters (`#provider=anthropic&search=gpt`)
- `$`/Mtok display consistently
- `<noscript>` fallback linking to existing markdown pages
- JSON parsing wrapped in try/catch with visible error UI on failure

### Must NOT Have (Guardrails)
- NO build step, npm, package.json for the frontend
- NO JS framework of any kind
- NO CSS framework
- NO chart libraries beyond uPlot
- NO icon libraries — inline SVG only, max 5
- NO web fonts — system stack only
- NO animations beyond theme fade (≤150ms) and sort indicator
- NO per-model HTML pages in v1
- NO image assets (logos, screenshots) in v1
- NO modification of existing markdown output
- NO service worker, PWA manifest, or offline mode
- NO analytics, user accounts, or preference sync
- NO side-by-side model comparison in v1
- NO cost calculator in v1
- NO benchmark scores or non-OpenRouter data
- NO email/RSS alerts in v1

---

## Verification Strategy

> **ZERO HUMAN INTERVENTION** — ALL verification is agent-executed.

### Test Decision
- **Infrastructure exists**: NO (no test framework in place)
- **Automated tests**: YES (tests-after, via `jq` for data + Playwright for frontend)
- **Framework**: `jq` (data validation) + Playwright (frontend E2E) + `curl` (headers/perf)
- **Agent-Executed QA**: MANDATORY for all tasks

### QA Policy
Every task MUST include agent-executable QA scenarios. Evidence saved to `.sisyphus/evidence/task-{N}-{scenario-slug}.{ext}`.

- **Data layer**: Bash with `curl` + `jq` — fetch JSON, assert schema, count models, validate types
- **Frontend**: Playwright — navigate, interact, assert DOM, screenshot
- **Perf**: `wc -c` and `gzip -c | wc -c` for size budgets
- **CI**: Simulate `git diff --staged --quiet` to verify no-commit-on-no-change behavior

---

## Execution Strategy

### Parallel Execution Waves

```
Wave 1 (Start Immediately — foundation, 5 tasks):
├── Task 1: JSON schema definition (types.nim additions) [quick]
├── Task 2: Backfill history script (scripts/backfill-history.nim) [quick]
├── Task 3: index.html skeleton + noscript fallback [quick]
├── Task 4: style.css — dark theme, responsive, system stack [visual-engineering]
└── Task 5: CNAME file + docs directory setup [quick]

Wave 2 (After Wave 1 — core pipeline, 3 tasks):
├── Task 6: Nim emits current.json (additive, no markdown breakage) [unspecified-high]
├── Task 7: Nim emits history.json (incremental append) [unspecified-high]
└── Task 8: CI workflow update (fetch-depth, concurrency, jq validation) [quick]

Wave 3 (After Wave 2 — frontend logic, 4 tasks):
├── Task 9: app.js — data fetching + error handling + state [unspecified-high]
├── Task 10: app.js — sortable/filterable table + URL hash [unspecified-high]
├── Task 11: app.js — uPlot price history chart [visual-engineering]
└── Task 12: app.js — theme toggle + provider page view [unspecified-high]

Wave 4 (After Wave 3 — integration + polish, 3 tasks):
├── Task 13: Custom domain DNS setup (Cloudflare CNAME) [quick]
├── Task 14: CI smoke tests (curl, jq, Playwright) [deep]
└── Task 15: Final integration — backfill history, deploy, verify [deep]

Critical Path: Task 1 → Task 6 → Task 9 → Task 11 → Task 14
Parallel Speedup: ~60% faster than sequential
```

---

## TODOs

- [x] 1. **Define versioned JSON schema in types.nim**

  **What to do**:
  - Add `JsonModel*` and `JsonHistoryEntry*` object types to `src/types.nim`
  - `JsonModel`: `id`, `name`, `provider` (extracted from `id.split("/")[0]`), `context_length`, `pricing` (nested: `prompt`, `completion`, `image`, `request`, `web_search`, `input_cache_read`), `created_at`, `is_free`, `is_moderated`, `modalities`
  - `JsonHistoryEntry`: `model_id`, `from_date` (ISO 8601), `to_date` (nullable = ongoing), `prompt_price`, `completion_price`
  - `JsonCurrentRoot`: `version: 1`, `generated_at` (ISO 8601 UTC), `models: seq[JsonModel]`
  - `JsonHistoryRoot`: `version: 1`, `generated_at`, `entries: seq[JsonHistoryEntry]`
  - All prices as `float` (already parsed from string in parser.nim)
  - All prices in per-token units (same as OpenRouter API) — frontend converts to $/Mtok

  **Must NOT do**:
  - Do NOT modify existing `ModelRow` or `OpenRouterModel` types
  - Do NOT add fields not present in the OpenRouter API response

  **Recommended Agent Profile**:
  - **Category**: `quick`
    - Reason: Single file change, well-defined types, no logic
  - **Skills**: `[]`
  - **Skills Evaluated but Omitted**: N/A

  **Parallelization**:
  - **Can Run In Parallel**: YES
  - **Parallel Group**: Wave 1 (with Tasks 2, 3, 4, 5)
  - **Blocks**: Task 6, Task 7
  - **Blocked By**: None

  **References**:
  - `src/types.nim:1-47` — Existing type definitions to follow the same pattern
  - `src/parser.nim:48-77` — `toModelRow` shows how pricing is extracted
  - `simonw/llm-prices` data schema: https://github.com/simonw/llm-prices/blob/main/scripts/build.py — reference for `price_history` array pattern

  **Acceptance Criteria**:
  - [ ] `nim c src/types.nim` compiles without errors
  - [ ] New types are exported (`*`) and usable from other modules

  **QA Scenarios**:
  ```
  Scenario: Types compile and export correctly
    Tool: Bash
    Steps:
      1. Create a small test file that imports types and constructs a JsonModel
      2. nim c -r test_types.nim
    Expected Result: Compiles and runs without error
    Evidence: .sisyphus/evidence/task-1-types-compile.txt
  ```

  **Commit**: YES (groups with 2-5)
  - Message: `feat(schema): define versioned JSON data types`
  - Files: `src/types.nim`

- [x] 2. **Write backfill history script (scripts/backfill-history.nim)**

  **What to do**:
  - Create `scripts/backfill-history.nim` — a one-time script, NOT part of CI
  - Walk `git log` for `data/registry.json` commits (use `git log --format=%H %ct -- data/registry.json`)
  - For each commit: `git show <sha>:data/registry.json`, parse JSON, extract pricing for each model
  - Build `history.json` with per-model entries: each snapshot becomes a `from_date` entry, `to_date` is the next snapshot's timestamp (or `null` for latest)
  - Write output to `docs/data/history.json`
  - Handle: models that appear mid-history (first snapshot is their `from_date`), models that disappear (last snapshot's `to_date` = that snapshot's timestamp)
  - Use `std/osproc` for git commands, `std/json` for parsing

  **Must NOT do**:
  - Do NOT integrate into CI — this is a one-time run
  - Do NOT modify any existing source files

  **Recommended Agent Profile**:
  - **Category**: `quick`
    - Reason: Single script, well-defined input/output, one-time use
  - **Skills**: `[]`
  - **Skills Evaluated but Omitted**: N/A

  **Parallelization**:
  - **Can Run In Parallel**: YES
  - **Parallel Group**: Wave 1 (with Tasks 1, 3, 4, 5)
  - **Blocks**: Task 7 (needs history.json format defined)
  - **Blocked By**: Task 1 (needs JsonHistoryEntry type)

  **References**:
  - `src/fetcher.nim` — Pattern for file I/O in Nim
  - `src/parser.nim:126-148` — Pattern for parsing registry JSON
  - `data/registry.json` — Current snapshot format
  - `git log --oneline -- data/registry.json` — Shows 21 historical commits

  **Acceptance Criteria**:
  - [ ] `nim c scripts/backfill-history.nim` compiles
  - [ ] Running it produces `docs/data/history.json` with entries for all 21 snapshots
  - [ ] `jq '.entries | length' docs/data/history.json` > 0
  - [ ] Every model in current registry has at least one history entry

  **QA Scenarios**:
  ```
  Scenario: Backfill produces valid history.json
    Tool: Bash
    Preconditions: scripts/backfill-history.nim exists and compiles
    Steps:
      1. nim c -r scripts/backfill-history.nim
      2. jq '.version' docs/data/history.json
      3. jq '.entries | length' docs/data/history.json
      4. jq '.entries[0] | has("model_id") and has("from_date") and has("prompt_price")' docs/data/history.json
    Expected Result: version=1, entries > 0, each entry has required fields
    Evidence: .sisyphus/evidence/task-2-backfill-valid.txt
  ```

  **Commit**: YES (groups with 1, 3, 4, 5)
  - Message: `feat(schema): define versioned JSON data types`
  - Files: `scripts/backfill-history.nim`

- [x] 3. **Create index.html skeleton with noscript fallback**

  **What to do**:
  - Create `docs/index.html` — the single-page frontend
  - HTML5 doctype, `<meta charset="utf-8">`, `<meta name="viewport" content="width=device-width, initial-scale=1">`
  - `<title>AI Model Price Tracker</title>`
  - Link to `assets/style.css` and `assets/app.js` (defer)
  - `<body>` with:
    - `<header>`: site title, last-updated timestamp placeholder, theme toggle button
    - `<main>`: search input, provider filter dropdown, table container, chart container
    - `<footer>`: link to GitHub repo, link to markdown pages
  - `<noscript>` block: "JavaScript is required for the interactive site. View the [static markdown pages](../FREE_MODELS.md) instead."
  - All interactive elements have `id` attributes for JS hooks
  - No inline styles, no JS in HTML

  **Must NOT do**:
  - Do NOT add any JS or CSS in the HTML file
  - Do NOT add any external CDN links
  - Do NOT add analytics, tracking, or third-party resources

  **Recommended Agent Profile**:
  - **Category**: `quick`
    - Reason: Single HTML file, no logic, pure structure
  - **Skills**: `[]`
  - **Skills Evaluated but Omitted**: N/A

  **Parallelization**:
  - **Can Run In Parallel**: YES
  - **Parallel Group**: Wave 1 (with Tasks 1, 2, 4, 5)
  - **Blocks**: Tasks 9-12 (frontend JS)
  - **Blocked By**: None

  **References**:
  - `simonw/llm-prices/index.html` — Reference for single-file structure: https://raw.githubusercontent.com/simonw/llm-prices/main/index.html
  - `docs/` directory — Will be created as part of this task

  **Acceptance Criteria**:
  - [ ] File exists at `docs/index.html`
  - [ ] Valid HTML5 (validate with `tidy` or similar)
  - [ ] `<noscript>` block present with links to markdown pages
  - [ ] No external resources (CDN, fonts, etc.)

  **QA Scenarios**:
  ```
  Scenario: HTML is valid and has required elements
    Tool: Bash
    Steps:
      1. grep '<!DOCTYPE html>' docs/index.html
      2. grep '<noscript>' docs/index.html
      3. grep 'FREE_MODELS.md' docs/index.html
      4. grep -c 'src=' docs/index.html  # should be 0 (no inline scripts)
      5. grep -c 'href=' docs/index.html | grep -v assets/  # only CSS + external links
    Expected Result: DOCTYPE present, noscript present, no inline scripts
    Evidence: .sisyphus/evidence/task-3-html-valid.txt
  ```

  **Commit**: YES (groups with 1, 2, 4, 5)
  - Message: `feat(schema): define versioned JSON data types`
  - Files: `docs/index.html`

- [x] 4. **Create dark theme CSS (docs/assets/style.css)**

  **What to do**:
  - Create `docs/assets/style.css`
  - CSS custom properties on `:root` for dark theme (GitHub's dark colors: `--bg: #0d1117`, `--bg-alt: #161b22`, `--fg: #e6edf3`, `--fg-muted: #8b949e`, `--border: #30363d`, `--accent: #58a6ff`, `--accent-green: #3fb950`, `--accent-red: #f85149`)
  - Light theme via `[data-theme="light"]` overrides: `--bg: #ffffff`, `--fg: #1f2328`, etc.
  - `@media (prefers-color-scheme: light)` applies light vars as default
  - Responsive table: `overflow-x: auto` on mobile, hide columns with class `hide-mobile` below 768px
  - uPlot dark theme overrides (target `.uplot` class selectors)
  - System font stack: `-apple-system, BlinkMacSystemFont, "Segoe UI", Noto Sans, Helvetica, Arial, sans-serif`
  - Monospace for model IDs: `ui-monospace, SFMono-Regular, "SF Mono", Menlo, Consolas, monospace`
  - No animations except: theme toggle `transition: background-color 150ms`, sort indicator `transition: opacity 100ms`
  - Max content width: 1400px, centered
  - Sticky header on scroll
  - Search input styled as dark input field
  - Table: striped rows (`:nth-child(even)`), hover highlight, sortable column headers with arrow indicators
  - Chart container: responsive, min-height 400px

  **Must NOT do**:
  - Do NOT use any CSS framework
  - Do NOT use `@import`
  - Do NOT use web fonts (`@font-face`)
  - Do NOT add animations beyond the allowed list

  **Recommended Agent Profile**:
  - **Category**: `visual-engineering`
    - Reason: UI/UX design, dark theme, responsive layout
  - **Skills**: `[]`
  - **Skills Evaluated but Omitted**: N/A

  **Parallelization**:
  - **Can Run In Parallel**: YES
  - **Parallel Group**: Wave 1 (with Tasks 1, 2, 3, 5)
  - **Blocks**: Tasks 9-12 (frontend JS relies on CSS classes)
  - **Blocked By**: None (but should coordinate class names with Task 3's HTML)

  **References**:
  - GitHub's Primer dark theme: `https://github.com/primer/primitives/blob/main/data/colors/themes/dark_dimmed.json`
  - `simonw/llm-prices` CSS (embedded in index.html)
  - uPlot CSS theming: `https://github.com/leeoniya/uPlot/tree/master/dist`

  **Acceptance Criteria**:
  - [ ] File exists, no CSS framework imports
  - [ ] `<link rel="stylesheet" href="assets/style.css">` in index.html works
  - [ ] Dark theme renders correctly (verify via screenshot)
  - [ ] Light theme toggle works
  - [ ] Table is scrollable on mobile viewport (375px width)
  - [ ] Total CSS gzipped < 15KB

  **QA Scenarios**:
  ```
  Scenario: CSS loads and themes apply
    Tool: Bash
    Steps:
      1. wc -c docs/assets/style.css
      2. gzip -c docs/assets/style.css | wc -c
      3. grep -c '@import' docs/assets/style.css  # should be 0
      4. grep -c '@font-face' docs/assets/style.css  # should be 0
    Expected Result: Filesize reasonable, no imports, no web fonts
    Evidence: .sisyphus/evidence/task-4-css-stats.txt
  ```

  **Commit**: YES (groups with 1-5)
  - Message: `feat(schema): define versioned JSON data types`
  - Files: `docs/assets/style.css`

- [x] 5. **Setup docs directory and CNAME**

  **What to do**:
  - Ensure `docs/` directory exists
  - Create `docs/CNAME` with content: `models.spagserv.uk`
  - Create `docs/assets/` directory (for CSS and JS)
  - Create `docs/data/` directory (for JSON files)
  - Add `docs/data/` to `.gitignore` if not already tracked (it should be tracked)
  - Verify GitHub Pages is configured in repo settings (or note that it's set manually)

  **Must NOT do**:
  - Do NOT add any actual data files in this task

  **Recommended Agent Profile**:
  - **Category**: `quick`
    - Reason: Trivial directory/file setup
  - **Skills**: `[]`

  **Parallelization**:
  - **Can Run In Parallel**: YES
  - **Parallel Group**: Wave 1 (with Tasks 1-4)
  - **Blocks**: Tasks 6-7 (need docs/data/ to exist)
  - **Blocked By**: None

  **Acceptance Criteria**:
  - [ ] `docs/CNAME` exists with correct content
  - [ ] `docs/assets/` exists
  - [ ] `docs/data/` exists

  **QA Scenarios**:
  ```
  Scenario: Directories and CNAME exist
    Tool: Bash
    Steps:
      1. test -d docs/assets && test -d docs/data
      2. cat docs/CNAME
    Expected Result: directories exist, CNAME = "models.spagserv.uk"
    Evidence: .sisyphus/evidence/task-5-dirs.txt
  ```

  **Commit**: YES (groups with 1-5)
  - Message: `feat(schema): define versioned JSON data types`
  - Files: `docs/CNAME`, `docs/assets/.gitkeep`, `docs/data/.gitkeep`

- [ ] 6. **Nim generator emits current.json**

  **What to do**:
  - Add a new proc `generateCurrentJson(rows: seq[ModelRow]): string` to `src/formatter.nim`
  - Converts `seq[ModelRow]` to JSON matching the `JsonCurrentRoot` schema
  - Provider extracted from model ID: `model.id.split("/")[0]`
  - Prices kept in per-token units (same as OpenRouter API)
  - All model IDs included (free, paid, unknown-pricing)
  - Output path: `docs/data/current.json`
  - Call from `main.nim` alongside existing markdown generation
  - Wrap in try/except with clear error messages

  **Must NOT do**:
  - Do NOT modify existing markdown generation functions
  - Do NOT remove or change existing output files
  - Do NOT use a JSON library beyond `std/json`

  **Recommended Agent Profile**:
  - **Category**: `unspecified-high`
    - Reason: JSON serialization logic, additive changes to existing modules
  - **Skills**: `[]`

  **Parallelization**:
  - **Can Run In Parallel**: NO
  - **Parallel Group**: Wave 2 (sequential)
  - **Blocks**: Task 7, Tasks 9-12 (frontend needs current.json)
  - **Blocked By**: Task 1 (needs JsonModel type)

  **References**:
  - `src/types.nim` — JsonModel, JsonCurrentRoot types (from Task 1)
  - `src/formatter.nim:85-91` — `generateRowsTable` pattern for iterating rows
  - `src/main.nim:65-83` — Entry point, where to add the call

  **Acceptance Criteria**:
  - [ ] `nim c src/main.nim` compiles
  - [ ] Running generates `docs/data/current.json`
  - [ ] `jq '.version' docs/data/current.json` == 1
  - [ ] `jq '.models | length' docs/data/current.json` >= 360
  - [ ] `jq '.models[0] | has("id") and has("provider") and has("pricing")' docs/data/current.json` == true
  - [ ] `wc -c docs/data/current.json` < 204800 (200KB budget)

  **QA Scenarios**:
  ```
  Scenario: current.json is valid and complete
    Tool: Bash
    Preconditions: ./src/main has been compiled
    Steps:
      1. ./src/main
      2. jq '.version' docs/data/current.json
      3. jq '.models | length' docs/data/current.json
      4. jq '.models[:3][] | {id: .id, provider: .provider, has_pricing: (.pricing | has("prompt"))}' docs/data/current.json
      5. wc -c docs/data/current.json
    Expected Result: version=1, >=360 models, every model has pricing
    Evidence: .sisyphus/evidence/task-6-current-json.txt
  ```

  **Commit**: YES (groups with 7)
  - Message: `feat(generator): emit current.json and history.json`
  - Files: `src/formatter.nim`, `src/main.nim`

- [ ] 7. **Nim generator emits history.json (incremental)**

  **What to do**:
  - Add a proc in `src/formatter.nim` (or new module `src/historian.nim`) for incremental history updates
  - On each CI run:
    1. Read existing `docs/data/history.json` (if it exists)
    2. Get current snapshot's pricing data from parsed rows
    3. For each model: compare current pricing with last history entry
    4. If changed: close previous entry (set `to_date` to previous run timestamp), add new entry (set `from_date` to previous run timestamp, `to_date` = null)
    5. If new model (not in history): add entry with `from_date` = current timestamp, `to_date` = null
    6. If model disappeared from API: close last entry with `to_date` = current timestamp
  - Use `std/json` for all JSON operations
  - Output to `docs/data/history.json`
  - Guard: if `history.json` doesn't exist (first run post-backfill), warn and skip (backfill script handles bootstrapping)

  **Must NOT do**:
  - Do NOT walk git log in CI (that's the backfill script's job)
  - Do NOT fail CI if history.json is missing (backfill must be run first)

  **Recommended Agent Profile**:
  - **Category**: `unspecified-high`
    - Reason: Stateful JSON merging logic, edge cases (new/disappeared models)
  - **Skills**: `[]`

  **Parallelization**:
  - **Can Run In Parallel**: NO
  - **Parallel Group**: Wave 2 (sequential)
  - **Blocks**: Task 11 (chart needs history data)
  - **Blocked By**: Task 1 (types), Task 6 (current.json structure), Task 2 (history format)

  **References**:
  - `docs/data/history.json` format — defined by Task 2's output
  - `src/parser.nim:48-77` — `toModelRow` shows model-to-row conversion
  - `src/main.nim:65-83` — Where to add history.json write

  **Acceptance Criteria**:
  - [ ] `nim c src/main.nim` compiles
  - [ ] First run with existing history.json = append works
  - [ ] Second run with no price changes = no duplicate entries
  - [ ] `jq '.entries[0] | has("model_id") and has("from_date")' docs/data/history.json` == true

  **QA Scenarios**:
  ```
  Scenario: History appends correctly without duplicates
    Tool: Bash
    Preconditions: history.json exists from backfill
    Steps:
      1. cp docs/data/history.json docs/data/history.json.bak
      2. ./src/main  # run generator (no API change expected in test)
      3. diff docs/data/history.json docs/data/history.json.bak || echo "HISTORY_CHANGED"
      4. jq '.entries | length' docs/data/history.json
    Expected Result: Either no change (diff exits 0) or valid append
    Evidence: .sisyphus/evidence/task-7-history-append.txt
  ```

  **Commit**: YES (groups with 6)
  - Message: `feat(generator): emit current.json and history.json`
  - Files: `src/formatter.nim` (or `src/historian.nim`), `src/main.nim`

- [ ] 8. **CI workflow update**

  **What to do**:
  - Update `.github/workflows/update.yml`:
    - Add `fetch-depth: 0` to `actions/checkout@v4` (needed for git log backfill in Task 2)
    - Add `concurrency:` group to prevent race conditions:
      ```yaml
      concurrency:
        group: update-data
        cancel-in-progress: true
      ```
    - Add `jq` validation step after `./src/main`:
      ```yaml
      - name: Validate JSON output
        run: |
          jq '.models | length' docs/data/current.json | xargs -I{} test {} -ge 300
          jq '.entries | length' docs/data/history.json | xargs -I{} test {} -ge 1
          test $(stat -c%s docs/data/current.json) -lt 204800
      ```
    - Update `git add` to include `docs/data/` files
    - Add comment documenting the custom domain setup requirement

  **Must NOT do**:
  - Do NOT break the existing markdown generation workflow
  - Do NOT add node/npm steps

  **Recommended Agent Profile**:
  - **Category**: `quick`
    - Reason: YAML changes, clear additions
  - **Skills**: `[]`

  **Parallelization**:
  - **Can Run In Parallel**: YES (with Tasks 6, 7)
  - **Parallel Group**: Wave 2 (with Tasks 6, 7)
  - **Blocks**: Task 14 (smoke tests need CI to run)
  - **Blocked By**: Tasks 6, 7 (needs JSON output to validate)

  **References**:
  - `.github/workflows/update.yml:1-23` — Current workflow to modify
  - `simonw/llm-prices/.github/workflows` — Pattern for git scraping CI

  **Acceptance Criteria**:
  - [ ] YAML is valid (`yamllint` or GitHub parser)
  - [ ] `concurrency` group is configured
  - [ ] `fetch-depth: 0` is set on checkout
  - [ ] jq validation step exists
  - [ ] `docs/data/` files are included in git add

  **QA Scenarios**:
  ```
  Scenario: Workflow YAML is valid
    Tool: Bash
    Steps:
      1. python3 -c "import yaml; yaml.safe_load(open('.github/workflows/update.yml'))"
      2. grep 'fetch-depth: 0' .github/workflows/update.yml
      3. grep 'concurrency:' .github/workflows/update.yml
      4. grep 'jq' .github/workflows/update.yml
    Expected Result: YAML valid, fetch-depth=0 present, concurrency present, jq validation present
    Evidence: .sisyphus/evidence/task-8-workflow-valid.txt
  ```

  **Commit**: YES (groups with 6, 7)
  - Message: `ci(workflow): fetch-depth 0, concurrency, jq validation`
  - Files: `.github/workflows/update.yml`

- [ ] 9. **app.js — data fetching, error handling, state management**

  **What to do**:
  - Create `docs/assets/app.js`
  - On page load: `fetch('./data/current.json')` and `fetch('./data/history.json')`
  - Wrap all JSON parsing in try/catch
  - On fetch failure: show inline error message in the table container ("Failed to load model data. The [static markdown pages](../FREE_MODELS.md) are always available.")
  - Store parsed data in module-level variables: `let models = [], history = []`
  - Parse `generated_at` timestamp and display in header as "Last updated: May 11, 2026 02:29 UTC"
  - Expose a simple state object: `{ provider: null, search: '', sortCol: 'contextPerCent', sortDir: 'desc', selectedModel: null }`
  - Read initial state from `window.location.hash` on load
  - On state change: update URL hash, re-render table
  - `popstate` event listener to handle browser back/forward

  **Must NOT do**:
  - Do NOT use any JS framework or library
  - Do NOT use `eval()` or `new Function()`
  - Do NOT add any third-party code

  **Recommended Agent Profile**:
  - **Category**: `unspecified-high`
    - Reason: Core application logic, state management, error handling
  - **Skills**: `[]`

  **Parallelization**:
  - **Can Run In Parallel**: NO (sequential within Wave 3)
  - **Parallel Group**: Wave 3 (sequential with 10, 11, 12)
  - **Blocks**: Tasks 10, 11, 12
  - **Blocked By**: Tasks 3, 4 (HTML + CSS structure), Task 6 (current.json format)

  **References**:
  - `simonw/llm-prices/index.html` — URL hash state pattern, fetch pattern
  - `docs/data/current.json` — Data format to consume
  - `docs/data/history.json` — Data format to consume

  **Acceptance Criteria**:
  - [ ] File exists, no imports/requires
  - [ ] Page loads without console errors
  - [ ] Error message shown when JSON files are missing
  - [ ] URL hash updates on state change
  - [ ] Browser back/forward restores state

  **QA Scenarios**:
  ```
  Scenario: Data loads and state works
    Tool: Playwright
    Steps:
      1. Navigate to index.html
      2. Wait for table to render (querySelectorAll('tbody tr').length > 0)
      3. Check no console errors (page.on('console'))
      4. Check URL hash is set
      5. Navigate to index.html#provider=nonexistent
      6. Check error message is shown
    Expected Result: Table renders, no errors, hash state works
    Evidence: .sisyphus/evidence/task-9-data-load.txt
  ```

  **Commit**: YES (groups with 10-12)
  - Message: `feat(site): static frontend with table, charts, theme`
  - Files: `docs/assets/app.js`

- [ ] 10. **app.js — sortable/filterable table + URL hash**

  **What to do**:
  - Add table rendering function: `renderTable(models, state)`
  - Generate `<thead>` with sortable column headers (click to sort, click again to reverse)
  - Columns: Model ID, Name, Provider, Context, Prompt ($/Mtok), Completion ($/Mtok), Request ($/req), Context/Cent, Moderated
  - Sort: `models.sort((a, b) => state.sortDir === 'asc' ? a[col] - b[col] : b[col] - a[col])`
  - Filter by search text: case-insensitive substring match on id + name + provider
  - Filter by provider: exact match on provider field
  - Re-render `<tbody>` on every state change (innerHTML = rows.join(''))
  - Format prices as `$/Mtok`: `(price * 1_000_000).toFixed(4)`
  - Format context: `(n).toLocaleString()`
  - Format context/cent: if Infinity show "∞", if -Infinity show "N/A"
  - Click on a row → set `state.selectedModel`, trigger chart render
  - Highlight selected row with CSS class
  - URL hash format: `#provider=anthropic&search=claude&sort=price&dir=asc&model=anthropic/claude-3.5-sonnet`

  **Must NOT do**:
  - Do NOT use any table library
  - Do NOT use innerHTML with unsanitized data (escape model IDs for HTML)

  **Recommended Agent Profile**:
  - **Category**: `unspecified-high`
    - Reason: Table rendering, sorting, filtering logic
  - **Skills**: `[]`

  **Parallelization**:
  - **Can Run In Parallel**: NO (sequential within Wave 3)
  - **Parallel Group**: Wave 3 (sequential with 9, 11, 12)
  - **Blocks**: None (table is independent of chart)
  - **Blocked By**: Task 9 (needs data + state)

  **References**:
  - `simonw/llm-prices/index.html` — Sortable table pattern, URL hash format
  - `docs/assets/style.css` — Table CSS classes to use

  **Acceptance Criteria**:
  - [ ] Table renders 360+ rows
  - [ ] Click column header → sorts ascending, click again → descending
  - [ ] Type "claude" in search → only matching rows visible
  - [ ] Select provider from dropdown → only that provider's rows visible
  - [ ] Click row → row is highlighted, URL hash includes model ID
  - [ ] Load page with `#provider=anthropic` → pre-filtered

  **QA Scenarios**:
  ```
  Scenario: Table sort, filter, and selection work
    Tool: Playwright
    Steps:
      1. Navigate to index.html
      2. Click first sortable column header
      3. Check first row value <= second row value
      4. Click again, check first row value >= second row value
      5. Type "claude" in search input
      6. Check all visible rows contain "claude" (case-insensitive)
      7. Click a row
      8. Check URL hash contains the model ID
    Expected Result: Sort, filter, selection all work
    Evidence: .sisyphus/evidence/task-10-table.txt
  ```

  **Commit**: YES (groups with 9, 11, 12)
  - Message: `feat(site): static frontend with table, charts, theme`
  - Files: `docs/assets/app.js`

- [ ] 11. **app.js — uPlot price history chart**

  **What to do**:
  - Add uPlot via CDN: `<script src="https://cdn.jsdelivr.net/npm/uplot@1.6.30/dist/uPlot.iife.min.js">` in index.html
  - When a model is selected: find its history entries, build uPlot data
  - uPlot data format: `[timestamps[], promptPrices[], completionPrices[]]`
  - Timestamps in seconds (uPlot expects seconds)
  - Log scale Y-axis: `scales: { y: { distr: 3 } }` (uPlot's log distribution)
  - Two series: prompt price (blue, `#58a6ff`) and completion price (green, `#3fb950`)
  - Hover tooltip showing: date, prompt $/Mtok, completion $/Mtok
  - Legend below chart showing current prices
  - If no history for model: show "No price history available for this model"
  - If model has only one entry (current): show "Only one data point — history will accumulate over time"
  - Responsive: chart resizes with window
  - Dark theme: pass colors matching CSS variables

  **Must NOT do**:
  - Do NOT add any chart library beyond uPlot
  - Do NOT add animations (uPlot's default transitions are fine)

  **Recommended Agent Profile**:
  - **Category**: `visual-engineering`
    - Reason: Chart rendering, visual design, dark theme integration
  - **Skills**: `[]`

  **Parallelization**:
  - **Can Run In Parallel**: NO (sequential within Wave 3)
  - **Parallel Group**: Wave 3 (sequential with 9, 10, 12)
  - **Blocks**: None
  - **Blocked By**: Task 9 (needs data), Task 7 (needs history.json format)

  **References**:
  - uPlot docs: `https://github.com/leeoniya/uPlot/tree/master/docs`
  - uPlot log scale: `https://leeoniya.github.io/uPlot/demos/log-scales.html`
  - `docs/data/history.json` — Data format

  **Acceptance Criteria**:
  - [ ] uPlot script loads from CDN
  - [ ] Clicking a model row renders a chart
  - [ ] Chart has two lines (prompt + completion)
  - [ ] Y-axis is log scale
  - [ ] Hover shows tooltip with date and prices
  - [ ] Chart resizes with window
  - [ ] "No history" message shown for models without history

  **QA Scenarios**:
  ```
  Scenario: Chart renders with correct data
    Tool: Playwright
    Steps:
      1. Navigate to index.html
      2. Click a model row (e.g., one with known history)
      3. Wait for canvas element to appear
      4. Check canvas has non-zero width and height
      5. Hover over chart area
      6. Check tooltip element is visible
    Expected Result: Chart renders, tooltip works
    Evidence: .sisyphus/evidence/task-11-chart.txt
  ```

  **Commit**: YES (groups with 9, 10, 12)
  - Message: `feat(site): static frontend with table, charts, theme`
  - Files: `docs/index.html`, `docs/assets/app.js`

- [ ] 12. **app.js — theme toggle + provider page view**

  **What to do**:
  - Theme toggle:
    - On load: check `localStorage.getItem('theme')`, fall back to `prefers-color-scheme`
    - Set `document.documentElement.dataset.theme` to 'dark' or 'light'
    - Toggle button: click → flip theme, save to localStorage, update dataset
    - Button text/icon: moon/sun SVG inline
  - Provider page view:
    - When `state.provider` is set: show provider name as heading, filter table to that provider's models
    - Show provider stats: model count, price range (min/max prompt + completion), average price
    - Show "Clear filter" button to reset provider
    - Provider dropdown in header: populated from unique provider list, "All Providers" default
  - All state changes update URL hash and trigger re-render

  **Must NOT do**:
  - Do NOT add any icon library — inline SVG only
  - Do NOT add analytics or tracking

  **Recommended Agent Profile**:
  - **Category**: `unspecified-high`
    - Reason: Theme logic, provider filtering, UI interactions
  - **Skills**: `[]`

  **Parallelization**:
  - **Can Run In Parallel**: NO (sequential within Wave 3)
  - **Parallel Group**: Wave 3 (sequential with 9, 10, 11)
  - **Blocks**: None
  - **Blocked By**: Task 9 (needs data + state), Task 4 (needs CSS theme classes)

  **References**:
  - `docs/assets/style.css` — Theme CSS variables
  - `simonw/llm-prices/index.html` — Theme toggle pattern

  **Acceptance Criteria**:
  - [ ] Theme toggle button exists and works
  - [ ] Theme persists across page reload (localStorage)
  - [ ] `prefers-color-scheme` is respected on first visit
  - [ ] Provider dropdown is populated with unique providers
  - [ ] Selecting a provider filters the table
  - [ ] Provider stats are shown when filtered
  - [ ] "Clear filter" button works

  **QA Scenarios**:
  ```
  Scenario: Theme toggle and provider filter work
    Tool: Playwright
    Steps:
      1. Navigate to index.html
      2. Click theme toggle button
      3. Check document.documentElement.dataset.theme changed
      4. Reload page
      5. Check theme is still the toggled value (localStorage)
      6. Select "anthropic" from provider dropdown
      7. Check all visible rows have provider "anthropic"
      8. Check provider stats are displayed
      9. Click "Clear filter"
      10. Check all providers are visible again
    Expected Result: Theme persists, provider filter works
    Evidence: .sisyphus/evidence/task-12-theme-provider.txt
  ```

  **Commit**: YES (groups with 9, 10, 11)
  - Message: `feat(site): static frontend with table, charts, theme`
  - Files: `docs/assets/app.js`

- [ ] 13. **Custom domain DNS setup (Cloudflare)**

  **What to do**:
  - Add `docs/CNAME` with content: `models.spagserv.uk`
  - In Cloudflare DNS for spagserv.uk: add CNAME record `models` → `mrspaghatti.github.io`
  - Enable proxy (orange cloud) for CDN + SSL
  - In GitHub repo Settings → Pages → Custom domain: `models.spagserv.uk`
  - Wait for DNS propagation and HTTPS provisioning (GitHub issues SSL cert automatically)
  - Verify: `curl -sI https://models.spagserv.uk/` returns 200

  **Must NOT do**:
  - Do NOT add an A record pointing to GitHub Pages IPs (they change)
  - Do NOT set `Enforce HTTPS` until SSL cert is provisioned

  **Recommended Agent Profile**:
  - **Category**: `quick`
    - Reason: DNS config, well-defined steps
  - **Skills**: `[]`

  **Parallelization**:
  - **Can Run In Parallel**: YES
  - **Parallel Group**: Wave 4 (with Tasks 14, 15)
  - **Blocks**: None (can be done in parallel with other Wave 4 tasks)
  - **Blocked By**: None (CNAME file already exists from Task 5)

  **References**:
  - GitHub Pages custom domain docs: `https://docs.github.com/en/pages/configuring-a-custom-domain-for-your-github-pages-site`
  - Cloudflare DNS docs

  **Acceptance Criteria**:
  - [ ] `curl -sI https://models.spagserv.uk/` returns 200
  - [ ] `curl -sI https://models.spagserv.uk/data/current.json` returns 200 with `Content-Type: application/json`

  **QA Scenarios**:
  ```
  Scenario: Custom domain resolves and serves content
    Tool: Bash (curl)
    Steps:
      1. curl -sI https://models.spagserv.uk/
      2. curl -sI https://models.spagserv.uk/data/current.json
    Expected Result: Both return HTTP 200
    Evidence: .sisyphus/evidence/task-13-domain.txt
  ```

  **Commit**: YES (separate)
  - Message: `chore(domain): CNAME for spagserv.uk`
  - Files: `docs/CNAME` (already exists, verify content)

- [ ] 14. **CI smoke tests (curl, jq, Playwright)**

  **What to do**:
  - Add a new workflow `.github/workflows/smoke.yml` (or extend update.yml with a test job)
  - Smoke test steps:
    1. `curl -sI https://models.spagserv.uk/` → 200
    2. `curl -s https://models.spagserv.uk/data/current.json | jq '.models | length'` → ≥ 300
    3. `curl -s https://models.spagserv.uk/data/history.json | jq '.entries | length'` → ≥ 1
    4. `curl -s https://models.spagserv.uk/data/current.json | wc -c` → < 204800
    5. `curl -s https://models.spagserv.uk/data/history.json | wc -c` → < 1048576
  - Run on schedule (every 6 hours, offset from update cron) + workflow_dispatch
  - Use `actions/checkout@v4` with `fetch-depth: 1` (no git history needed)
  - Fail loudly on any check failure (send notification via GitHub UI)

  **Must NOT do**:
  - Do NOT add Playwright to CI (too heavy for a smoke test — keep it curl+jq)
  - Do NOT block the update workflow on smoke tests

  **Recommended Agent Profile**:
  - **Category**: `deep`
    - Reason: CI pipeline design, reliability considerations
  - **Skills**: `[]`

  **Parallelization**:
  - **Can Run In Parallel**: YES
  - **Parallel Group**: Wave 4 (with Tasks 13, 15)
  - **Blocks**: None
  - **Blocked By**: Task 8 (CI workflow), Task 13 (domain)

  **References**:
  - `.github/workflows/update.yml` — Existing workflow pattern
  - GitHub Actions docs for `schedule` event

  **Acceptance Criteria**:
  - [ ] Smoke workflow exists and is valid YAML
  - [ ] All curl+jq checks pass against the live site
  - [ ] Workflow runs on schedule and workflow_dispatch

  **QA Scenarios**:
  ```
  Scenario: Smoke tests pass
    Tool: Bash
    Steps:
      1. curl -sI https://models.spagserv.uk/ | grep "200 OK"
      2. curl -s https://models.spagserv.uk/data/current.json | jq '.models | length'
      3. curl -s https://models.spagserv.uk/data/history.json | jq '.entries | length'
    Expected Result: All checks pass
    Evidence: .sisyphus/evidence/task-14-smoke.txt
  ```

  **Commit**: YES (separate)
  - Message: `ci(tests): smoke test suite`
  - Files: `.github/workflows/smoke.yml`

- [ ] 15. **Final integration — backfill history, deploy, verify**

  **What to do**:
  - Run `scripts/backfill-history.nim` to generate initial `docs/data/history.json`
  - Run `./src/main` to generate `docs/data/current.json`
  - Verify both JSON files are valid
  - Commit all files and push to master
  - Enable GitHub Pages in repo settings (Settings → Pages → Source: Deploy from branch `main`, folder `/docs`)
  - Configure custom domain in GitHub Pages settings: `models.spagserv.uk`
  - Wait for initial deploy (1-5 minutes)
  - Verify: `curl https://models.spagserv.uk/` returns the site
  - Verify: Playwright smoke test on the live site
  - Verify: `curl https://models.spagserv.uk/data/current.json` returns valid JSON

  **Must NOT do**:
  - Do NOT modify any source files in this task
  - Do NOT skip the Playwright verification

  **Recommended Agent Profile**:
  - **Category**: `deep`
    - Reason: Integration orchestration, deployment verification
  - **Skills**: `[]`

  **Parallelization**:
  - **Can Run In Parallel**: NO (final integration)
  - **Parallel Group**: Wave 4 (sequential after 13, 14)
  - **Blocks**: None (final task)
  - **Blocked By**: Tasks 1-14

  **References**:
  - All previous tasks' outputs
  - GitHub Pages docs

  **Acceptance Criteria**:
  - [ ] `curl https://models.spagserv.uk/` returns 200 with HTML
  - [ ] `curl https://models.spagserv.uk/data/current.json` returns valid JSON with ≥360 models
  - [ ] `curl https://models.spagserv.uk/data/history.json` returns valid JSON with entries
  - [ ] Playwright: table renders, sort works, chart renders, theme toggle works
  - [ ] Total frontend assets gzipped < 50KB

  **QA Scenarios**:
  ```
  Scenario: Full integration verification
    Tool: Bash + Playwright
    Steps:
      1. curl -sI https://models.spagserv.uk/ | head -5
      2. curl -s https://models.spagserv.uk/data/current.json | jq '.models | length'
      3. curl -s https://models.spagserv.uk/data/history.json | jq '.entries | length'
      4. Playwright: navigate to site, verify table renders
      5. Playwright: sort, filter, click row, verify chart
      6. Playwright: toggle theme, verify persistence
    Expected Result: All checks pass
    Evidence: .sisyphus/evidence/task-15-integration.txt
  ```

  **Commit**: YES (separate)
  - Message: `chore(deploy): backfill history, enable Pages, verify`
  - Files: `docs/data/history.json`, `docs/data/current.json`

---

> 4 review agents run in PARALLEL. ALL must APPROVE. Present consolidated results and wait for explicit user okay.

- [ ] F1. **Plan Compliance Audit** — `oracle`
  Verify: every Must Have is implemented, every Must NOT Have is absent, all evidence files exist, deliverables match plan.

- [ ] F2. **Code Quality Review** — `unspecified-high`
  Run `tsc --noEmit` if applicable, review for AI slop, verify no build dependency crept in, check file sizes.

- [ ] F3. **Real Manual QA** — `unspecified-high` (+ `playwright` skill)
  Execute EVERY QA scenario from EVERY task. Capture evidence to `.sisyphus/evidence/final-qa/`. Test cross-task integration.

- [ ] F4. **Scope Fidelity Check** — `deep`
  Verify every built feature maps 1:1 to a task in this plan. No scope creep. No unaccounted files.

---

## Commit Strategy

- **1-5**: `feat(schema): define versioned JSON data types`
- **6-7**: `feat(generator): emit current.json and history.json`
- **8**: `ci(workflow): fetch-depth 0, concurrency, jq validation`
- **9-12**: `feat(site): static frontend with table, charts, theme`
- **13**: `chore(domain): CNAME for spagserv.uk`
- **14-15**: `ci(tests): smoke test suite and integration`

---

## Success Criteria

### Verification Commands
```bash
curl -sI https://models.spagserv.uk/ | grep "200 OK"
curl -s https://models.spagserv.uk/data/current.json | jq '.models | length'  # >= 360
curl -s https://models.spagserv.uk/data/history.json | jq '.models | length'  # >= 360
gzip -c docs/index.html docs/assets/style.css docs/assets/app.js | wc -c  # < 51200
```

### Final Checklist
- [ ] All Must Have items present
- [ ] All Must NOT Have items absent (search codebase for npm, package.json, React, etc.)
- [ ] All evidence files exist in `.sisyphus/evidence/`
- [ ] User has been presented with results and given explicit okay
