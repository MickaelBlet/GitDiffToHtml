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
#   git-diff-to-html.sh abc1234                  # that single commit

set -euo pipefail

OUTPUT="git-diff.html"
TITLE=""
RANGE=""
CONTEXT_LINES="1000000"

usage() {
    sed -n '3,28p' "$0" | sed 's/^# \{0,1\}//'
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
    --border: #dfe1e6;
    --text: #172b4d;
    --muted: #6b778c;
    --hunk-bg: #f1f8ff;
    --hunk-color: #005580;
    --add-bg: #e6ffed;
    --add-ln-bg: #cdffd8;
    --del-bg: #ffebe9;
    --del-ln-bg: #ffdcd7;
    --ln-bg: #fafbfc;
    --status-added: #36b37e;
    --status-deleted: #de350b;
    --status-modified: #0052cc;
    --status-renamed: #ff991f;
}
* { box-sizing: border-box; }
html, body { margin: 0; padding: 0; }
body {
    font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Helvetica, Arial, sans-serif;
    background: var(--bg);
    color: var(--text);
    font-size: 14px;
    line-height: 1.5;
}
header.top {
    background: #fff;
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
    background: #f4f5f7;
    border: 1px solid var(--border);
    border-radius: 3px;
    padding: 1px 6px;
    font-size: 12px;
}
main {
    max-width: 1200px;
    margin: 24px auto;
    padding: 0 24px 40px 24px;
}
.summary {
    background: #fff;
    border: 1px solid var(--border);
    border-radius: 3px;
    padding: 14px 18px;
    margin-bottom: 20px;
}
.summary .stats {
    display: flex;
    gap: 20px;
    flex-wrap: wrap;
    font-size: 13px;
}
.summary .stats b { font-weight: 700; }
.summary .add { color: #1a7f4e; }
.summary .del { color: #c92a2a; }
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
    color: #0052cc;
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
    background: #fafbfc;
    border-bottom: 1px solid var(--border);
    display: flex;
    align-items: center;
    gap: 10px;
    cursor: pointer;
    user-select: none;
}
.file-header:hover { background: #f4f5f7; }
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
.diff-body { overflow-x: auto; }
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
tr.add td.ln    { background: var(--add-ln-bg); color: #1a7f4e; }
tr.del td       { background: var(--del-bg); }
tr.del td.ln    { background: var(--del-ln-bg); color: #c92a2a; }
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
    background: #fff;
    border: 1px solid var(--border);
    border-radius: 6px;
    box-shadow: 0 3px 10px rgba(9, 30, 66, 0.18);
    padding: 6px 10px;
    display: flex;
    align-items: center;
    gap: 8px;
    font-size: 13px;
}
.nav-buttons button {
    background: #0052cc;
    color: #fff;
    border: none;
    padding: 6px 12px;
    border-radius: 3px;
    cursor: pointer;
    font-size: 12px;
    font-weight: 600;
    font-family: inherit;
}
.nav-buttons button:hover:not(:disabled) { background: #0043a3; }
.nav-buttons button:disabled {
    background: #dfe1e6;
    color: #a5adba;
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
<body>
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
    <div class="stats">
        <span><b>${FILES_CHANGED}</b> file$([ "$FILES_CHANGED" = "1" ] || echo s) changed</span>
        <span class="add"><b>+${INSERTIONS}</b> insertion$([ "$INSERTIONS" = "1" ] || echo s)</span>
        <span class="del"><b>&minus;${DELETIONS}</b> deletion$([ "$DELETIONS" = "1" ] || echo s)</span>
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
        printf "<div class=\"file-card\">"
        printf "<div class=\"file-header\"><span class=\"status %s\">%s</span><span class=\"path\">%s</span><span class=\"toggle\">collapse</span></div>", file_status, file_status, esc(path)
        printf "<div class=\"diff-body\"><table class=\"diff-table\"><tbody>\n"
        file_opened = 1
        in_hunk = 0
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
<div class="nav-buttons" role="group" aria-label="Change navigator">
    <button type="button" id="nav-prev" title="Previous change (p / k / Shift+Tab)">&uarr; Prev</button>
    <span class="counter" id="nav-counter">0 / 0</span>
    <button type="button" id="nav-next" title="Next change (n / j / Tab)">&darr; Next</button>
</div>
<script>
(function () {
    // Collapse/expand file cards on header click.
    document.querySelectorAll('.file-header').forEach(function (h) {
        h.addEventListener('click', function () {
            h.parentElement.classList.toggle('collapsed');
        });
    });

    // Build the list of change groups: clusters of consecutive add/del rows.
    var groups = [];
    document.querySelectorAll('tr.add, tr.del').forEach(function (row) {
        var prev = row.previousElementSibling;
        if (!prev || !(prev.classList.contains('add') || prev.classList.contains('del'))) {
            groups.push(row);
        }
    });

    var idx = -1;
    var prevBtn = document.getElementById('nav-prev');
    var nextBtn = document.getElementById('nav-next');
    var counter = document.getElementById('nav-counter');

    function updateCounter() {
        counter.textContent = (groups.length === 0 ? 0 : (idx < 0 ? 0 : idx + 1)) + ' / ' + groups.length;
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

    if (groups.length === 0) {
        prevBtn.disabled = true;
        nextBtn.disabled = true;
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

    updateCounter();
})();
</script>
</body>
</html>
HTML_FOOT
} > "$OUTPUT"

echo "Wrote $OUTPUT ($FILES_CHANGED file(s) changed, +$INSERTIONS / -$DELETIONS)"
