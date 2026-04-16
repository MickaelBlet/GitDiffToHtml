#!/usr/bin/env bash
#
# git-diff-to-html.sh
#
# Generate a self-contained, Bitbucket-style HTML page from a git diff.
#
# Usage:
#   git-diff-to-html.sh [options] [<commit-range>]
#
# Options:
#   -o, --output FILE    Output HTML file (default: git-diff.html)
#   -t, --title  TEXT    Page title (default: "Git Diff: <range>")
#   -U, --unified N      Number of context lines around each change.
#                        Default is very large so the full content of each
#                        modified file is shown. Use a small number (e.g. 3)
#                        to get a classic compact diff.
#       --view MODE      Initial view mode: "unified" (default) or "split".
#                        A toggle is always present in the page.
#       --theme NAME     Initial theme: "light" (default) or "dark".
#                        A toggle is always present in the page.
#   -h, --help           Show this help message and exit
#
# Arguments:
#   <commit-range>       Any git revision range, e.g. HEAD~3..HEAD,
#                        main..feature, or a single commit SHA.
#                        Defaults to the last commit (HEAD~1..HEAD).
#
# Examples:
#   git-diff-to-html.sh                          # last commit, full files
#   git-diff-to-html.sh HEAD~5..HEAD
#   git-diff-to-html.sh -o review.html main..feature
#   git-diff-to-html.sh -U 3 HEAD~1..HEAD        # compact 3-line context
#   git-diff-to-html.sh --view split --theme dark HEAD~1..HEAD
#   git-diff-to-html.sh abc1234                  # that single commit

set -euo pipefail

OUTPUT="git-diff.html"
TITLE=""
RANGE=""
CONTEXT_LINES="1000000"
VIEW_MODE="unified"
THEME="light"

usage() {
    sed -n '3,33p' "$0" | sed 's/^# \{0,1\}//'
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        -o|--output)
            [[ $# -ge 2 ]] || { echo "Error: $1 requires an argument" >&2; exit 2; }
            OUTPUT="$2"; shift 2 ;;
        -t|--title)
            [[ $# -ge 2 ]] || { echo "Error: $1 requires an argument" >&2; exit 2; }
            TITLE="$2"; shift 2 ;;
        -U|--unified)
            [[ $# -ge 2 ]] || { echo "Error: $1 requires an argument" >&2; exit 2; }
            if ! [[ "$2" =~ ^[0-9]+$ ]]; then
                echo "Error: $1 expects a non-negative integer" >&2; exit 2
            fi
            CONTEXT_LINES="$2"; shift 2 ;;
        --view)
            [[ $# -ge 2 ]] || { echo "Error: $1 requires an argument" >&2; exit 2; }
            case "$2" in
                unified|split) VIEW_MODE="$2" ;;
                *) echo "Error: --view expects 'unified' or 'split'" >&2; exit 2 ;;
            esac
            shift 2 ;;
        --theme)
            [[ $# -ge 2 ]] || { echo "Error: $1 requires an argument" >&2; exit 2; }
            case "$2" in
                light|dark) THEME="$2" ;;
                *) echo "Error: --theme expects 'light' or 'dark'" >&2; exit 2 ;;
            esac
            shift 2 ;;
        -h|--help)
            usage; exit 0 ;;
        --)
            shift
            [[ $# -gt 0 ]] && RANGE="$1"
            break ;;
        -*)
            echo "Error: unknown option '$1'" >&2
            usage >&2
            exit 2 ;;
        *)
            if [[ -n "$RANGE" ]]; then
                echo "Error: unexpected extra argument '$1'" >&2
                exit 2
            fi
            RANGE="$1"; shift ;;
    esac
done

# Ensure we're inside a git work tree.
if ! git rev-parse --show-toplevel >/dev/null 2>&1; then
    echo "Error: not inside a git repository" >&2
    exit 1
fi

# Resolve default range: the last commit.
if [[ -z "$RANGE" ]]; then
    if git rev-parse --verify -q HEAD~1 >/dev/null 2>&1; then
        RANGE="HEAD~1..HEAD"
    else
        RANGE="HEAD"
    fi
fi

# Build the actual diff range. A single commit becomes <commit>^..<commit>
# (or empty-tree..<commit> for the root commit). Explicit A..B stays as-is.
if [[ "$RANGE" == *..* ]]; then
    DIFF_RANGE="$RANGE"
else
    if ! git rev-parse --verify -q "$RANGE" >/dev/null 2>&1; then
        echo "Error: invalid revision '$RANGE'" >&2
        exit 1
    fi
    if git rev-parse --verify -q "${RANGE}^" >/dev/null 2>&1; then
        DIFF_RANGE="${RANGE}^..${RANGE}"
    else
        EMPTY_TREE=$(git hash-object -t tree /dev/null)
        DIFF_RANGE="${EMPTY_TREE}..${RANGE}"
    fi
fi

# Validate the effective diff range.
if ! git rev-list "$DIFF_RANGE" >/dev/null 2>&1; then
    echo "Error: invalid commit range '$RANGE'" >&2
    exit 1
fi

TITLE="${TITLE:-Git Diff: $RANGE}"

# ---------- helpers ----------

html_escape() {
    local s="${1-}"
    s="${s//&/&amp;}"
    s="${s//</&lt;}"
    s="${s//>/&gt;}"
    s="${s//\"/&quot;}"
    s="${s//\'/&#39;}"
    printf '%s' "$s"
}

# ---------- gather metadata ----------

REPO_NAME=$(basename "$(git rev-parse --show-toplevel)")
GEN_DATE=$(date '+%Y-%m-%d %H:%M:%S %z')
SHORTSTAT=$(git diff --shortstat "$DIFF_RANGE" 2>/dev/null || true)

# Parse shortstat: "  N files changed, N insertions(+), N deletions(-)"
FILES_CHANGED=0
INSERTIONS=0
DELETIONS=0
if [[ -n "$SHORTSTAT" ]]; then
    FILES_CHANGED=$(printf '%s' "$SHORTSTAT" | sed -n 's/.* \([0-9][0-9]*\) files\{0,1\} changed.*/\1/p')
    INSERTIONS=$(printf   '%s' "$SHORTSTAT" | sed -n 's/.* \([0-9][0-9]*\) insertions\{0,1\}(+).*/\1/p')
    DELETIONS=$(printf    '%s' "$SHORTSTAT" | sed -n 's/.* \([0-9][0-9]*\) deletions\{0,1\}(-).*/\1/p')
    FILES_CHANGED=${FILES_CHANGED:-0}
    INSERTIONS=${INSERTIONS:-0}
    DELETIONS=${DELETIONS:-0}
fi

# ---------- write the HTML ----------

{
cat <<HTML_HEAD
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>$(html_escape "$TITLE")</title>
<style>
:root {
    --bg: #f4f5f7;
    --card-bg: #ffffff;
    --header-bg: #ffffff;
    --border: #dfe1e6;
    --text: #172b4d;
    --muted: #6b778c;
    --hunk-bg: #f1f8ff;
    --hunk-color: #005580;
    --add-bg: #e6ffed;
    --add-ln-bg: #cdffd8;
    --add-text: #1a7f4e;
    --del-bg: #ffebe9;
    --del-ln-bg: #ffdcd7;
    --del-text: #c92a2a;
    --ln-bg: #fafbfc;
    --empty-bg: #f6f8fa;
    --file-header-bg: #fafbfc;
    --file-header-hover: #f4f5f7;
    --code-inline-bg: #f4f5f7;
    --button-bg: #ffffff;
    --button-text: #42526e;
    --accent: #0052cc;
    --accent-text: #ffffff;
    --status-added: #36b37e;
    --status-deleted: #de350b;
    --status-modified: #0052cc;
    --status-renamed: #ff991f;
    --shadow: 0 3px 10px rgba(9, 30, 66, 0.18);
}
body.theme-dark {
    --bg: #0d1117;
    --card-bg: #161b22;
    --header-bg: #161b22;
    --border: #30363d;
    --text: #c9d1d9;
    --muted: #8b949e;
    --hunk-bg: #1c2128;
    --hunk-color: #58a6ff;
    --add-bg: #04260f;
    --add-ln-bg: #033a16;
    --add-text: #56d364;
    --del-bg: #3c0a12;
    --del-ln-bg: #67060c;
    --del-text: #f85149;
    --ln-bg: #0d1117;
    --empty-bg: #010409;
    --file-header-bg: #1c2128;
    --file-header-hover: #22272e;
    --code-inline-bg: #1c2128;
    --button-bg: #21262d;
    --button-text: #c9d1d9;
    --accent: #1f6feb;
    --accent-text: #ffffff;
    --status-added: #238636;
    --status-deleted: #da3633;
    --status-modified: #1f6feb;
    --status-renamed: #d29922;
    --shadow: 0 3px 12px rgba(0, 0, 0, 0.6);
}
* { box-sizing: border-box; }
html, body { margin: 0; padding: 0; }
body {
    font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Helvetica, Arial, sans-serif;
    background: var(--bg);
    color: var(--text);
    font-size: 14px;
    line-height: 1.5;
    transition: background-color 0.15s ease, color 0.15s ease;
}
header.top {
    background: var(--header-bg);
    border-bottom: 1px solid var(--border);
    padding: 20px 24px;
}
header.top h1 {
    margin: 0 0 6px 0;
    font-size: 20px;
    font-weight: 600;
}
header.top .meta {
    color: var(--muted);
    font-size: 13px;
}
header.top .meta code {
    background: var(--code-inline-bg);
    border: 1px solid var(--border);
    border-radius: 3px;
    padding: 1px 6px;
    font-size: 12px;
}
.layout {
    display: flex;
    align-items: flex-start;
    max-width: 1600px;
    margin: 0 auto;
}
.sidebar {
    flex: 0 0 280px;
    position: sticky;
    top: 0;
    height: 100vh;
    overflow-y: auto;
    background: var(--card-bg);
    border-right: 1px solid var(--border);
    font-size: 13px;
}
.sidebar-header {
    position: sticky;
    top: 0;
    background: var(--file-header-bg);
    border-bottom: 1px solid var(--border);
    padding: 10px 14px;
    display: flex;
    align-items: center;
    justify-content: space-between;
    font-weight: 600;
    color: var(--text);
    z-index: 1;
}
.sidebar-header button {
    background: transparent;
    border: none;
    color: var(--muted);
    font-size: 18px;
    cursor: pointer;
    padding: 0 4px;
    line-height: 1;
}
.sidebar-header button:hover { color: var(--text); }
.file-list {
    list-style: none;
    margin: 0;
    padding: 6px 0;
}
.file-list li {
    display: flex;
    align-items: center;
    gap: 8px;
    padding: 6px 12px;
    cursor: pointer;
    border-left: 3px solid transparent;
}
.file-list li:hover { background: var(--file-header-hover); }
.file-list li.active {
    background: var(--file-header-hover);
    border-left-color: var(--accent);
}
.file-list .dot {
    flex: 0 0 8px;
    width: 8px;
    height: 8px;
    border-radius: 50%;
    display: inline-block;
}
.file-list .dot.added    { background: var(--status-added); }
.file-list .dot.deleted  { background: var(--status-deleted); }
.file-list .dot.modified { background: var(--status-modified); }
.file-list .dot.renamed,
.file-list .dot.copied   { background: var(--status-renamed); }
.file-list .info {
    flex: 1;
    min-width: 0;
    display: flex;
    flex-direction: column;
}
.file-list .name {
    font-family: Menlo, Consolas, "Courier New", monospace;
    font-size: 12px;
    color: var(--text);
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
}
.file-list .dir {
    font-family: Menlo, Consolas, "Courier New", monospace;
    font-size: 10px;
    color: var(--muted);
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
}
.file-list .counts {
    flex: 0 0 auto;
    font-size: 10px;
    font-family: Menlo, Consolas, "Courier New", monospace;
}
.file-list .counts .a { color: var(--add-text); }
.file-list .counts .d { color: var(--del-text); }
#sidebar-show {
    position: fixed;
    top: 16px;
    left: 16px;
    z-index: 90;
    width: 34px;
    height: 34px;
    padding: 0;
    border-radius: 4px;
    background: var(--card-bg);
    border: 1px solid var(--border);
    color: var(--text);
    cursor: pointer;
    box-shadow: var(--shadow);
    font-size: 16px;
    line-height: 1;
    display: none;
}
#sidebar-show:hover { background: var(--file-header-hover); }
body.sidebar-hidden .sidebar { display: none; }
body.sidebar-hidden #sidebar-show { display: inline-flex; align-items: center; justify-content: center; }
.content {
    flex: 1;
    min-width: 0;
    overflow: hidden;
}
main {
    padding: 0 24px 40px 24px;
    margin-top: 24px;
}
.summary {
    background: var(--card-bg);
    border: 1px solid var(--border);
    border-radius: 3px;
    padding: 14px 18px;
    margin-bottom: 20px;
}
.summary-top {
    display: flex;
    justify-content: space-between;
    align-items: center;
    gap: 12px;
    flex-wrap: wrap;
}
.summary .stats {
    display: flex;
    gap: 20px;
    flex-wrap: wrap;
    font-size: 13px;
}
.summary .stats b { font-weight: 700; }
.summary .add { color: var(--add-text); }
.summary .del { color: var(--del-text); }
.toolbar {
    display: flex;
    align-items: center;
    gap: 10px;
}
.view-toggle {
    display: inline-flex;
    border: 1px solid var(--border);
    border-radius: 3px;
    overflow: hidden;
    background: var(--button-bg);
}
.view-toggle button {
    background: var(--button-bg);
    border: none;
    padding: 6px 14px;
    cursor: pointer;
    font-size: 12px;
    font-weight: 600;
    color: var(--button-text);
    font-family: inherit;
}
.view-toggle button + button { border-left: 1px solid var(--border); }
.view-toggle button.active {
    background: var(--accent);
    color: var(--accent-text);
}
.view-toggle button:not(.active):hover { background: var(--file-header-hover); }
#theme-toggle {
    background: var(--button-bg);
    border: 1px solid var(--border);
    border-radius: 3px;
    width: 32px;
    height: 30px;
    padding: 0;
    cursor: pointer;
    color: var(--button-text);
    font-size: 16px;
    line-height: 1;
    display: inline-flex;
    align-items: center;
    justify-content: center;
}
#theme-toggle:hover { background: var(--file-header-hover); }
#theme-toggle .moon { display: inline; }
#theme-toggle .sun  { display: none; }
body.theme-dark #theme-toggle .moon { display: none; }
body.theme-dark #theme-toggle .sun  { display: inline; }
.commit-list {
    margin-top: 12px;
    border-top: 1px solid var(--border);
    padding-top: 10px;
}
.commit-list .row {
    display: flex;
    gap: 12px;
    padding: 4px 0;
    font-size: 13px;
    align-items: baseline;
}
.commit-list .sha {
    font-family: Menlo, Consolas, "Courier New", monospace;
    color: var(--accent);
    flex: 0 0 auto;
    min-width: 70px;
}
.commit-list .subject { flex: 1; color: var(--text); }
.commit-list .author { color: var(--muted); font-size: 12px; }
.commit-list .date { color: var(--muted); font-size: 12px; }
.file-card {
    background: var(--card-bg);
    border: 1px solid var(--border);
    border-radius: 3px;
    margin-bottom: 16px;
    overflow: hidden;
}
.file-header {
    padding: 10px 14px;
    background: var(--file-header-bg);
    border-bottom: 1px solid var(--border);
    display: flex;
    align-items: center;
    gap: 10px;
    cursor: pointer;
    user-select: none;
}
.file-header:hover { background: var(--file-header-hover); }
.file-header .status {
    text-transform: uppercase;
    font-size: 10px;
    font-weight: 700;
    letter-spacing: 0.5px;
    color: #fff;
    padding: 3px 7px;
    border-radius: 3px;
    flex: 0 0 auto;
}
.status.added    { background: var(--status-added); }
.status.deleted  { background: var(--status-deleted); }
.status.modified { background: var(--status-modified); }
.status.renamed,
.status.copied   { background: var(--status-renamed); }
.file-header .path {
    font-family: Menlo, Consolas, "Courier New", monospace;
    font-size: 13px;
    color: var(--text);
    flex: 1;
    word-break: break-all;
}
.file-header .toggle {
    color: var(--muted);
    font-size: 11px;
    flex: 0 0 auto;
}
.diff-body { overflow-x: auto; max-width: 100%; }
table.diff-table {
    border-collapse: collapse;
    width: 100%;
    font-family: Menlo, Consolas, "Courier New", monospace;
    font-size: 12px;
}
table.diff-table td {
    padding: 0 8px;
    vertical-align: top;
    white-space: pre;
}
td.ln {
    width: 1%;
    min-width: 42px;
    text-align: right;
    color: var(--muted);
    background: var(--ln-bg);
    border-right: 1px solid var(--border);
    user-select: none;
}
td.code { width: 100%; }
tr.ctx td.code { color: var(--text); }
tr.add td       { background: var(--add-bg); }
tr.add td.ln    { background: var(--add-ln-bg); color: var(--add-text); }
tr.del td       { background: var(--del-bg); }
tr.del td.ln    { background: var(--del-ln-bg); color: var(--del-text); }
tr.hunk td {
    background: var(--hunk-bg);
    color: var(--hunk-color);
    font-style: italic;
    padding-top: 2px;
    padding-bottom: 2px;
}
tr.hunk td.ln { color: var(--hunk-color); }
tr.nonewline td { color: var(--muted); font-style: italic; }
tr.binary td    { color: var(--muted); font-style: italic; padding: 10px 14px; }
.file-card.collapsed .diff-body { display: none; }
.file-card.collapsed .file-header .toggle::before { content: "▸ "; }
.file-card .file-header .toggle::before { content: "▾ "; }

/* ----- Split (side-by-side) view ----- */
table.diff-table.sbs { display: none; table-layout: fixed; }
body.view-split table.diff-table.unified { display: none; }
body.view-split table.diff-table.sbs     { display: table; }
table.diff-table.sbs td.ln {
    width: 42px;
    min-width: 42px;
    border-right: 1px solid var(--border);
}
table.diff-table.sbs td.code {
    width: 50%;
    white-space: pre-wrap;
    word-break: break-word;
    overflow-wrap: break-word;
}
table.diff-table.sbs td.code + td.ln { border-left: 2px solid var(--border); }
table.diff-table.sbs td.code.ctx   { color: var(--text); background: var(--card-bg); }
table.diff-table.sbs td.code.add   { background: var(--add-bg); }
table.diff-table.sbs td.ln.add     { background: var(--add-ln-bg); color: var(--add-text); }
table.diff-table.sbs td.code.del   { background: var(--del-bg); }
table.diff-table.sbs td.ln.del     { background: var(--del-ln-bg); color: var(--del-text); }
table.diff-table.sbs td.code.empty,
table.diff-table.sbs td.ln.empty   { background: var(--empty-bg); }
table.diff-table.sbs tr.hunk td    { background: var(--hunk-bg); }
.empty {
    background: #fff;
    border: 1px solid var(--border);
    border-radius: 3px;
    padding: 30px;
    text-align: center;
    color: var(--muted);
}
footer {
    text-align: center;
    color: var(--muted);
    font-size: 12px;
    padding: 16px 0 30px 0;
}
footer a { color: var(--muted); }
.nav-buttons {
    position: fixed;
    right: 20px;
    bottom: 20px;
    z-index: 100;
    background: var(--card-bg);
    border: 1px solid var(--border);
    border-radius: 6px;
    box-shadow: var(--shadow);
    padding: 6px 10px;
    display: flex;
    align-items: center;
    gap: 8px;
    font-size: 13px;
}
.nav-buttons button {
    background: var(--accent);
    color: var(--accent-text);
    border: none;
    padding: 6px 12px;
    border-radius: 3px;
    cursor: pointer;
    font-size: 12px;
    font-weight: 600;
    font-family: inherit;
}
.nav-buttons button:hover:not(:disabled) { filter: brightness(0.92); }
.nav-buttons button:disabled {
    background: var(--border);
    color: var(--muted);
    cursor: not-allowed;
}
.nav-buttons .counter {
    color: var(--muted);
    font-variant-numeric: tabular-nums;
    min-width: 54px;
    text-align: center;
}
tr.flash > td {
    animation: flash 1.2s ease-out;
}
@keyframes flash {
    0%   { box-shadow: inset 3px 0 0 #ff991f; }
    100% { box-shadow: inset 3px 0 0 transparent; }
}
</style>
</head>
<body class="$([ "$THEME" = "dark" ] && echo -n "theme-dark ")$([ "$VIEW_MODE" = "split" ] && echo -n "view-split ")" data-initial-view="$(html_escape "$VIEW_MODE")" data-initial-theme="$(html_escape "$THEME")">
<button type="button" id="sidebar-show" title="Show files sidebar" aria-label="Show sidebar">&#9776;</button>
<div class="layout">
<aside class="sidebar" aria-label="Files">
    <div class="sidebar-header">
        <span>Files (${FILES_CHANGED})</span>
        <button type="button" id="sidebar-hide" title="Hide sidebar" aria-label="Hide sidebar">&times;</button>
    </div>
    <ul class="file-list" id="file-list"></ul>
</aside>
<div class="content">
<header class="top">
<h1>$(html_escape "$TITLE")</h1>
<div class="meta">
    Repository: <b>$(html_escape "$REPO_NAME")</b>
    &middot; Range: <code>$(html_escape "$RANGE")</code>
    &middot; Generated: $(html_escape "$GEN_DATE")
</div>
</header>
<main>
<section class="summary">
    <div class="summary-top">
        <div class="stats">
            <span><b>${FILES_CHANGED}</b> file$([ "$FILES_CHANGED" = "1" ] || echo s) changed</span>
            <span class="add"><b>+${INSERTIONS}</b> insertion$([ "$INSERTIONS" = "1" ] || echo s)</span>
            <span class="del"><b>&minus;${DELETIONS}</b> deletion$([ "$DELETIONS" = "1" ] || echo s)</span>
        </div>
        <div class="toolbar">
            <div class="view-toggle" role="group" aria-label="View mode">
                <button type="button" data-view="unified"$([ "$VIEW_MODE" = "unified" ] && echo -n ' class="active"')>Unified</button>
                <button type="button" data-view="split"$([ "$VIEW_MODE" = "split" ] && echo -n ' class="active"')>Split</button>
            </div>
            <button type="button" id="theme-toggle" title="Toggle dark / light theme" aria-label="Toggle theme">
                <span class="moon">&#9790;</span><span class="sun">&#9788;</span>
            </button>
        </div>
    </div>
HTML_HEAD

# ----- commit list -----
if [[ "$RANGE" == *..* ]]; then
    LOG_OUTPUT=$(git log --pretty=format:'%h%x1f%an%x1f%ad%x1f%s' --date=short "$RANGE" 2>/dev/null || true)
else
    LOG_OUTPUT=$(git log -1 --pretty=format:'%h%x1f%an%x1f%ad%x1f%s' --date=short "$RANGE" 2>/dev/null || true)
fi

if [[ -n "$LOG_OUTPUT" ]]; then
    echo '    <div class="commit-list">'
    while IFS=$'\x1f' read -r sha author adate subject; do
        [[ -z "$sha" ]] && continue
        printf '        <div class="row"><span class="sha">%s</span><span class="subject">%s</span><span class="author">%s</span><span class="date">%s</span></div>\n' \
            "$(html_escape "$sha")" \
            "$(html_escape "$subject")" \
            "$(html_escape "$author")" \
            "$(html_escape "$adate")"
    done <<< "$LOG_OUTPUT"
    echo '    </div>'
fi

echo '</section>'

# ----- diff body -----
DIFF_OUTPUT=$(git diff --no-color --unified="$CONTEXT_LINES" "$DIFF_RANGE" 2>/dev/null || true)

if [[ -z "$DIFF_OUTPUT" ]]; then
    echo '<div class="empty">No changes in this range.</div>'
else
    printf '%s\n' "$DIFF_OUTPUT" | awk '
    function esc(s) {
        gsub(/&/, "\\&amp;", s)
        gsub(/</, "\\&lt;",  s)
        gsub(/>/, "\\&gt;",  s)
        return s
    }
    function open_file(   path) {
        path = file_new
        if (file_status == "deleted") path = file_old
        if (file_status == "renamed" || file_status == "copied") path = file_old " → " file_new
        printf "<div class=\"file-card\" id=\"file-%d\">", file_counter
        printf "<div class=\"file-header\"><span class=\"status %s\">%s</span><span class=\"path\">%s</span><span class=\"toggle\">collapse</span></div>", file_status, file_status, esc(path)
        printf "<div class=\"diff-body\"><table class=\"diff-table unified\"><tbody>\n"
        file_opened = 1
        in_hunk = 0
        file_counter++
    }
    function ensure_open() {
        if (file_pending && !file_opened) open_file()
        file_pending = 0
    }
    function flush_file() {
        if (file_pending && !file_opened) open_file()
        if (file_opened) printf "</tbody></table></div></div>\n"
        file_opened = 0
        file_pending = 0
        in_hunk = 0
    }
    BEGIN {
        file_opened = 0
        file_pending = 0
        in_hunk = 0
        file_status = "modified"
        file_counter = 0
    }
    /^diff --git / {
        flush_file()
        n = split($0, parts, " ")
        pa = parts[3]; sub(/^a\//, "", pa)
        pb = parts[4]; sub(/^b\//, "", pb)
        file_old = pa
        file_new = pb
        file_status = "modified"
        file_pending = 1
        next
    }
    /^new file mode /     { file_status = "added";   next }
    /^deleted file mode / { file_status = "deleted"; next }
    /^rename from /       { file_status = "renamed"; next }
    /^rename to /         { next }
    /^copy from /         { file_status = "copied";  next }
    /^copy to /           { next }
    /^similarity index /  { next }
    /^dissimilarity index / { next }
    /^old mode /          { next }
    /^new mode /          { next }
    /^index /             { next }
    /^--- /               { next }
    /^\+\+\+ /            { next }
    /^Binary files /      {
        ensure_open()
        printf "<tr class=\"binary\"><td colspan=\"3\">%s</td></tr>\n", esc($0)
        next
    }
    /^@@/ {
        ensure_open()
        split($2, la, ","); split($3, ra, ",")
        left_line  = substr(la[1], 2) + 0
        right_line = substr(ra[1], 2) + 0
        printf "<tr class=\"hunk\"><td class=\"ln\">&hellip;</td><td class=\"ln\">&hellip;</td><td class=\"code\">%s</td></tr>\n", esc($0)
        in_hunk = 1
        next
    }
    {
        if (!in_hunk) next
        c = substr($0, 1, 1)
        rest = substr($0, 2)
        if (c == " ") {
            printf "<tr class=\"ctx\"><td class=\"ln\">%d</td><td class=\"ln\">%d</td><td class=\"code\"> %s</td></tr>\n", left_line, right_line, esc(rest)
            left_line++; right_line++
        } else if (c == "-") {
            printf "<tr class=\"del\"><td class=\"ln\">%d</td><td class=\"ln\"></td><td class=\"code\">-%s</td></tr>\n", left_line, esc(rest)
            left_line++
        } else if (c == "+") {
            printf "<tr class=\"add\"><td class=\"ln\"></td><td class=\"ln\">%d</td><td class=\"code\">+%s</td></tr>\n", right_line, esc(rest)
            right_line++
        } else if (c == "\\") {
            printf "<tr class=\"nonewline\"><td class=\"ln\"></td><td class=\"ln\"></td><td class=\"code\">%s</td></tr>\n", esc($0)
        }
    }
    END { flush_file() }
    '
fi

cat <<'HTML_FOOT'
</main>
<footer>Generated by git-diff-to-html.sh</footer>
</div><!-- /.content -->
</div><!-- /.layout -->
<div class="nav-buttons" role="group" aria-label="Change navigator">
    <button type="button" id="nav-prev" title="Previous change (p / k / Shift+Tab)">&uarr; Prev</button>
    <span class="counter" id="nav-counter">0 / 0</span>
    <button type="button" id="nav-next" title="Next change (n / j / Tab)">&darr; Next</button>
</div>
<script>
(function () {
    // ----- Collapse/expand file cards on header click.
    document.querySelectorAll('.file-header').forEach(function (h) {
        h.addEventListener('click', function (e) {
            // Don't collapse when a link or button inside the header is clicked.
            if (e.target.closest('a, button')) return;
            h.parentElement.classList.toggle('collapsed');
        });
    });

    // ----- Populate the sidebar file list (BEFORE SbS is built,
    //       so tr.add / tr.del counts come only from the unified table).
    var fileList = document.getElementById('file-list');
    var cards = document.querySelectorAll('.file-card');
    cards.forEach(function (card) {
        var statusEl = card.querySelector('.file-header .status');
        var status = statusEl ? (statusEl.classList[1] || 'modified') : 'modified';
        var path = (card.querySelector('.file-header .path') || {}).textContent || '';
        var adds = card.querySelectorAll('tr.add').length;
        var dels = card.querySelectorAll('tr.del').length;

        // Split path into directory and basename.
        var base = path, dir = '';
        var slash = path.lastIndexOf('/');
        if (slash >= 0) { base = path.substring(slash + 1); dir = path.substring(0, slash); }

        var li = document.createElement('li');
        li.setAttribute('data-target', card.id);
        li.title = path;

        var dot = document.createElement('span');
        dot.className = 'dot ' + status;
        li.appendChild(dot);

        var info = document.createElement('div');
        info.className = 'info';
        var nameSpan = document.createElement('span');
        nameSpan.className = 'name';
        nameSpan.textContent = base;
        info.appendChild(nameSpan);
        if (dir) {
            var dirSpan = document.createElement('span');
            dirSpan.className = 'dir';
            dirSpan.textContent = dir;
            info.appendChild(dirSpan);
        }
        li.appendChild(info);

        var counts = document.createElement('span');
        counts.className = 'counts';
        counts.innerHTML = '<span class="a">+' + adds + '</span> <span class="d">-' + dels + '</span>';
        li.appendChild(counts);

        li.addEventListener('click', function () {
            card.classList.remove('collapsed');
            card.scrollIntoView({ behavior: 'smooth', block: 'start' });
        });
        fileList.appendChild(li);
    });

    // Highlight the currently-visible file in the sidebar.
    if (cards.length > 0 && 'IntersectionObserver' in window) {
        var visible = {};
        var observer = new IntersectionObserver(function (entries) {
            entries.forEach(function (e) {
                visible[e.target.id] = e.isIntersecting;
            });
            // Pick the first visible card in document order.
            var activeId = null;
            for (var i = 0; i < cards.length; i++) {
                if (visible[cards[i].id]) { activeId = cards[i].id; break; }
            }
            document.querySelectorAll('.file-list li').forEach(function (li) {
                li.classList.toggle('active', li.getAttribute('data-target') === activeId);
            });
        }, { rootMargin: '-60px 0px -60% 0px' });
        cards.forEach(function (c) { observer.observe(c); });
    }

    // ----- Sidebar show/hide (persisted).
    var hideBtn = document.getElementById('sidebar-hide');
    var showBtn = document.getElementById('sidebar-show');
    function setSidebar(hidden) {
        document.body.classList.toggle('sidebar-hidden', hidden);
        try { localStorage.setItem('gd2h-sidebar', hidden ? 'hidden' : 'shown'); } catch (_) {}
    }
    try {
        if (localStorage.getItem('gd2h-sidebar') === 'hidden') setSidebar(true);
    } catch (_) {}
    if (hideBtn) hideBtn.addEventListener('click', function () { setSidebar(true); });
    if (showBtn) showBtn.addEventListener('click', function () { setSidebar(false); });

    // ----- Build the side-by-side table for each unified table.
    function mkTd(cls, html) {
        var td = document.createElement('td');
        td.className = cls;
        td.innerHTML = html;
        return td;
    }
    function buildSbs(unifiedTable) {
        var sbs = document.createElement('table');
        sbs.className = 'diff-table sbs';
        var tbody = document.createElement('tbody');
        sbs.appendChild(tbody);

        var rows = Array.prototype.slice.call(unifiedTable.querySelectorAll('tbody > tr'));
        var i = 0;
        while (i < rows.length) {
            var r = rows[i];
            if (r.classList.contains('hunk') || r.classList.contains('binary') || r.classList.contains('nonewline')) {
                var tr = document.createElement('tr');
                tr.className = r.className;
                var td = document.createElement('td');
                td.colSpan = 4;
                td.className = 'code';
                var srcTd = r.querySelector('td.code') || r.querySelector('td[colspan]') || r.querySelector('td');
                td.innerHTML = srcTd.innerHTML;
                tr.appendChild(td);
                tbody.appendChild(tr);
                i++;
                continue;
            }
            if (r.classList.contains('ctx')) {
                var tds = r.querySelectorAll('td');
                var ll = tds[0].textContent;
                var rl = tds[1].textContent;
                var code = tds[2].innerHTML;
                if (code.charAt(0) === ' ') code = code.substring(1);
                var tr2 = document.createElement('tr');
                tr2.className = 'ctx';
                tr2.appendChild(mkTd('ln', ll));
                tr2.appendChild(mkTd('code ctx', code));
                tr2.appendChild(mkTd('ln', rl));
                tr2.appendChild(mkTd('code ctx', code));
                tbody.appendChild(tr2);
                i++;
                continue;
            }
            // Collect consecutive del rows then consecutive add rows.
            var dels = [];
            while (i < rows.length && rows[i].classList.contains('del')) { dels.push(rows[i]); i++; }
            var adds = [];
            while (i < rows.length && rows[i].classList.contains('add')) { adds.push(rows[i]); i++; }
            var maxN = Math.max(dels.length, adds.length);
            for (var j = 0; j < maxN; j++) {
                var d = dels[j], a = adds[j];
                var cls = (d && a) ? 'mod' : (d ? 'del' : 'add');
                var tr3 = document.createElement('tr');
                tr3.className = cls;
                if (d) {
                    var dtds = d.querySelectorAll('td');
                    var dln = dtds[0].textContent;
                    var dcode = dtds[2].innerHTML;
                    if (dcode.charAt(0) === '-') dcode = dcode.substring(1);
                    tr3.appendChild(mkTd('ln del', dln));
                    tr3.appendChild(mkTd('code del', dcode));
                } else {
                    tr3.appendChild(mkTd('ln empty', ''));
                    tr3.appendChild(mkTd('code empty', ''));
                }
                if (a) {
                    var atds = a.querySelectorAll('td');
                    var aln = atds[1].textContent;
                    var acode = atds[2].innerHTML;
                    if (acode.charAt(0) === '+') acode = acode.substring(1);
                    tr3.appendChild(mkTd('ln add', aln));
                    tr3.appendChild(mkTd('code add', acode));
                } else {
                    tr3.appendChild(mkTd('ln empty', ''));
                    tr3.appendChild(mkTd('code empty', ''));
                }
                tbody.appendChild(tr3);
            }
        }
        return sbs;
    }
    document.querySelectorAll('table.diff-table.unified').forEach(function (t) {
        var sbs = buildSbs(t);
        t.parentNode.insertBefore(sbs, t.nextSibling);
    });

    // ----- Theme toggle (persisted in localStorage).
    var themeBtn = document.getElementById('theme-toggle');
    function applyTheme(theme) {
        if (theme === 'dark') document.body.classList.add('theme-dark');
        else document.body.classList.remove('theme-dark');
    }
    try {
        var saved = localStorage.getItem('gd2h-theme');
        if (saved) applyTheme(saved);
    } catch (_) {}
    themeBtn.addEventListener('click', function () {
        var isDark = document.body.classList.toggle('theme-dark');
        try { localStorage.setItem('gd2h-theme', isDark ? 'dark' : 'light'); } catch (_) {}
    });

    // ----- View toggle (unified / split).
    var currentView = document.body.classList.contains('view-split') ? 'split' : 'unified';
    var viewButtons = document.querySelectorAll('.view-toggle button');

    function setView(view) {
        currentView = view;
        if (view === 'split') document.body.classList.add('view-split');
        else document.body.classList.remove('view-split');
        viewButtons.forEach(function (b) {
            b.classList.toggle('active', b.getAttribute('data-view') === view);
        });
        try { localStorage.setItem('gd2h-view', view); } catch (_) {}
        rebuildGroups();
    }
    try {
        var savedView = localStorage.getItem('gd2h-view');
        if (savedView === 'unified' || savedView === 'split') setView(savedView);
    } catch (_) {}
    viewButtons.forEach(function (b) {
        b.addEventListener('click', function () { setView(b.getAttribute('data-view')); });
    });

    // ----- Change navigator (prev/next). Groups depend on current view.
    var idx = -1;
    var groups = [];
    var prevBtn = document.getElementById('nav-prev');
    var nextBtn = document.getElementById('nav-next');
    var counter = document.getElementById('nav-counter');

    function isChange(r) {
        return r.classList.contains('add') || r.classList.contains('del') || r.classList.contains('mod');
    }
    function rebuildGroups() {
        var sel = (currentView === 'split')
            ? 'table.diff-table.sbs > tbody > tr'
            : 'table.diff-table.unified > tbody > tr';
        var rows = Array.prototype.slice.call(document.querySelectorAll(sel));
        groups = [];
        for (var i = 0; i < rows.length; i++) {
            if (isChange(rows[i])) {
                var prev = rows[i].previousElementSibling;
                if (!prev || !isChange(prev)) groups.push(rows[i]);
            }
        }
        idx = -1;
        prevBtn.disabled = nextBtn.disabled = (groups.length === 0);
        updateCounter();
    }
    function updateCounter() {
        counter.textContent = (idx < 0 ? 0 : idx + 1) + ' / ' + groups.length;
    }
    function goTo(i) {
        if (groups.length === 0) return;
        idx = ((i % groups.length) + groups.length) % groups.length;
        var target = groups[idx];
        var card = target.closest('.file-card');
        if (card) card.classList.remove('collapsed');
        target.scrollIntoView({ behavior: 'smooth', block: 'center' });
        groups.forEach(function (g) { g.classList.remove('flash'); });
        target.classList.add('flash');
        updateCounter();
    }

    prevBtn.addEventListener('click', function () { goTo(idx < 0 ? groups.length - 1 : idx - 1); });
    nextBtn.addEventListener('click', function () { goTo(idx + 1); });
    document.addEventListener('keydown', function (e) {
        var t = e.target;
        if (t && (t.tagName === 'INPUT' || t.tagName === 'TEXTAREA' || t.isContentEditable)) return;
        if (e.ctrlKey || e.metaKey || e.altKey) return;
        if (e.key === 'n' || e.key === 'j') {
            e.preventDefault();
            goTo(idx + 1);
        } else if (e.key === 'p' || e.key === 'k') {
            e.preventDefault();
            goTo(idx < 0 ? groups.length - 1 : idx - 1);
        } else if (e.key === 'Tab') {
            e.preventDefault();
            goTo(e.shiftKey ? (idx < 0 ? groups.length - 1 : idx - 1) : (idx + 1));
        }
    });

    rebuildGroups();
})();
</script>
</body>
</html>
HTML_FOOT
} > "$OUTPUT"

echo "Wrote $OUTPUT ($FILES_CHANGED file(s) changed, +$INSERTIONS / -$DELETIONS)"
