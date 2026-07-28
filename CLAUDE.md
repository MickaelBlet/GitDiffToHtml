# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

`git_diff_to_html.sh` — a single Bash script (~1800 lines) that renders any `git diff` into one self-contained, Bitbucket-style HTML file. No dependencies beyond `git`, `bash` and `awk`. There is no build system, no test suite, no package manifest: the script *is* the project.

## Commands

```bash
# Generate + inspect (default output: git_diff.html, gitignored)
./git_diff_to_html.sh -o /tmp/out.html HEAD~3..HEAD
./git_diff_to_html.sh --working -o /tmp/wip.html

# Syntax-check after editing shell
bash -n git_diff_to_html.sh

# Syntax-check the embedded browser JS: extract the <script> body from a
# generated page into a .js file, then
node --check /tmp/extracted.js

# Regenerate README previews (wkhtmltoimage)
./git_diff_to_html.sh --view unified --theme light -o /tmp/preview-light.html HEAD~3..HEAD
wkhtmltoimage --width 1200 --height 800 --crop-h 800 --quality 90 /tmp/preview-light.html preview-light.png
```

Verification is manual: generate a page and open it in a browser. Exercise both `--view` modes, both themes, `--working` (untracked files), a multi-commit range (per-commit navigation only appears with ≥2 commits) and a single commit.

## Script layout

Line ranges drift; find sections by their `# ----------` / `# -----` comment banners.

1. **Header comment block** (lines 1–48) — the usage text. `usage()` prints it by slicing this block, so option docs live here *and* in README.md; keep both in sync when adding a flag.
2. **Arg parsing / defaults** — `SOURCE_MODE` is `range | working | staged | unstaged`; `set_source_mode` rejects conflicting flags.
3. **Range resolution** — builds `DIFF_ARGS[]`, the revision selector handed to every `git diff`. A bare SHA becomes `<sha>^..<sha>`, or `<empty-tree>..<sha>` for a root commit. `unstaged` leaves `DIFF_ARGS` empty (work tree vs index). All expansions use `${DIFF_ARGS[@]+"${DIFF_ARGS[@]}"}` because of `set -u`.
4. **Untracked files** — `git diff` never lists them, so each is synthesized via `git diff --no-index /dev/null <file>`, and its counts are added manually to the shortstat totals.
5. **HTML emission** — everything from `{ cat <<HTML_HEAD` to `} > "$OUTPUT"` is one redirected block. `HTML_HEAD` is *unquoted* (shell interpolation active: `$(html_escape ...)`, CLI-default `class="active"` markers); `HTML_FOOT` is *quoted* `<<'HTML_FOOT'` (pure JS, no interpolation). Adding `$`, backticks or `\` to the wrong heredoc is the usual breakage.
6. **`render_diff_html <diff-text> <id-prefix>`** — an awk program that turns a unified diff into `.file-card` markup. It only ever emits the **unified** table; the split table is built client-side. The `id-prefix` argument keeps element ids unique across diff sets.
7. **Commit list / diff sets** — `COMMIT_HTML` is built *before* the heredoc (it is interpolated into the sidebar `<aside>`), while the matching `.diff-set` blocks are emitted later in `<main>`. With a multi-commit range the page holds one `.diff-set` per commit plus an `all` set; clicking a sidebar commit row swaps the visible set.
8. **Embedded JS** (`HTML_FOOT`) — one IIFE, ordered by dependency and marked with `// -----` banners. Order matters: sidebar counts are read from `table.unified` *before* the split table exists; syntax highlighting and word-level diffing run before the split table is cloned so both views inherit the markup.

## Client-side conventions

- State lives in `document.body` classes (`theme-dark`, `view-split`, …) and is persisted under `gd2h-*` localStorage keys. **localStorage wins over the CLI defaults** (`--theme`, `--view`, `--whitespace`, `--collapse`), which only seed the initial markup — a stale saved preference is the usual "my flag did nothing" report.
- Whitespace markers and word-level highlighting rewrite `innerHTML` with a `/(<[^>]*>)|([^<]+)/` tag/text split so they don't corrupt syntax-highlight spans. Any new HTML-rewriting pass must follow the same pattern.
- Syntax highlighting is hand-rolled, per-line, keyed off the file extension via the `extLang` map; add languages there.
- The sidebar is a flex column that owns its own scrolling (`.commit-list` and `.file-list` each scroll independently; the aside itself is `overflow: hidden`). Sections are separated by `.sidebar-section-title`.
- Collapsing, prev/next navigation and the sidebar all re-derive from the *active* diff set (`activeSet()`); anything added must be rebuilt on set switch too.

## Conventions

- 4-space indent in shell; lowercase `snake_case` functions, `UPPER_CASE` globals.
- All interpolated text goes through `html_escape` (shell) or `esc` (awk).
- Sticky headers depend on the `--summary-height` CSS variable kept in sync by a `ResizeObserver`; new sticky elements must account for it.
