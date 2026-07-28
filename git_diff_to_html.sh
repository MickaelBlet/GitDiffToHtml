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
#   -w, --working        Diff the current work in progress: everything not yet
#                        committed (staged + unstaged), compared to HEAD.
#                        Untracked files are included too.
#       --staged         Diff only the staged changes (index vs HEAD).
#       --unstaged       Diff only the unstaged changes (work tree vs index),
#                        including untracked files.
#       --untracked ST   Include untracked files: "on" (default) or "off".
#                        Only meaningful with --working / --unstaged.
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
#       --colorblind ST  Initial colorblind-safe palette: "on" or "off"
#                        (default). Replaces the green/red add/delete colors
#                        with a blue/orange pair readable with deuteranopia
#                        or protanopia, in both the light and dark themes.
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
#   git_diff_to_html.sh --working                # current work in progress
#   git_diff_to_html.sh --staged                 # what would be committed
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
COLORBLIND="off"
SOURCE_MODE="range"   # range | working | staged | unstaged
UNTRACKED="on"

usage() {
    sed -n '3,48p' "$0" | sed 's/^# \{0,1\}//'
}

set_source_mode() {
    if [[ "$SOURCE_MODE" != "range" && "$SOURCE_MODE" != "$1" ]]; then
        echo "Error: --working, --staged and --unstaged are mutually exclusive" >&2
        exit 2
    fi
    SOURCE_MODE="$1"
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        -w|--working)
            set_source_mode working; shift ;;
        --staged|--cached)
            set_source_mode staged; shift ;;
        --unstaged)
            set_source_mode unstaged; shift ;;
        --untracked)
            [[ $# -ge 2 ]] || { echo "Error: $1 requires an argument" >&2; exit 2; }
            case "$2" in
                on|off) UNTRACKED="$2" ;;
                *) echo "Error: --untracked expects 'on' or 'off'" >&2; exit 2 ;;
            esac
            shift 2 ;;
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
        --colorblind)
            [[ $# -ge 2 ]] || { echo "Error: $1 requires an argument" >&2; exit 2; }
            case "$2" in
                on|off) COLORBLIND="$2" ;;
                *) echo "Error: --colorblind expects 'on' or 'off'" >&2; exit 2 ;;
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

TOPLEVEL=$(git rev-parse --show-toplevel)

# DIFF_ARGS holds the revision selector passed to `git diff`; it stays empty
# for the "unstaged" mode (work tree vs index).
DIFF_ARGS=()
SHOW_UNTRACKED="off"

if [[ "$SOURCE_MODE" == "range" ]]; then
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

    DIFF_ARGS=("$DIFF_RANGE")
else
    if [[ -n "$RANGE" ]]; then
        echo "Error: a commit range cannot be combined with --working / --staged / --unstaged" >&2
        exit 2
    fi

    # Compare against HEAD, or against the empty tree in a repo with no commit.
    if git rev-parse --verify -q HEAD >/dev/null 2>&1; then
        BASE_REV="HEAD"
    else
        BASE_REV=$(git hash-object -t tree /dev/null)
    fi

    case "$SOURCE_MODE" in
        working)
            RANGE="working tree (uncommitted)"
            DIFF_ARGS=("$BASE_REV")
            SHOW_UNTRACKED="$UNTRACKED" ;;
        staged)
            RANGE="staged changes"
            DIFF_ARGS=(--cached "$BASE_REV") ;;
        unstaged)
            RANGE="unstaged changes"
            SHOW_UNTRACKED="$UNTRACKED" ;;
    esac
fi

TITLE="${TITLE:-Git Diff: $RANGE}"

# ---------- untracked files ----------

# `git diff` never reports untracked files, so build a synthetic "new file"
# diff for each of them with `git diff --no-index` against /dev/null.
UNTRACKED_DIFF=""
UNTRACKED_COUNT=0
UNTRACKED_LINES=0
if [[ "$SHOW_UNTRACKED" == "on" ]]; then
    while IFS= read -r -d '' f; do
        d=$(git -C "$TOPLEVEL" diff --no-color --unified="$CONTEXT_LINES" \
                --no-index -- /dev/null "$f" 2>/dev/null || true)
        [[ -z "$d" ]] && continue
        UNTRACKED_DIFF+="$d"$'\n'
        UNTRACKED_COUNT=$((UNTRACKED_COUNT + 1))
        UNTRACKED_LINES=$((UNTRACKED_LINES + $(printf '%s\n' "$d" |
            awk '/^@@/ { in_hunk = 1; next } in_hunk && /^\+/ { n++ } END { print n + 0 }')))
    done < <(git -C "$TOPLEVEL" ls-files -z --others --exclude-standard)
fi

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
SHORTSTAT=$(git diff --shortstat ${DIFF_ARGS[@]+"${DIFF_ARGS[@]}"} 2>/dev/null || true)

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

# Untracked files are not part of the shortstat: add them by hand.
FILES_CHANGED=$((FILES_CHANGED + UNTRACKED_COUNT))
INSERTIONS=$((INSERTIONS + UNTRACKED_LINES))

# ---------- commit list ----------

# Built before the page so it can be embedded in the sidebar.
LOG_OUTPUT=""
# "on" when the range is written backwards (B..A): the diff then undoes the
# commits, so each per-commit diff has to be reversed as well.
REVERSED="off"
if [[ "$SOURCE_MODE" != "range" ]]; then
    LOG_OUTPUT=""
elif [[ "$RANGE" == *..* ]]; then
    LOG_OUTPUT=$(git log --pretty=format:'%h%x1f%an%x1f%ad%x1f%s' --date=short "$RANGE" 2>/dev/null || true)
    if [[ -z "$LOG_OUTPUT" && "$RANGE" != *...* ]]; then
        # A reversed range (e.g. HEAD..HEAD~5) lists no commits; log the other
        # way round so the page still shows what the diff undoes.
        LOG_OUTPUT=$(git log --pretty=format:'%h%x1f%an%x1f%ad%x1f%s' --date=short \
            "${RANGE#*..}..${RANGE%%..*}" 2>/dev/null || true)
        [[ -n "$LOG_OUTPUT" ]] && REVERSED="on"
    fi
else
    LOG_OUTPUT=$(git log -1 --pretty=format:'%h%x1f%an%x1f%ad%x1f%s' --date=short "$RANGE" 2>/dev/null || true)
fi

# Collect the commit SHAs so each one can get its own selectable diff.
COMMIT_SHAS=()
if [[ -n "$LOG_OUTPUT" ]]; then
    while IFS=$'\x1f' read -r sha _rest; do
        [[ -n "$sha" ]] && COMMIT_SHAS+=("$sha")
    done <<< "$LOG_OUTPUT"
fi

# Per-commit navigation only makes sense when the range holds several commits.
PER_COMMIT="off"
[[ ${#COMMIT_SHAS[@]} -gt 1 ]] && PER_COMMIT="on"

COMMIT_HTML=""
if [[ -n "$LOG_OUTPUT" ]]; then
    # Note: a command substitution that fails would abort the script (set -e),
    # so build the optional label with a plain if.
    REV_LABEL=""
    if [[ "$REVERSED" == "on" ]]; then
        REV_LABEL=" &middot; reversed"
    fi
    COMMIT_HTML+='    <div class="sidebar-section-title">'
    COMMIT_HTML+="<span>Commits (${#COMMIT_SHAS[@]})${REV_LABEL}</span>"
    COMMIT_HTML+='</div>'$'\n'
    COMMIT_HTML+='    <div class="commit-list">'$'\n'
    if [[ "$PER_COMMIT" == "on" ]]; then
        COMMIT_HTML+=$(printf '        <div class="row clickable all active" data-set="all"><span class="sha">all</span><span class="subject">All %d commits</span><span class="meta"></span></div>' \
            "${#COMMIT_SHAS[@]}")$'\n'
    fi
    while IFS=$'\x1f' read -r sha author adate subject; do
        [[ -z "$sha" ]] && continue
        COMMIT_HTML+=$(printf '        <div class="row%s"%s title="%s"><span class="sha">%s</span><span class="subject">%s</span><span class="meta"><span class="author">%s</span><span class="date">%s</span></span></div>' \
            "$([ "$PER_COMMIT" = "on" ] && echo -n ' clickable')" \
            "$([ "$PER_COMMIT" = "on" ] && printf ' data-set="%s"' "$(html_escape "$sha")")" \
            "$(html_escape "$subject")" \
            "$(html_escape "$sha")" \
            "$(html_escape "$subject")" \
            "$(html_escape "$author")" \
            "$(html_escape "$adate")")$'\n'
    done <<< "$LOG_OUTPUT"
    COMMIT_HTML+='    </div>'
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
/* Colorblind-safe palette (Okabe-Ito blue / vermillion) applied on top of
   whichever theme is active: additions turn blue, deletions orange. */
body.colorblind {
    --add-bg: #e8f1fb;
    --add-ln-bg: #cfe2f7;
    --add-text: #0b4f8a;
    --del-bg: #fdf1e5;
    --del-ln-bg: #fadcc0;
    --del-text: #8f4300;
    --status-added: #0072b2;
    --status-deleted: #d55e00;
    --status-modified: #6f42c1;
    --status-renamed: #8f4300;
}
body.theme-dark.colorblind {
    --add-bg: #08192b;
    --add-ln-bg: #0d3054;
    --add-text: #79c0ff;
    --del-bg: #2a1607;
    --del-ln-bg: #4d2708;
    --del-text: #ffa657;
    --status-added: #1f6feb;
    --status-deleted: #e08a3c;
    --status-modified: #a371f7;
    --status-renamed: #e08a3c;
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
    overflow: hidden;
    background: var(--card-bg);
    border-right: 1px solid var(--border);
    font-size: 13px;
    display: flex;
    flex-direction: column;
}
.sidebar-header {
    flex: 0 0 auto;
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
.sidebar-section-title {
    flex: 0 0 auto;
    padding: 10px 14px 6px;
    border-top: 1px solid var(--border);
    font-weight: 600;
    font-size: 11px;
    text-transform: uppercase;
    letter-spacing: 0.5px;
    color: var(--muted);
}
.sidebar-header + .sidebar-section-title { border-top: none; }
.sidebar-filter {
    flex: 0 0 auto;
    padding: 0 8px 8px;
    background: var(--card-bg);
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
    flex: 1 1 auto;
    min-height: 0;
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
/* Whitespace markers are drawn as overlays so the real space/tab characters
   stay in the DOM and survive a copy/paste of the selection. */
.ws-mark { position: relative; }
.ws-mark::before {
    position: absolute;
    left: 0;
    top: 0;
    color: var(--muted);
    opacity: 0.65;
    pointer-events: none;
}
.ws-mark.ws-sp::before  { content: "\00B7"; }
.ws-mark.ws-tab::before { content: "\2192"; }
/* Diff prefix column (+/-/space): visible, never part of a copy. */
.pfx { user-select: none; -webkit-user-select: none; }
/* Split view: a selection started in one pane cannot reach the other. */
body.sel-l table.diff-table.sbs td.side-r,
body.sel-r table.diff-table.sbs td.side-l {
    user-select: none;
    -webkit-user-select: none;
}
.commit-list {
    flex: 0 1 auto;
    min-height: 0;
    max-height: 35vh;
    overflow-y: auto;
}
.commit-list .row {
    display: flex;
    flex-wrap: wrap;
    align-items: baseline;
    row-gap: 1px;
    padding: 5px 12px;
    font-size: 12px;
    border-left: 3px solid transparent;
}
.commit-list .row.clickable { cursor: pointer; }
.commit-list .row.clickable:hover { background: var(--file-header-hover); }
.commit-list .row.active {
    background: var(--file-header-hover);
    border-left-color: var(--accent);
}
/* Pinned to the top of the commit list so "all commits" is always reachable. */
.commit-list .row.all {
    position: sticky;
    top: 0;
    z-index: 1;
    background: var(--card-bg);
    box-shadow: 0 1px 0 var(--border);
}
.commit-list .row.all.active { background: var(--file-header-hover); }
.commit-list .row.all .sha { color: var(--muted); font-style: italic; }
.diff-set { display: none; }
.diff-set.active { display: block; }
.commit-list .sha {
    flex: 0 0 auto;
    margin-right: 8px;
    font-family: Menlo, Consolas, "Courier New", monospace;
    color: var(--accent);
}
.commit-list .subject {
    flex: 1 1 0;
    min-width: 0;
    color: var(--text);
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
}
/* Forced onto its own line by the 100% basis. */
.commit-list .meta {
    flex: 1 1 100%;
    display: flex;
    align-items: baseline;
    min-width: 0;
    font-size: 10px;
    color: var(--muted);
}
.commit-list .author {
    flex: 1 1 auto;
    margin-right: 8px;
    min-width: 0;
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
}
.commit-list .date { flex: 0 0 auto; }
.commit-list .row.all .meta { display: none; }
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
.diff-body { overflow-x: auto; overflow-y: hidden; max-width: 100%; }
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
table.diff-table td.code {
    width: 100%;
    white-space: pre-wrap;
    word-break: break-word;
    overflow-wrap: break-word;
}
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
/* Hiding collapsed context via a class avoids per-row inline style writes. */
tr.ctx-hidden { display: none; }
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
<body class="$([ "$THEME" = "dark" ] && echo -n "theme-dark ")$([ "$VIEW_MODE" = "split" ] && echo -n "view-split ")$([ "$COLORBLIND" = "on" ] && echo -n "colorblind ")" data-initial-view="$(html_escape "$VIEW_MODE")" data-initial-theme="$(html_escape "$THEME")" data-initial-ws="$(html_escape "$WHITESPACE")" data-initial-collapse="$(html_escape "$COLLAPSE")" data-initial-colorblind="$(html_escape "$COLORBLIND")">
<button type="button" id="sidebar-show" title="Show files sidebar" aria-label="Show sidebar"><svg viewBox="0 0 24 24" width="14" height="14" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><polyline points="9 6 15 12 9 18"/></svg></button>
<div class="layout">
<aside class="sidebar" aria-label="Changes">
    <div class="sidebar-header">
        <span>Changes</span>
        <button type="button" id="sidebar-hide" title="Hide sidebar" aria-label="Hide sidebar">&times;</button>
    </div>
${COMMIT_HTML}
    <div class="sidebar-section-title">
        <span id="files-count">Files (${FILES_CHANGED})</span>
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
    &middot; $([ "$SOURCE_MODE" = "range" ] && echo -n Range || echo -n Scope): <code>$(html_escape "$RANGE")</code>
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
            <label class="ws-toggle" title="Colorblind-safe palette: blue additions / orange deletions instead of green / red">
                <input type="checkbox" id="colorblind-toggle"$([ "$COLORBLIND" = "on" ] && echo -n ' checked')>
                <span>Colorblind</span>
            </label>
            <button type="button" id="theme-toggle" title="Toggle dark / light theme" aria-label="Toggle theme">
                <span class="moon">&#9790;</span><span class="sun">&#9788;</span>
            </button>
        </div>
    </div>
</section>
HTML_HEAD

# ----- diff body -----
DIFF_OUTPUT=$(git diff --no-color --unified="$CONTEXT_LINES" ${DIFF_ARGS[@]+"${DIFF_ARGS[@]}"} 2>/dev/null || true)

if [[ -n "$UNTRACKED_DIFF" ]]; then
    DIFF_OUTPUT="${DIFF_OUTPUT:+$DIFF_OUTPUT$'\n'}${UNTRACKED_DIFF%$'\n'}"
fi

# Turn a raw unified diff into the file-card markup. $1 is the diff text,
# $2 a prefix making the generated element ids unique across diff sets.
render_diff_html() {
    if [[ -z "$1" ]]; then
        echo '<div class="empty">No changes in this range.</div>'
        return
    fi
    printf '%s\n' "$1" | awk -v prefix="$2" '
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
        printf "<div class=\"file-card\" id=\"%s-file-%d\">", prefix, file_counter
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
            printf "<tr class=\"ctx\"><td class=\"ln\">%d</td><td class=\"ln\">%d</td><td class=\"code\"><span class=\"pfx\"> </span>%s</td></tr>\n", left_line, right_line, esc(rest)
            left_line++; right_line++
        } else if (c == "-") {
            printf "<tr class=\"del\"><td class=\"ln\">%d</td><td class=\"ln\"></td><td class=\"code\"><span class=\"pfx\">-</span>%s</td></tr>\n", left_line, esc(rest)
            left_line++
        } else if (c == "+") {
            printf "<tr class=\"add\"><td class=\"ln\"></td><td class=\"ln\">%d</td><td class=\"code\"><span class=\"pfx\">+</span>%s</td></tr>\n", right_line, esc(rest)
            right_line++
        } else if (c == "\\") {
            printf "<tr class=\"nonewline\"><td class=\"ln\"></td><td class=\"ln\"></td><td class=\"code\">%s</td></tr>\n", esc($0)
        }
    }
    END { flush_file() }
    '
}

echo '<div class="diff-sets">'
if [[ "$PER_COMMIT" == "on" ]]; then
    printf '<div class="diff-set active" data-set="all">\n'
    render_diff_html "$DIFF_OUTPUT" "all"
    printf '</div>\n'
    for sha in "${COMMIT_SHAS[@]}"; do
        if git rev-parse --verify -q "${sha}^" >/dev/null 2>&1; then
            crange="${sha}^..${sha}"
            [[ "$REVERSED" == "on" ]] && crange="${sha}..${sha}^"
        else
            empty_tree=$(git hash-object -t tree /dev/null)
            crange="${empty_tree}..${sha}"
            [[ "$REVERSED" == "on" ]] && crange="${sha}..${empty_tree}"
        fi
        cdiff=$(git diff --no-color --unified="$CONTEXT_LINES" "$crange" 2>/dev/null || true)
        printf '<div class="diff-set" data-set="%s">\n' "$(html_escape "$sha")"
        render_diff_html "$cdiff" "c${sha}"
        printf '</div>\n'
    done
else
    printf '<div class="diff-set active" data-set="all">\n'
    render_diff_html "$DIFF_OUTPUT" "all"
    printf '</div>\n'
fi
echo '</div>'

cat <<'HTML_FOOT'
</main>
<footer>Generated by <a href="https://github.com/MickaelBlet/GitDiffToHtml">git_diff_to_html.sh</a></footer>
</div><!-- /.content -->
</div><!-- /.layout -->
<script>
(function () {
    // ----- Keep --summary-height in sync so sticky file headers sit below the toolbar.
    var summaryEl = document.querySelector('.summary');
    var summaryHeight = 0;
    if (summaryEl) {
        var syncSummaryHeight = function () {
            summaryHeight = summaryEl.offsetHeight;
            document.documentElement.style.setProperty('--summary-height', summaryHeight + 'px');
        };
        syncSummaryHeight();
        window.addEventListener('resize', syncSummaryHeight);
        if ('ResizeObserver' in window) new ResizeObserver(syncSummaryHeight).observe(summaryEl);
    }

    // ----- Delegated clicks: file-card collapse + collapse placeholders.
    //       One document listener instead of one per header/placeholder.
    document.addEventListener('click', function (e) {
        var t = e.target;
        var ph = t.closest ? t.closest('tr.collapse-placeholder') : null;
        if (ph) {
            var r = ph.nextElementSibling;
            while (r && r.classList.contains('ctx-hidden')) {
                r.classList.remove('ctx-hidden');
                r = r.nextElementSibling;
            }
            ph.remove();
            return;
        }
        var h = t.closest ? t.closest('.file-header') : null;
        // Don't collapse when a link or button inside the header is clicked.
        if (h && !t.closest('a, button')) h.parentElement.classList.toggle('collapsed');
    });

    function activeSet() {
        return document.querySelector('.diff-set.active') || document.body;
    }

    // ----- Side-by-side table construction (built lazily, see processSet).
    // Unified code cells start with <span class="pfx">+|-| </span>; the split
    // view carries the prefix in its own column classes, so drop it.
    var PFX_RE = /^<span class="pfx">.<\/span>/;
    function srcHtml(td) {
        // Whitespace markers stash the pristine markup in data-orig.
        return td.dataset.orig !== undefined ? td.dataset.orig : td.innerHTML;
    }
    function stripPfx(html) { return html.replace(PFX_RE, ''); }
    // Building the whole tbody as one HTML string is far cheaper than
    // createElement/appendChild per cell on large diffs.
    function buildSbs(unifiedTable) {
        var rows = unifiedTable.tBodies[0] ? unifiedTable.tBodies[0].rows : [];
        var out = [];
        var i = 0, n = rows.length;
        while (i < n) {
            var r = rows[i];
            var cl = r.classList;
            if (cl.contains('hunk') || cl.contains('binary') || cl.contains('nonewline')) {
                var srcTd = r.querySelector('td.code') || r.cells[r.cells.length - 1];
                out.push('<tr class="' + r.className + '"><td colspan="4" class="code">' + (srcTd ? srcTd.innerHTML : '') + '</td></tr>');
                i++;
                continue;
            }
            if (cl.contains('ctx')) {
                var code = stripPfx(srcHtml(r.cells[2]));
                out.push('<tr class="ctx"><td class="ln side-l">' + r.cells[0].textContent +
                    '</td><td class="code ctx side-l">' + code +
                    '</td><td class="ln side-r">' + r.cells[1].textContent +
                    '</td><td class="code ctx side-r">' + code + '</td></tr>');
                i++;
                continue;
            }
            // Collect consecutive del rows then consecutive add rows.
            var dels = [];
            while (i < n && rows[i].classList.contains('del')) { dels.push(rows[i]); i++; }
            var adds = [];
            while (i < n && rows[i].classList.contains('add')) { adds.push(rows[i]); i++; }
            if (!dels.length && !adds.length) { i++; continue; }
            var maxN = Math.max(dels.length, adds.length);
            for (var j = 0; j < maxN; j++) {
                var d = dels[j], a = adds[j];
                var s = '<tr class="' + ((d && a) ? 'mod' : (d ? 'del' : 'add')) + '">';
                s += d
                    ? '<td class="ln del side-l">' + d.cells[0].textContent + '</td><td class="code del side-l">' + stripPfx(srcHtml(d.cells[2])) + '</td>'
                    : '<td class="ln empty side-l"></td><td class="code empty side-l"></td>';
                s += a
                    ? '<td class="ln add side-r">' + a.cells[1].textContent + '</td><td class="code add side-r">' + stripPfx(srcHtml(a.cells[2])) + '</td>'
                    : '<td class="ln empty side-r"></td><td class="code empty side-r"></td>';
                out.push(s + '</tr>');
            }
        }
        var sbs = document.createElement('table');
        sbs.className = 'diff-table sbs';
        sbs.innerHTML = '<tbody>' + out.join('') + '</tbody>';
        return sbs;
    }
    // Split tables double the DOM, so only build them for a set that is
    // actually displayed in split view.
    function ensureSbs(root) {
        root.querySelectorAll('table.diff-table.unified').forEach(function (t) {
            if (t.dataset.sbs === '1') return;
            t.dataset.sbs = '1';
            t.parentNode.insertBefore(buildSbs(t), t.nextSibling);
        });
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
        var arrow = p.indexOf('→');
        if (arrow >= 0) p = p.substring(arrow + 1).trim();
        var lang = detectLang(p);
        if (!lang || !hljs.getLanguage(lang)) return;
        var table = card.querySelector('table.diff-table.unified');
        if (!table || !table.tBodies[0]) return;
        var rows = table.tBodies[0].rows;
        var opts = { language: lang, ignoreIllegals: true };
        for (var i = 0; i < rows.length; i++) {
            var cl = rows[i].classList;
            if (!(cl.contains('ctx') || cl.contains('add') || cl.contains('del'))) continue;
            var td = rows[i].cells[2];
            if (!td) continue;
            var text = td.textContent;
            if (text.length === 0) continue;
            try {
                td.innerHTML = '<span class="pfx">' + text.charAt(0) + '</span>' +
                    hljs.highlight(text.substring(1), opts).value;
            } catch (_) {}
        }
    }

    // ----- Intra-line (word-level) highlighting, Bitbucket-style.
    var WORD_RE = /\s+|[A-Za-z0-9_]+|[^\sA-Za-z0-9_]/g;
    var WS_RE = /^\s+$/;
    function wordDiff(a, b) {
        var at = a.match(WORD_RE) || [];
        var bt = b.match(WORD_RE) || [];
        // Trim the common head/tail before the O(n*m) LCS: most edited lines
        // differ only in the middle, which keeps the table tiny.
        var na = at.length, nb = bt.length;
        var lo = 0;
        while (lo < na && lo < nb && at[lo] === bt[lo]) lo++;
        var ha = na, hb = nb;
        while (ha > lo && hb > lo && at[ha - 1] === bt[hb - 1]) { ha--; hb--; }
        var n = ha - lo, m = hb - lo;
        var aMark = new Array(na), bMark = new Array(nb);
        var i, j;
        if (n === 0 || m === 0) {
            for (i = lo; i < ha; i++) aMark[i] = true;
            for (j = lo; j < hb; j++) bMark[j] = true;
        } else {
            if (n * m > 40000) return null;
            // One flat typed array instead of n+1 allocations.
            var w = m + 1;
            var dp = new Int32Array((n + 1) * w);
            for (i = 1; i <= n; i++) {
                var row = i * w, prow = row - w, ai = at[lo + i - 1];
                for (j = 1; j <= m; j++) {
                    dp[row + j] = ai === bt[lo + j - 1]
                        ? dp[prow + j - 1] + 1
                        : (dp[prow + j] >= dp[row + j - 1] ? dp[prow + j] : dp[row + j - 1]);
                }
            }
            var ci = n, cj = m;
            while (ci > 0 && cj > 0) {
                if (at[lo + ci - 1] === bt[lo + cj - 1]) { ci--; cj--; }
                else if (dp[(ci - 1) * w + cj] >= dp[ci * w + cj - 1]) { aMark[lo + --ci] = true; }
                else { bMark[lo + --cj] = true; }
            }
            while (ci > 0) { aMark[lo + --ci] = true; }
            while (cj > 0) { bMark[lo + --cj] = true; }
        }
        function ranges(tokens, marks) {
            var res = [], pos = 0, cur = null;
            for (var k = 0; k < tokens.length; k++) {
                var len = tokens[k].length;
                if (marks[k] && !WS_RE.test(tokens[k])) {
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
    // Walks the markup once, copying whole runs instead of char-by-char
    // concatenation, so highlight spans survive untouched.
    function wrapCharRanges(html, ranges, cls) {
        if (!ranges || !ranges.length) return html;
        var open = '<span class="' + cls + '">';
        var out = '', run = 0, pos = 0, ri = 0, inSpan = false;
        var i = 0, L = html.length;
        function flushTo(idx) {
            if (idx > run) out += html.substring(run, idx);
            run = idx;
        }
        function sync(idx) {
            while (ri < ranges.length && pos >= ranges[ri][1]) {
                if (inSpan) { flushTo(idx); out += '</span>'; inSpan = false; }
                ri++;
            }
            if (!inSpan && ri < ranges.length && pos >= ranges[ri][0] && pos < ranges[ri][1]) {
                flushTo(idx);
                out += open;
                inSpan = true;
            }
        }
        while (i < L) {
            var c = html.charCodeAt(i);
            if (c === 60 /* < */) {
                var wasIn = inSpan;
                if (inSpan) { flushTo(i); out += '</span>'; inSpan = false; }
                var e = html.indexOf('>', i);
                if (e < 0) e = L - 1;
                i = e + 1;
                if (wasIn) { flushTo(i); out += open; inSpan = true; }
                continue;
            }
            sync(i);
            if (c === 38 /* & */) {
                var s = html.indexOf(';', i);
                i = s < 0 ? i + 1 : s + 1;
            } else {
                i++;
            }
            pos++;
        }
        sync(L);
        flushTo(L);
        if (inSpan) out += '</span>';
        return out;
    }
    function shift1(r) { return [r[0] + 1, r[1] + 1]; }
    function applyIntraLineUnified(table) {
        if (!table.tBodies[0]) return;
        var rows = table.tBodies[0].rows;
        var i = 0, n = rows.length;
        while (i < n) {
            if (!rows[i].classList.contains('del')) { i++; continue; }
            var dels = [];
            while (i < n && rows[i].classList.contains('del')) { dels.push(rows[i]); i++; }
            var adds = [];
            while (i < n && rows[i].classList.contains('add')) { adds.push(rows[i]); i++; }
            var pairs = Math.min(dels.length, adds.length);
            for (var k = 0; k < pairs; k++) {
                var dTd = dels[k].cells[2];
                var aTd = adds[k].cells[2];
                if (!dTd || !aTd) continue;
                var dText = dTd.textContent;
                var aText = aTd.textContent;
                if (dText.charAt(0) === '-') dText = dText.substring(1);
                if (aText.charAt(0) === '+') aText = aText.substring(1);
                if (dText === aText) continue;
                var diff = wordDiff(dText, aText);
                if (!diff) continue;
                // innerHTML has the prefix char at position 0, so shift ranges by +1.
                if (diff.a.length) dTd.innerHTML = wrapCharRanges(dTd.innerHTML, diff.a.map(shift1), 'word-diff');
                if (diff.b.length) aTd.innerHTML = wrapCharRanges(aTd.innerHTML, diff.b.map(shift1), 'word-diff');
            }
        }
    }

    // ----- Split view: lock a selection to the pane it started in, so
    //       dragging across never mixes old and new text.
    document.addEventListener('mousedown', function (e) {
        if (e.button !== 0) return;
        var td = e.target.closest ? e.target.closest('table.diff-table.sbs td') : null;
        document.body.classList.remove('sel-l', 'sel-r');
        if (!td) return;
        if (td.classList.contains('side-l')) document.body.classList.add('sel-l');
        else if (td.classList.contains('side-r')) document.body.classList.add('sel-r');
    }, true);

    // ----- Collapse unchanged context (keep 30 lines around each change).
    var COLLAPSE_CONTEXT = 30;
    var collapseOn = false;
    function collapseTable(table, on) {
        var hadHidden = table.dataset.collapsed === '1';
        if (hadHidden) {
            table.querySelectorAll('tr.collapse-placeholder').forEach(function (tr) { tr.remove(); });
            table.querySelectorAll('tr.ctx-hidden').forEach(function (tr) { tr.classList.remove('ctx-hidden'); });
            table.dataset.collapsed = '0';
        }
        if (!on || !table.tBodies[0]) return;
        var rows = Array.prototype.slice.call(table.tBodies[0].rows);
        var n = rows.length;
        var keep = new Uint8Array(n);
        var last = -1;
        for (var i = 0; i < n; i++) {
            var cl = rows[i].classList;
            if (cl.contains('add') || cl.contains('del') || cl.contains('mod')) {
                var lo = i - COLLAPSE_CONTEXT;
                if (lo <= last) lo = last + 1;
                if (lo < 0) lo = 0;
                var hi = Math.min(n - 1, i + COLLAPSE_CONTEXT);
                for (var j = lo; j <= hi; j++) keep[j] = 1;
                if (hi > last) last = hi;
            } else if (!cl.contains('ctx')) {
                keep[i] = 1;
                if (i > last) last = i;
            }
        }
        var cols = table.classList.contains('sbs') ? 4 : 3;
        var k = 0, hidden = false;
        var frag = [];
        while (k < n) {
            if (!keep[k] && rows[k].classList.contains('ctx')) {
                var start = k;
                while (k < n && !keep[k] && rows[k].classList.contains('ctx')) {
                    rows[k].classList.add('ctx-hidden');
                    k++;
                }
                var count = k - start;
                var ph = document.createElement('tr');
                ph.className = 'collapse-placeholder';
                ph.innerHTML = '<td colspan="' + cols + '"><span class="cph-text">&hellip; ' + count + ' unchanged line' + (count === 1 ? '' : 's') + ' (click to expand)</span></td>';
                frag.push([ph, rows[start]]);
                hidden = true;
            } else {
                k++;
            }
        }
        for (var f = 0; f < frag.length; f++) frag[f][1].parentNode.insertBefore(frag[f][0], frag[f][1]);
        if (hidden) table.dataset.collapsed = '1';
    }
    function applyCollapse(on, root) {
        (root || activeSet()).querySelectorAll('table.diff-table').forEach(function (t) {
            collapseTable(t, on);
        });
    }

    // ----- Whitespace markers (persisted). Wraps spaces/tabs in spans so CSS
    //       can overlay markers without changing the underlying characters.
    var wsOn = false;
    var WS_TAG_RE = /(<[^>]*>)|([^<]+)/g;
    function transformWs(html) {
        // Only substitute inside text nodes — skip attributes/tags so
        // syntax-highlight markup stays intact. Tab is kept after the
        // arrow so it still advances to the next tab stop.
        return html.replace(WS_TAG_RE, function (_, tag, text) {
            if (tag) return tag;
            if (text.indexOf(' ') < 0 && text.indexOf('\t') < 0) return text;
            return text
                .replace(/ /g, '\x00')
                .replace(/\t/g, '\x01')
                .replace(/\x00/g, '<span class="ws-mark ws-sp"> </span>')
                .replace(/\x01/g, '<span class="ws-mark ws-tab">\t</span>');
        });
    }
    function applyWs(on, root) {
        (root || activeSet()).querySelectorAll('td.code').forEach(function (td) {
            if (on) {
                if (td.dataset.orig === undefined) td.dataset.orig = td.innerHTML;
                // Unified-view cells start with the diff prefix span, which
                // isn't part of the source line — skip it so its space doesn't
                // get marked.
                var src = td.dataset.orig;
                var pm = src.match(PFX_RE);
                td.innerHTML = pm
                    ? pm[0] + transformWs(src.substring(pm[0].length))
                    : transformWs(src);
            } else if (td.dataset.orig !== undefined) {
                td.innerHTML = td.dataset.orig;
                delete td.dataset.orig;
            }
        });
        document.body.classList.toggle('show-whitespace', on);
    }

    // ----- Per-set processing. Highlighting, word diff and split tables are
    //       the expensive passes: run them once, and only for the set the
    //       user is actually looking at.
    var currentView = document.body.classList.contains('view-split') ? 'split' : 'unified';
    function processSet(set) {
        if (!set || set === document.body) return;
        if (set.dataset.processed !== '1') {
            set.dataset.processed = '1';
            set.querySelectorAll('.file-card').forEach(highlightCard);
            set.querySelectorAll('table.diff-table.unified').forEach(applyIntraLineUnified);
        }
        if (currentView === 'split') ensureSbs(set);
        applyWs(wsOn, set);
        applyCollapse(collapseOn, set);
    }

    // ----- Sidebar file list.
    var fileList = document.getElementById('file-list');
    var filterInput = document.getElementById('file-filter');
    var cards = [];
    var lis = [];
    var liById = Object.create(null);
    var totalAdds = 0, totalDels = 0;
    var currentActiveId = null;
    var activeLi = null;

    function buildSidebar() {
        cards = Array.prototype.slice.call(activeSet().querySelectorAll('.file-card'));
        lis = [];
        liById = Object.create(null);
        totalAdds = totalDels = 0;
        var frag = document.createDocumentFragment();
        cards.forEach(function (card) {
            var statusEl = card.querySelector('.file-header .status');
            var status = statusEl ? (statusEl.classList[1] || 'modified') : 'modified';
            var pathEl = card.querySelector('.file-header .path');
            var path = pathEl ? pathEl.textContent : '';
            // One pass over the unified rows instead of two class queries.
            var table = card.querySelector('table.diff-table.unified');
            var adds = 0, dels = 0;
            if (table && table.tBodies[0]) {
                var rows = table.tBodies[0].rows;
                for (var i = 0; i < rows.length; i++) {
                    var cl = rows[i].classList;
                    if (cl.contains('add')) adds++;
                    else if (cl.contains('del')) dels++;
                }
            }
            totalAdds += adds;
            totalDels += dels;

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
            frag.appendChild(li);
            lis.push(li);
            liById[card.id] = li;
        });
        fileList.textContent = '';
        fileList.appendChild(frag);
        applyFilter();
        var header = document.getElementById('files-count');
        if (header) header.textContent = 'Files (' + cards.length + ')';
        currentActiveId = null;
        activeLi = null;
        updateActive();
    }

    // Highlight the currently-visible file in the sidebar. The cards are in
    // document order, so a binary search beats reading every rect on scroll.
    function updateActive() {
        if (cards.length === 0) return;
        var offset = summaryHeight + 1;
        var lo = 0, hi = cards.length - 1, found = 0;
        while (lo <= hi) {
            var mid = (lo + hi) >> 1;
            if (cards[mid].getBoundingClientRect().top <= offset) { found = mid; lo = mid + 1; }
            else hi = mid - 1;
        }
        var activeId = cards[found].id;
        if (activeId === currentActiveId) return;
        currentActiveId = activeId;
        if (activeLi) activeLi.classList.remove('active');
        activeLi = liById[activeId] || null;
        if (activeLi) activeLi.classList.add('active');
    }
    var ticking = false;
    var onScroll = function () {
        if (ticking) return;
        ticking = true;
        requestAnimationFrame(function () { ticking = false; updateActive(); });
    };
    window.addEventListener('scroll', onScroll, { passive: true });
    window.addEventListener('resize', onScroll);

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

    // ----- Sidebar file filter (works off the cached <li> list).
    function applyFilter() {
        var q = filterInput ? filterInput.value.toLowerCase() : '';
        for (var i = 0; i < lis.length; i++) {
            var li = lis[i];
            li.classList.toggle('hidden', !(!q || (li.title || '').toLowerCase().indexOf(q) >= 0));
        }
    }
    if (filterInput) filterInput.addEventListener('input', applyFilter);

    // ----- Toolbar toggles.
    var collapseCheckbox = document.getElementById('collapse-toggle');
    var cbCheckbox = document.getElementById('colorblind-toggle');
    var themeBtn = document.getElementById('theme-toggle');
    var wsCheckbox = document.getElementById('ws-toggle');
    var viewButtons = document.querySelectorAll('.view-toggle button');

    function stored(key, attr) {
        var v = null;
        try { v = localStorage.getItem(key); } catch (_) {}
        return v === null ? (document.body.getAttribute(attr) === 'on') : (v === 'on');
    }
    // Read the persisted state first; the DOM passes run once, at the end.
    collapseOn = stored('gd2h-collapse', 'data-initial-collapse');
    wsOn = stored('gd2h-ws', 'data-initial-ws');
    collapseCheckbox.checked = collapseOn;
    wsCheckbox.checked = wsOn;
    document.body.classList.toggle('show-whitespace', wsOn);

    collapseCheckbox.addEventListener('change', function () {
        collapseOn = collapseCheckbox.checked;
        applyCollapse(collapseOn);
        try { localStorage.setItem('gd2h-collapse', collapseOn ? 'on' : 'off'); } catch (_) {}
    });
    wsCheckbox.addEventListener('change', function () {
        wsOn = wsCheckbox.checked;
        applyWs(wsOn);
        try { localStorage.setItem('gd2h-ws', wsOn ? 'on' : 'off'); } catch (_) {}
    });

    // Colorblind-safe palette (persisted).
    function applyColorblind(on) {
        document.body.classList.toggle('colorblind', on);
        cbCheckbox.checked = on;
    }
    applyColorblind(stored('gd2h-colorblind', 'data-initial-colorblind'));
    cbCheckbox.addEventListener('change', function () {
        var on = cbCheckbox.checked;
        applyColorblind(on);
        try { localStorage.setItem('gd2h-colorblind', on ? 'on' : 'off'); } catch (_) {}
    });

    // Theme (persisted).
    try {
        var savedTheme = localStorage.getItem('gd2h-theme');
        if (savedTheme) document.body.classList.toggle('theme-dark', savedTheme === 'dark');
    } catch (_) {}
    themeBtn.addEventListener('click', function () {
        var isDark = document.body.classList.toggle('theme-dark');
        try { localStorage.setItem('gd2h-theme', isDark ? 'dark' : 'light'); } catch (_) {}
    });

    // View toggle (unified / split). Split tables are built on demand.
    function setView(view, initial) {
        currentView = view;
        document.body.classList.toggle('view-split', view === 'split');
        viewButtons.forEach(function (b) {
            b.classList.toggle('active', b.getAttribute('data-view') === view);
        });
        try { localStorage.setItem('gd2h-view', view); } catch (_) {}
        if (initial) return;
        processSet(activeSet());
        rebuildGroups();
    }
    try {
        var savedView = localStorage.getItem('gd2h-view');
        if (savedView === 'unified' || savedView === 'split') setView(savedView, true);
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
        var cl = r.classList;
        return cl.contains('add') || cl.contains('del') || cl.contains('mod');
    }
    function rebuildGroups() {
        var sel = (currentView === 'split')
            ? 'table.diff-table.sbs > tbody > tr'
            : 'table.diff-table.unified > tbody > tr';
        var rows = activeSet().querySelectorAll(sel);
        groups = [];
        for (var i = 0; i < rows.length; i++) {
            if (!isChange(rows[i])) continue;
            var prev = rows[i].previousElementSibling;
            if (!prev || !isChange(prev)) groups.push(rows[i]);
        }
        idx = -1;
        prevBtn.disabled = nextBtn.disabled = (groups.length === 0);
        updateCounter();
    }
    function updateCounter() {
        counter.textContent = (idx < 0 ? 0 : idx + 1) + ' / ' + groups.length;
    }
    var flashed = null;
    function goTo(i) {
        if (groups.length === 0) return;
        idx = ((i % groups.length) + groups.length) % groups.length;
        var target = groups[idx];
        var card = target.closest('.file-card');
        if (card) card.classList.remove('collapsed');
        target.scrollIntoView({ behavior: 'smooth', block: 'center' });
        if (flashed) flashed.classList.remove('flash');
        flashed = target;
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

    // ----- Commit navigation: each commit row shows only its own diff.
    var commitRows = document.querySelectorAll('.commit-list .row.clickable');
    var statFiles = document.querySelector('.summary .stats span:nth-child(1)');
    var statAdd = document.querySelector('.summary .stats .add');
    var statDel = document.querySelector('.summary .stats .del');
    function updateStats() {
        // Totals come from the sidebar pass — no extra DOM walk.
        var n = cards.length, a = totalAdds, d = totalDels;
        if (statFiles) statFiles.innerHTML = '<b>' + n + '</b> file' + (n === 1 ? '' : 's') + ' changed';
        if (statAdd) statAdd.innerHTML = '<b>+' + a + '</b> insertion' + (a === 1 ? '' : 's');
        if (statDel) statDel.innerHTML = '<b>&minus;' + d + '</b> deletion' + (d === 1 ? '' : 's');
    }
    function setActiveSet(name) {
        var target = document.querySelector('.diff-set[data-set="' + name + '"]');
        if (!target) return;
        document.querySelectorAll('.diff-set').forEach(function (s) {
            s.classList.toggle('active', s === target);
        });
        commitRows.forEach(function (r) {
            r.classList.toggle('active', r.getAttribute('data-set') === name);
        });
        flashed = null;
        processSet(target);
        buildSidebar();
        updateStats();
        rebuildGroups();
        window.scrollTo({ top: 0 });
    }
    commitRows.forEach(function (r) {
        r.addEventListener('click', function () { setActiveSet(r.getAttribute('data-set')); });
    });

    // ----- Initial run (only the visible diff set is touched).
    processSet(activeSet());
    buildSidebar();
    if (commitRows.length) updateStats();
    rebuildGroups();

    // ----- Auto-jump to the first change on load.
    if (groups.length > 0 && !window.location.hash) {
        idx = 0;
        var first = groups[0];
        var firstCard = first.closest('.file-card');
        if (firstCard) firstCard.classList.remove('collapsed');
        requestAnimationFrame(function () {
            first.scrollIntoView({ block: 'center' });
            flashed = first;
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
