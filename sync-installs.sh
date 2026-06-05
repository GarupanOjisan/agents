#!/usr/bin/env bash
set -euo pipefail

# Update Claude Code skills across multiple repositories from this harness repo.
#
# Manifest format (tab or space separated):
#   scope  repo-path-or--  skill [skill ...]
#
# Examples:
#   user      -                         swe
#   repo-user /Users/m0tch/dev/app      sre cloud-troubleshooting mysql-ops redis-ops
#   repo-team /Users/m0tch/dev/team-app security-ciso security-pentester

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
DEFAULT_MANIFEST="${ROOT_DIR}/install-targets.tsv"
MANIFEST="${1:-$DEFAULT_MANIFEST}"

fail() {
    echo "[error] $*" >&2
    exit 1
}

usage() {
    cat <<EOF
Usage: $0 [manifest]

Manifest format:
  scope  repo-path-or--  skill [skill ...]

Scopes:
  user, global, repo-user, repo-team

Examples:
  user      -                    swe
  repo-user /path/to/repo        sre cloud-troubleshooting mysql-ops redis-ops
  repo-team /path/to/team-repo   security-ciso security-pentester
EOF
}

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    usage
    exit 0
fi

[[ -f "$MANIFEST" ]] || fail "manifest not found: $MANIFEST"

line_no=0
updated=0
failed=0

while IFS= read -r line || [[ -n "$line" ]]; do
    line_no=$((line_no + 1))

    # Trim leading/trailing whitespace.
    line="${line#"${line%%[![:space:]]*}"}"
    line="${line%"${line##*[![:space:]]}"}"

    [[ -z "$line" || "${line:0:1}" == "#" ]] && continue

    read -r scope repo skills <<< "$line"
    [[ -n "${scope:-}" && -n "${repo:-}" && -n "${skills:-}" ]] || {
        echo "[error] ${MANIFEST}:${line_no}: expected: scope repo skill [skill ...]" >&2
        failed=$((failed + 1))
        continue
    }

    echo "[info] ${MANIFEST}:${line_no}: scope=${scope} repo=${repo} skills=${skills}"

    if [[ "$scope" == "user" || "$scope" == "global" ]]; then
        if "$ROOT_DIR/install.sh" --scope "$scope" $skills; then
            updated=$((updated + 1))
        else
            failed=$((failed + 1))
        fi
        continue
    fi

    if [[ "$repo" == "-" ]]; then
        echo "[error] ${MANIFEST}:${line_no}: repo path is required for scope=${scope}" >&2
        failed=$((failed + 1))
        continue
    fi

    if "$ROOT_DIR/install.sh" --scope "$scope" --repo "$repo" $skills; then
        updated=$((updated + 1))
    else
        failed=$((failed + 1))
    fi
done < "$MANIFEST"

echo "[info] Done: ${updated} target(s) updated, ${failed} failed"
[[ "$failed" -eq 0 ]]
