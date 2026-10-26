#!/usr/bin/env bash
# Scans this repository for content that must never be published.
#
#   LEAK_DENYLIST=path/to/denylist.txt scripts/leak_scan.sh
#   scripts/leak_scan.sh --no-denylist      # CI: every check except the denylist
#
# What is scanned:
#   - The working tree: tracked files plus untracked files that are not
#     gitignored, skipping any .build/ directory.
#   - The full history: every blob reachable from any ref (with the path it
#     was first seen at), every commit message with its author and committer
#     names and emails, annotated tag messages, and ref names.
#   Objects reachable only from the reflog are not scanned.
#
# Checks:
#   denylist     every entry of the file named by LEAK_DENYLIST, as a fixed,
#                case-insensitive string. Blank lines and lines starting with
#                # are skipped; surrounding whitespace is trimmed. Matching runs
#                in the C locale, so case folding covers ASCII letters only.
#   long-number  a run of 17 to 20 digits (account or platform ids). A run
#                directly after a "." is the fractional part of a decimal, such
#                as the 16 and 17 digit ratios in the test fixture, and is not
#                flagged; neither is a run that is part of a longer digit run.
#   credential   private key headers, AWS access key ids, GitHub tokens, Slack
#                tokens, and assignments of a long value to a name containing
#                api_key, secret, token or password.
#   abs-path     absolute paths under the macOS or Linux home directory roots.
#
# Output is per check: the number of places with a match and, for each, the
# file path, blob id and first commit, or commit id. Matched text and
# denylist entries are never printed. Exit status: 0 clean, 1 something found,
# 2 usage or setup error.
#
# Known false positives can be listed in scripts/leak_allowlist.txt, one
# "<check> <path-glob>" per line. The denylist check cannot be allowlisted:
# the fix for a denylist match is to remove the content.

set -u
export LC_ALL=C

use_denylist=1
for arg in "$@"; do
    case "$arg" in
        --no-denylist) use_denylist=0 ;;
        -h|--help) sed -n '2,36p' "$0"; exit 0 ;;
        *) echo "leak_scan: unknown argument (see --help)" >&2; exit 2 ;;
    esac
done

root=$(git rev-parse --show-toplevel 2>/dev/null) || {
    echo "leak_scan: not inside a git repository" >&2; exit 2; }
cd "$root" || exit 2

work=$(mktemp -d "${TMPDIR:-/tmp}/leak_scan.XXXXXX") || exit 2
chmod 700 "$work"
trap 'rm -rf "$work"' EXIT

checks="long-number credential abs-path"
if [ "$use_denylist" -eq 1 ]; then
    if [ -z "${LEAK_DENYLIST:-}" ]; then
        echo "leak_scan: LEAK_DENYLIST is not set. Point it at the private denylist file, or pass --no-denylist to skip only that check." >&2
        exit 2
    fi
    if [ ! -r "$LEAK_DENYLIST" ]; then
        echo "leak_scan: the file named by LEAK_DENYLIST is not readable" >&2
        exit 2
    fi
    # Cleaned copy of the entries, readable only by this user, deleted on exit.
    sed -e 's/\r$//' -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' "$LEAK_DENYLIST" \
        | grep -v -e '^$' -e '^#' > "$work/denylist" || true
    if [ ! -s "$work/denylist" ]; then
        echo "leak_scan: the denylist has no entries" >&2
        exit 2
    fi
    checks="denylist $checks"
fi

# Regular expressions (POSIX ERE). They are written so that this file does not
# match itself: each literal prefix is followed by a bracket expression or a
# group, which the patterns themselves do not accept.
re_long_number='(^|[^0-9.])[0-9]{17,20}([^0-9]|$)'
re_credential='-----BEGIN ([A-Z]+ )*PRIVATE KEY( BLOCK)?-----|(AKIA|ASIA)[0-9A-Z]{16}|gh[pousr]_[A-Za-z0-9]{36}|github_pat_[A-Za-z0-9_]{22,}|xox[abposr]-[A-Za-z0-9-]{10,}|(api[_-]?key|secret|token|passw(or)?d)[A-Za-z0-9_]*["'\'']?[[:space:]]*[:=][[:space:]]*["'\'']?[A-Za-z0-9_+/=.-]{16,}'
re_abs_path='/(Users|home)/[A-Za-z0-9._-]'

# Number of matching lines in file $2 for check $1.
count_matches() {
    case "$1" in
        denylist)    grep -a -c -i -F -f "$work/denylist" -- "$2" ;;
        long-number) grep -a -c -E -e "$re_long_number" -- "$2" ;;
        credential)  grep -a -c -E -i -e "$re_credential" -- "$2" ;;
        abs-path)    grep -a -c -E -e "$re_abs_path" -- "$2" ;;
    esac
}

allowlist="scripts/leak_allowlist.txt"
is_allowed() { # check path
    [ "$1" = denylist ] && return 1
    [ -f "$allowlist" ] || return 1
    while read -r a_check a_glob _; do
        case "$a_check" in ''|'#'*) continue ;; esac
        [ "$a_check" = "$1" ] || continue
        # shellcheck disable=SC2254
        case "$2" in $a_glob) return 0 ;; esac
    done < "$allowlist"
    return 1
}

# Runs every check on file $1 and records $2 (a description without content)
# for each check that matches. $3 is the path used for the allowlist.
scan_file() {
    for c in $checks; do
        n=$(count_matches "$c" "$1" 2>/dev/null) || n=0
        if [ "${n:-0}" -gt 0 ] && ! is_allowed "$c" "$3"; then
            echo "$2 ($n lines)" >> "$work/hits-$c"
        fi
    done
}

# 1. Working tree.
tree_files=0
while IFS= read -r -d '' path; do
    case "/$path" in */.build/*) continue ;; esac
    [ -f "$path" ] || continue
    tree_files=$((tree_files + 1))
    scan_file "$path" "tree: $path" "$path"
done < <(git ls-files -z --cached --others --exclude-standard)

# 2. History: blobs reachable from any ref.
blob_count=0
git rev-list --objects --all > "$work/objects"
while read -r sha path; do
    [ "$(git cat-file -t "$sha")" = blob ] || continue
    blob_count=$((blob_count + 1))
    git cat-file blob "$sha" > "$work/blob"
    first=$(git log --all --format=%h --find-object="$sha" | tail -n 1)
    scan_file "$work/blob" "history: blob ${sha:0:10} at $path (first in commit ${first:-unknown})" "$path"
done < "$work/objects"

# 3. History: commit messages, author and committer names and emails.
commit_count=0
for sha in $(git rev-list --all); do
    commit_count=$((commit_count + 1))
    git log -1 --format='author %an <%ae>%ncommitter %cn <%ce>%n%n%B' "$sha" > "$work/meta"
    scan_file "$work/meta" "history: commit ${sha:0:10} (message or identity)" "commit:$sha"
done

# 4. Ref names and annotated tag messages.
git for-each-ref --format='%(refname)' > "$work/refs"
scan_file "$work/refs" "refs: ref names" "refs"
tag_count=0
for sha in $(git for-each-ref --format='%(objectname) %(objecttype)' refs/tags | awk '$2 == "tag" { print $1 }'); do
    tag_count=$((tag_count + 1))
    git cat-file tag "$sha" > "$work/tag"
    scan_file "$work/tag" "history: tag object ${sha:0:10}" "tag:$sha"
done

echo "leak_scan: scanned $tree_files working-tree files, $blob_count history blobs, $commit_count commits, $tag_count annotated tags, ref names"
found=0
for c in denylist long-number credential abs-path; do
    case " $checks " in
        *" $c "*) ;;
        *) echo "[$c] skipped (--no-denylist)"; continue ;;
    esac
    if [ -s "$work/hits-$c" ]; then
        n=$(wc -l < "$work/hits-$c" | tr -d ' ')
        echo "[$c] $n found"
        sed 's/^/  /' "$work/hits-$c"
        found=1
    else
        echo "[$c] 0 found"
    fi
done

if [ "$found" -eq 1 ]; then
    echo "leak_scan: FAILED"
    exit 1
fi
echo "leak_scan: clean"
