#!/usr/bin/env bash
#
# git_diff_to_html.sh
#
# Generate a self-contained, Bitbucket-style HTML page from a git diff.
#
# Usage:
#   git_diff_to_html.sh [options] [<commit-range>]
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
#       --whitespace ST  Initial whitespace markers: "on" (default) or "off".
#                        A toggle is always present in the page.
#       --collapse ST    Initial collapse-unchanged: "on" (default) or "off".
#                        A toggle is always present in the page.
#   -h, --help           Show this help message and exit
#
# Arguments:
#   <commit-range>       Any git revision range, e.g. HEAD~3..HEAD,
#                        main..feature, or a single commit SHA.
#                        Defaults to the last commit (HEAD~1..HEAD).
#
# Examples:
#   git_diff_to_html.sh                          # last commit, full files
#   git_diff_to_html.sh HEAD~5..HEAD
#   git_diff_to_html.sh -o review.html main..feature
#   git_diff_to_html.sh -U 3 HEAD~1..HEAD        # compact 3-line context
#   git_diff_to_html.sh --view split --theme dark HEAD~1..HEAD
#   git_diff_to_html.sh abc1234                  # that single commit

set -euo pipefail

OUTPUT="git_diff.html"
TITLE=""
RANGE=""
CONTEXT_LINES="1000000"
VIEW_MODE="unified"
THEME="light"
WHITESPACE="on"
COLLAPSE="on"

usage() {
    sed -n '3,37p' "$0" | sed 's/^# \{0,1\}//'
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
        --whitespace)
            [[ $# -ge 2 ]] || { echo "Error: $1 requires an argument" >&2; exit 2; }
            case "$2" in
                on|off) WHITESPACE="$2" ;;
                *) echo "Error: --whitespace expects 'on' or 'off'" >&2; exit 2 ;;
            esac
            shift 2 ;;
        --collapse)
            [[ $# -ge 2 ]] || { echo "Error: $1 requires an argument" >&2; exit 2; }
            case "$2" in
                on|off) COLLAPSE="$2" ;;
                *) echo "Error: --collapse expects 'on' or 'off'" >&2; exit 2 ;;
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
<link rel="icon" type="image/svg+xml" href="data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 32 32'%3E%3Crect width='32' height='32' rx='6' fill='%23282c34'/%3E%3Ctext x='4' y='13' font-family='monospace' font-size='10' fill='%23e06c75'%3E-%3C/text%3E%3Crect x='12' y='6' width='14' height='4' rx='1' fill='%23e06c75' opacity='.6'/%3E%3Ctext x='4' y='24' font-family='monospace' font-size='10' fill='%2398c379'%3E+%3C/text%3E%3Crect x='12' y='17' width='16' height='4' rx='1' fill='%2398c379' opacity='.6'/%3E%3Crect x='12' y='24' width='10' height='4' rx='1' fill='%2398c379' opacity='.6'/%3E%3C/svg%3E">
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
    --syn-keyword: #d73a49;
    --syn-string:  #032f62;
    --syn-number:  #005cc5;
    --syn-comment: #6a737d;
    --syn-title:   #6f42c1;
    --syn-variable:#e36209;
    --syn-type:    #005cc5;
    --syn-tag:     #22863a;
    --syn-attr:    #6f42c1;
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
    --syn-keyword: #ff7b72;
    --syn-string:  #a5d6ff;
    --syn-number:  #79c0ff;
    --syn-comment: #8b949e;
    --syn-title:   #d2a8ff;
    --syn-variable:#ffa657;
    --syn-type:    #79c0ff;
    --syn-tag:     #7ee787;
    --syn-attr:    #d2a8ff;
}
.hljs-keyword, .hljs-selector-tag, .hljs-built_in, .hljs-section, .hljs-link,
.hljs-meta-keyword, .hljs-doctag { color: var(--syn-keyword); }
.hljs-string, .hljs-symbol, .hljs-bullet, .hljs-addition,
.hljs-regexp, .hljs-meta-string { color: var(--syn-string); }
.hljs-number, .hljs-literal { color: var(--syn-number); }
.hljs-comment, .hljs-quote, .hljs-meta { color: var(--syn-comment); font-style: italic; }
.hljs-title, .hljs-name, .hljs-selector-id, .hljs-selector-class,
.hljs-function .hljs-title { color: var(--syn-title); }
.hljs-variable, .hljs-template-variable, .hljs-params { color: var(--syn-variable); }
.hljs-type, .hljs-class .hljs-title, .hljs-title.class_ { color: var(--syn-type); }
.hljs-tag { color: var(--syn-tag); }
.hljs-attr, .hljs-attribute { color: var(--syn-attr); }
.hljs-deletion { color: var(--del-text); }
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
    padding: 16px 24px;
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
    align-items: stretch;
    min-height: calc(100vh - 60px);
}
.sidebar {
    flex: 0 0 260px;
    position: sticky;
    top: 0;
    height: 100vh;
    overflow-y: auto;
    background: var(--card-bg);
    border-right: 1px solid var(--border);
    font-size: 13px;
    display: flex;
    flex-direction: column;
}
.sidebar-header {
    position: sticky;
    top: 0;
    background: var(--card-bg);
    border-bottom: 1px solid var(--border);
    padding: 12px 14px 8px;
    display: flex;
    align-items: center;
    justify-content: space-between;
    font-weight: 600;
    font-size: 12px;
    text-transform: uppercase;
    letter-spacing: 0.5px;
    color: var(--muted);
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
.sidebar-filter {
    padding: 10px 8px;
    position: sticky;
    top: 38px;
    background: var(--card-bg);
    z-index: 1;
}
.sidebar-filter input {
    width: 100%;
    padding: 5px 8px;
    border: 1px solid var(--border);
    border-radius: 4px;
    background: var(--bg);
    color: var(--text);
    font-size: 12px;
    font-family: inherit;
    outline: none;
}
.sidebar-filter input::placeholder { color: var(--muted); }
.sidebar-filter input:focus { border-color: var(--accent); }
.file-list {
    list-style: none;
    margin: 0;
    padding: 2px 0;
    flex: 1;
    overflow-y: auto;
}
.file-list li {
    display: flex;
    align-items: center;
    gap: 8px;
    padding: 5px 12px;
    cursor: pointer;
    border-left: 3px solid transparent;
    transition: background 0.1s;
}
.file-list li:hover { background: var(--file-header-hover); }
.file-list li.active {
    background: var(--file-header-hover);
    border-left-color: var(--accent);
}
.file-list li.hidden { display: none; }
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
    top: 50%;
    left: 0;
    transform: translateY(-50%);
    z-index: 90;
    width: 28px;
    height: 100vh;
    padding: 0;
    border-radius: 0;
    background: var(--card-bg);
    border: 1px solid var(--border);
    border-left: none;
    color: var(--muted);
    cursor: pointer;
    box-shadow: var(--shadow);
    font-size: 14px;
    line-height: 1;
    display: none;
    transition: color 0.15s;
}
#sidebar-show:hover { color: var(--text); background: var(--file-header-hover); }
body.sidebar-hidden .sidebar { display: none; }
body.sidebar-hidden #sidebar-show { display: inline-flex; align-items: center; justify-content: center; }
body.sidebar-hidden .content { padding-left: 28px; }
.content {
    flex: 1;
    min-width: 0;
    overflow: clip;
}
main {
    padding: 0 24px 0 24px;
    margin-top: 24px;
}
.summary {
    background: var(--card-bg);
    border: 1px solid var(--border);
    border-radius: 3px;
    padding: 14px 18px;
    margin-bottom: 20px;
    position: sticky;
    top: 0;
    z-index: 3;
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
.ws-toggle {
    display: inline-flex;
    align-items: center;
    gap: 6px;
    background: var(--button-bg);
    border: 1px solid var(--border);
    border-radius: 3px;
    padding: 0 10px;
    height: 30px;
    font-size: 12px;
    font-weight: 600;
    color: var(--button-text);
    cursor: pointer;
    user-select: none;
}
.ws-toggle:hover { background: var(--file-header-hover); }
.ws-toggle input { margin: 0; cursor: pointer; }
.ws-mark { color: var(--muted); opacity: 0.65; }
.commit-list {
    background: var(--card-bg);
    border: 1px solid var(--border);
    border-radius: 3px;
    padding: 10px 18px;
    margin-bottom: 20px;
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
    overflow: clip;
    scroll-margin-top: var(--summary-height, 0px);
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
    position: sticky;
    top: var(--summary-height, 0px);
    z-index: 2;
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
    min-width: 40px;
    max-width: 50px;
    padding: 0 6px;
    text-align: right;
    color: var(--muted);
    background: var(--ln-bg);
    border-right: 1px solid var(--border);
    user-select: none;
    overflow: hidden;
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
tr.del .word-diff, td.code.del .word-diff {
    background: var(--del-ln-bg);
    border-radius: 2px;
}
tr.add .word-diff, td.code.add .word-diff {
    background: var(--add-ln-bg);
    border-radius: 2px;
}
tr.nonewline td { color: var(--muted); font-style: italic; }
tr.binary td    { color: var(--muted); font-style: italic; padding: 10px 14px; }
.file-card.collapsed .diff-body { display: none; }
.file-card.collapsed .file-header .toggle::before { content: "▸ "; }
.file-card .file-header .toggle::before { content: "▾ "; }

/* ----- Split (side-by-side) view ----- */
table.diff-table.sbs { display: none; }
body.view-split table.diff-table.unified { display: none; }
body.view-split table.diff-table.sbs     { display: table; }
table.diff-table.sbs td.ln {
    width: 40px;
    min-width: 40px;
    max-width: 50px;
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
    padding: 0 0 30px 0;
}
footer a { color: var(--muted); }
.nav-buttons {
    display: inline-flex;
    align-items: center;
    gap: 6px;
    font-size: 13px;
}
.nav-buttons button {
    background: var(--button-bg);
    color: var(--button-text);
    border: 1px solid var(--border);
    padding: 0 10px;
    height: 30px;
    border-radius: 3px;
    cursor: pointer;
    font-size: 12px;
    font-weight: 600;
    font-family: inherit;
}
.nav-buttons button:hover:not(:disabled) { background: var(--file-header-hover); }
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
    font-size: 12px;
}
tr.collapse-placeholder td {
    background: var(--hunk-bg);
    color: var(--hunk-color);
    font-style: italic;
    text-align: left;
    cursor: pointer;
    padding: 4px 8px;
    user-select: none;
}
tr.collapse-placeholder td .cph-text {
    position: sticky;
    left: 8px;
    display: inline-block;
}
tr.collapse-placeholder:hover td { background: var(--file-header-hover); }
tr.flash > td {
    animation: flash 1.2s ease-out;
}
@keyframes flash {
    0%   { box-shadow: inset 3px 0 0 #ff991f; }
    100% { box-shadow: inset 3px 0 0 transparent; }
}
</style>
<script src="https://cdnjs.cloudflare.com/ajax/libs/highlight.js/11.9.0/highlight.min.js"></script>
</head>
<body class="$([ "$THEME" = "dark" ] && echo -n "theme-dark ")$([ "$VIEW_MODE" = "split" ] && echo -n "view-split ")" data-initial-view="$(html_escape "$VIEW_MODE")" data-initial-theme="$(html_escape "$THEME")" data-initial-ws="$(html_escape "$WHITESPACE")" data-initial-collapse="$(html_escape "$COLLAPSE")">
<button type="button" id="sidebar-show" title="Show files sidebar" aria-label="Show sidebar"><svg viewBox="0 0 24 24" width="14" height="14" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><polyline points="9 6 15 12 9 18"/></svg></button>
<div class="layout">
<aside class="sidebar" aria-label="Files">
    <div class="sidebar-header">
        <span>Files (${FILES_CHANGED})</span>
        <button type="button" id="sidebar-hide" title="Hide sidebar" aria-label="Hide sidebar">&times;</button>
    </div>
    <div class="sidebar-filter">
        <input type="text" id="file-filter" placeholder="Filter files…" autocomplete="off" spellcheck="false">
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
            <div class="nav-buttons" role="group" aria-label="Change navigator">
                <button type="button" id="nav-prev" title="Previous change (p / k / Shift+Tab)">&uarr; Prev</button>
                <span class="counter" id="nav-counter">0 / 0</span>
                <button type="button" id="nav-next" title="Next change (n / j / Tab)">&darr; Next</button>
            </div>
            <div class="view-toggle" role="group" aria-label="View mode">
                <button type="button" data-view="unified"$([ "$VIEW_MODE" = "unified" ] && echo -n ' class="active"')>Unified</button>
                <button type="button" data-view="split"$([ "$VIEW_MODE" = "split" ] && echo -n ' class="active"')>Split</button>
            </div>
            <label class="ws-toggle" title="Show whitespace characters (&middot; for space, &rarr; for tab)">
                <input type="checkbox" id="ws-toggle">
                <span>Whitespace</span>
            </label>
            <label class="ws-toggle" title="Collapse unchanged context, keeping 30 lines around each change">
                <input type="checkbox" id="collapse-toggle">
                <span>Collapse</span>
            </label>
            <button type="button" id="theme-toggle" title="Toggle dark / light theme" aria-label="Toggle theme">
                <span class="moon">&#9790;</span><span class="sun">&#9788;</span>
            </button>
        </div>
    </div>
</section>
HTML_HEAD

# ----- commit list -----
if [[ "$RANGE" == *..* ]]; then
    LOG_OUTPUT=$(git log --pretty=format:'%h%x1f%an%x1f%ad%x1f%s' --date=short "$RANGE" 2>/dev/null || true)
else
    LOG_OUTPUT=$(git log -1 --pretty=format:'%h%x1f%an%x1f%ad%x1f%s' --date=short "$RANGE" 2>/dev/null || true)
fi

if [[ -n "$LOG_OUTPUT" ]]; then
    echo '<section class="commit-list">'
    while IFS=$'\x1f' read -r sha author adate subject; do
        [[ -z "$sha" ]] && continue
        printf '        <div class="row"><span class="sha">%s</span><span class="subject">%s</span><span class="author">%s</span><span class="date">%s</span></div>\n' \
            "$(html_escape "$sha")" \
            "$(html_escape "$subject")" \
            "$(html_escape "$author")" \
            "$(html_escape "$adate")"
    done <<< "$LOG_OUTPUT"
    echo '</section>'
fi

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
<footer>Generated by <a href="https://github.com/MickaelBlet/GitDiffToHtml">git_diff_to_html.sh</a></footer>
</div><!-- /.content -->
</div><!-- /.layout -->
<script>
(function () {
    // ----- Keep --summary-height in sync so sticky file headers sit below the toolbar.
    var summaryEl = document.querySelector('.summary');
    if (summaryEl) {
        var syncSummaryHeight = function () {
            document.documentElement.style.setProperty('--summary-height', summaryEl.offsetHeight + 'px');
        };
        syncSummaryHeight();
        window.addEventListener('resize', syncSummaryHeight);
        if ('ResizeObserver' in window) new ResizeObserver(syncSummaryHeight).observe(summaryEl);
    }

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
    if (cards.length > 0) {
        var lis = document.querySelectorAll('.file-list li');
        var currentActiveId = null;
        var updateActive = function () {
            var offset = (parseInt(getComputedStyle(document.documentElement).getPropertyValue('--summary-height')) || 0) + 1;
            var activeId = cards[0].id;
            for (var i = 0; i < cards.length; i++) {
                if (cards[i].getBoundingClientRect().top <= offset) activeId = cards[i].id;
                else break;
            }
            if (activeId === currentActiveId) return;
            currentActiveId = activeId;
            lis.forEach(function (li) {
                li.classList.toggle('active', li.getAttribute('data-target') === activeId);
            });
        };
        var ticking = false;
        var onScroll = function () {
            if (ticking) return;
            ticking = true;
            requestAnimationFrame(function () { ticking = false; updateActive(); });
        };
        window.addEventListener('scroll', onScroll, { passive: true });
        window.addEventListener('resize', onScroll);
        updateActive();
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

    // ----- Sidebar file filter.
    var filterInput = document.getElementById('file-filter');
    if (filterInput) {
        filterInput.addEventListener('input', function () {
            var q = filterInput.value.toLowerCase();
            document.querySelectorAll('.file-list li').forEach(function (li) {
                var match = !q || (li.title || '').toLowerCase().indexOf(q) >= 0;
                li.classList.toggle('hidden', !match);
            });
        });
    }

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
    // ----- Syntax highlighting (per-line, before SbS so both views get it).
    var extLang = {
        js:'javascript', mjs:'javascript', cjs:'javascript', jsx:'javascript',
        ts:'typescript', tsx:'typescript',
        py:'python', rb:'ruby', go:'go', rs:'rust',
        java:'java', kt:'kotlin', kts:'kotlin', swift:'swift', scala:'scala',
        c:'c', h:'c', cpp:'cpp', cc:'cpp', cxx:'cpp', hpp:'cpp', hh:'cpp', hxx:'cpp',
        cs:'csharp', php:'php', pl:'perl', pm:'perl', lua:'lua', r:'r',
        sh:'bash', bash:'bash', zsh:'bash',
        json:'json', yaml:'yaml', yml:'yaml', toml:'ini', ini:'ini',
        xml:'xml', html:'xml', htm:'xml', svg:'xml', vue:'xml',
        css:'css', scss:'scss', sass:'scss', less:'less',
        md:'markdown', markdown:'markdown',
        sql:'sql', dockerfile:'dockerfile', mk:'makefile', make:'makefile'
    };
    function detectLang(path) {
        var base = (path.split('/').pop() || '').toLowerCase();
        if (base === 'dockerfile') return 'dockerfile';
        if (base === 'makefile' || base === 'gnumakefile') return 'makefile';
        var dot = base.lastIndexOf('.');
        if (dot < 0) return null;
        return extLang[base.substring(dot + 1)] || null;
    }
    function highlightCard(card) {
        if (!window.hljs) return;
        var pathEl = card.querySelector('.file-header .path');
        if (!pathEl) return;
        var p = pathEl.textContent;
        var arrow = p.indexOf('\u2192');
        if (arrow >= 0) p = p.substring(arrow + 1).trim();
        var lang = detectLang(p);
        if (!lang || !hljs.getLanguage(lang)) return;
        card.querySelectorAll('table.unified > tbody > tr').forEach(function (tr) {
            if (!(tr.classList.contains('ctx') || tr.classList.contains('add') || tr.classList.contains('del'))) return;
            var tds = tr.querySelectorAll('td');
            var td = tds[2];
            if (!td) return;
            var text = td.textContent;
            if (text.length === 0) return;
            var prefix = text.charAt(0);
            var rest = text.substring(1);
            try {
                var res = hljs.highlight(rest, { language: lang, ignoreIllegals: true });
                // Escape prefix char.
                var pe = prefix === '<' ? '&lt;' : prefix === '>' ? '&gt;' : prefix === '&' ? '&amp;' : prefix;
                td.innerHTML = pe + res.value;
            } catch (_) {}
        });
    }
    document.querySelectorAll('.file-card').forEach(highlightCard);

    // ----- Intra-line (word-level) highlighting, Bitbucket-style.
    function wordDiff(a, b) {
        var re = /\s+|[A-Za-z0-9_]+|[^\sA-Za-z0-9_]/g;
        var at = a.match(re) || [];
        var bt = b.match(re) || [];
        var n = at.length, m = bt.length;
        if (n * m > 40000) return null;
        var dp = new Array(n + 1);
        for (var i = 0; i <= n; i++) dp[i] = new Int16Array(m + 1);
        for (var i = 1; i <= n; i++) {
            for (var j = 1; j <= m; j++) {
                dp[i][j] = at[i - 1] === bt[j - 1]
                    ? dp[i - 1][j - 1] + 1
                    : (dp[i - 1][j] >= dp[i][j - 1] ? dp[i - 1][j] : dp[i][j - 1]);
            }
        }
        var aMark = new Array(n), bMark = new Array(m);
        var ci = n, cj = m;
        while (ci > 0 && cj > 0) {
            if (at[ci - 1] === bt[cj - 1]) { ci--; cj--; }
            else if (dp[ci - 1][cj] >= dp[ci][cj - 1]) { aMark[ci - 1] = true; ci--; }
            else { bMark[cj - 1] = true; cj--; }
        }
        while (ci > 0) { aMark[--ci] = true; }
        while (cj > 0) { bMark[--cj] = true; }
        function ranges(tokens, marks) {
            var res = [], pos = 0, cur = null;
            for (var k = 0; k < tokens.length; k++) {
                var len = tokens[k].length;
                var isWs = /^\s+$/.test(tokens[k]);
                if (marks[k] && !isWs) {
                    if (cur && cur[1] === pos) cur[1] = pos + len;
                    else { cur = [pos, pos + len]; res.push(cur); }
                } else {
                    cur = null;
                }
                pos += len;
            }
            return res;
        }
        return { a: ranges(at, aMark), b: ranges(bt, bMark) };
    }
    function wrapCharRanges(html, ranges, cls) {
        if (!ranges || !ranges.length) return html;
        var out = '', pos = 0, ri = 0, inSpan = false;
        var i = 0, L = html.length;
        function sync() {
            while (ri < ranges.length && pos >= ranges[ri][1]) {
                if (inSpan) { out += '</span>'; inSpan = false; }
                ri++;
            }
            if (!inSpan && ri < ranges.length && pos >= ranges[ri][0] && pos < ranges[ri][1]) {
                out += '<span class="' + cls + '">';
                inSpan = true;
            }
        }
        while (i < L) {
            var c = html.charAt(i);
            if (c === '<') {
                var wasIn = inSpan;
                if (inSpan) { out += '</span>'; inSpan = false; }
                var e = html.indexOf('>', i);
                if (e < 0) e = L - 1;
                out += html.substring(i, e + 1);
                i = e + 1;
                if (wasIn) { out += '<span class="' + cls + '">'; inSpan = true; }
                continue;
            }
            sync();
            if (c === '&') {
                var s = html.indexOf(';', i);
                if (s < 0) { out += c; i++; pos++; continue; }
                out += html.substring(i, s + 1);
                i = s + 1;
            } else {
                out += c;
                i++;
            }
            pos++;
        }
        sync();
        if (inSpan) out += '</span>';
        return out;
    }
    function applyIntraLineUnified(table) {
        var rows = Array.prototype.slice.call(table.querySelectorAll(':scope > tbody > tr'));
        var i = 0;
        while (i < rows.length) {
            if (!rows[i].classList.contains('del')) { i++; continue; }
            var dels = [];
            while (i < rows.length && rows[i].classList.contains('del')) { dels.push(rows[i]); i++; }
            var adds = [];
            while (i < rows.length && rows[i].classList.contains('add')) { adds.push(rows[i]); i++; }
            var n = Math.min(dels.length, adds.length);
            for (var k = 0; k < n; k++) {
                var dTd = dels[k].querySelectorAll('td')[2];
                var aTd = adds[k].querySelectorAll('td')[2];
                if (!dTd || !aTd) continue;
                var dText = dTd.textContent;
                var aText = aTd.textContent;
                if (dText.charAt(0) === '-') dText = dText.substring(1);
                if (aText.charAt(0) === '+') aText = aText.substring(1);
                if (dText === aText) continue;
                var diff = wordDiff(dText, aText);
                if (!diff) continue;
                // innerHTML has the prefix char at position 0, so shift ranges by +1.
                var dR = diff.a.map(function (r) { return [r[0] + 1, r[1] + 1]; });
                var aR = diff.b.map(function (r) { return [r[0] + 1, r[1] + 1]; });
                dTd.innerHTML = wrapCharRanges(dTd.innerHTML, dR, 'word-diff');
                aTd.innerHTML = wrapCharRanges(aTd.innerHTML, aR, 'word-diff');
            }
        }
    }
    document.querySelectorAll('table.diff-table.unified').forEach(applyIntraLineUnified);

    document.querySelectorAll('table.diff-table.unified').forEach(function (t) {
        var sbs = buildSbs(t);
        t.parentNode.insertBefore(sbs, t.nextSibling);
    });

    // ----- Collapse unchanged context (keep 30 lines around each change).
    var collapseCheckbox = document.getElementById('collapse-toggle');
    var COLLAPSE_CONTEXT = 30;
    function applyCollapse(on) {
        document.querySelectorAll('table.diff-table').forEach(function (table) {
            table.querySelectorAll('tr.collapse-placeholder').forEach(function (tr) { tr.remove(); });
            table.querySelectorAll('tr.ctx-hidden').forEach(function (tr) {
                tr.style.display = '';
                tr.classList.remove('ctx-hidden');
            });
            if (!on) return;
            var rows = Array.prototype.slice.call(table.querySelectorAll(':scope > tbody > tr'));
            var keep = new Array(rows.length);
            for (var i = 0; i < rows.length; i++) {
                var r = rows[i];
                if (r.classList.contains('add') || r.classList.contains('del') || r.classList.contains('mod')) {
                    var lo = Math.max(0, i - COLLAPSE_CONTEXT);
                    var hi = Math.min(rows.length - 1, i + COLLAPSE_CONTEXT);
                    for (var j = lo; j <= hi; j++) keep[j] = true;
                } else if (!r.classList.contains('ctx')) {
                    keep[i] = true;
                }
            }
            var isSbs = table.classList.contains('sbs');
            var cols = isSbs ? 4 : 3;
            var k = 0;
            while (k < rows.length) {
                if (!keep[k] && rows[k].classList.contains('ctx')) {
                    var start = k;
                    while (k < rows.length && !keep[k] && rows[k].classList.contains('ctx')) {
                        rows[k].classList.add('ctx-hidden');
                        rows[k].style.display = 'none';
                        k++;
                    }
                    var count = k - start;
                    var hiddenGroup = rows.slice(start, k);
                    var ph = document.createElement('tr');
                    ph.className = 'collapse-placeholder';
                    ph.innerHTML = '<td colspan="' + cols + '"><span class="cph-text">&hellip; ' + count + ' unchanged line' + (count === 1 ? '' : 's') + ' (click to expand)</span></td>';
                    (function (group, placeholder) {
                        placeholder.addEventListener('click', function () {
                            group.forEach(function (r) {
                                r.style.display = '';
                                r.classList.remove('ctx-hidden');
                            });
                            placeholder.remove();
                        });
                    })(hiddenGroup, ph);
                    rows[start].parentNode.insertBefore(ph, rows[start]);
                } else {
                    k++;
                }
            }
        });
    }
    try {
        var savedCollapse = localStorage.getItem('gd2h-collapse');
        var collapseOn = savedCollapse === null
            ? (document.body.getAttribute('data-initial-collapse') === 'on')
            : (savedCollapse === 'on');
        if (collapseOn) {
            collapseCheckbox.checked = true;
            applyCollapse(true);
        }
    } catch (_) {}
    collapseCheckbox.addEventListener('change', function () {
        var on = collapseCheckbox.checked;
        applyCollapse(on);
        try { localStorage.setItem('gd2h-collapse', on ? 'on' : 'off'); } catch (_) {}
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

    // ----- Whitespace toggle (persisted). Wraps spaces/tabs in spans so CSS
    //       can overlay markers without changing the underlying characters.
    var wsCheckbox = document.getElementById('ws-toggle');
    function transformWs(html) {
        // Only substitute inside text nodes — skip attributes/tags so
        // syntax-highlight markup stays intact. Tab is kept after the
        // arrow so it still advances to the next tab stop.
        return html.replace(/(<[^>]*>)|([^<]+)/g, function (_, tag, text) {
            if (tag) return tag;
            return text
                .replace(/ /g, '\x00')
                .replace(/\t/g, '\x01')
                .replace(/\x00/g, '<span class="ws-mark">\u00B7</span>')
                .replace(/\x01/g, '<span class="ws-mark">\u2192</span>\t');
        });
    }
    function applyWs(on) {
        document.querySelectorAll('td.code').forEach(function (td) {
            if (on) {
                if (td.dataset.orig === undefined) td.dataset.orig = td.innerHTML;
                // Unified-view cells start with the diff prefix (' ', '+', '-'),
                // which isn't part of the source line — skip it so its space
                // doesn't get marked.
                var src = td.dataset.orig;
                var skipPrefix = !!td.closest('table.unified') && src.length > 0;
                td.innerHTML = skipPrefix
                    ? src.charAt(0) + transformWs(src.substring(1))
                    : transformWs(src);
            } else if (td.dataset.orig !== undefined) {
                td.innerHTML = td.dataset.orig;
            }
        });
        document.body.classList.toggle('show-whitespace', on);
        wsCheckbox.checked = on;
    }
    try {
        var savedWs = localStorage.getItem('gd2h-ws');
        var wsOn = savedWs === null
            ? (document.body.getAttribute('data-initial-ws') === 'on')
            : (savedWs === 'on');
        if (wsOn) applyWs(true);
    } catch (_) {}
    wsCheckbox.addEventListener('change', function () {
        var on = wsCheckbox.checked;
        applyWs(on);
        try { localStorage.setItem('gd2h-ws', on ? 'on' : 'off'); } catch (_) {}
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

    // ----- Auto-jump to the first change on load.
    if (groups.length > 0 && !window.location.hash) {
        idx = 0;
        var first = groups[0];
        var card = first.closest('.file-card');
        if (card) card.classList.remove('collapsed');
        requestAnimationFrame(function () {
            first.scrollIntoView({ block: 'center' });
            first.classList.add('flash');
            updateCounter();
        });
    }
})();
</script>
</body>
</html>
HTML_FOOT
} > "$OUTPUT"

echo "Wrote $OUTPUT ($FILES_CHANGED file(s) changed, +$INSERTIONS / -$DELETIONS)"
