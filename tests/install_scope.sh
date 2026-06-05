#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

fail() {
    echo "FAIL: $*" >&2
    exit 1
}

assert_dir() {
    [[ -d "$1" ]] || fail "expected directory: $1"
}

assert_no_dir() {
    [[ ! -d "$1" ]] || fail "unexpected directory: $1"
}

assert_file_contains() {
    local file="$1"
    local pattern="$2"
    [[ -f "$file" ]] || fail "expected file: $file"
    grep -Fqx "$pattern" "$file" || fail "expected '$pattern' in $file"
}

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

HOME_DIR="$TMP_DIR/home"
REPO_COPY="$TMP_DIR/repo"
mkdir -p "$HOME_DIR"
cp -R "$ROOT_DIR" "$REPO_COPY"

rm -rf "$REPO_COPY/.claude/skills" "$REPO_COPY/.git/info/exclude"
mkdir -p "$REPO_COPY/.git/info"

(
    cd "$REPO_COPY"

    HOME="$HOME_DIR" ./install.sh --scope repo-team --list >/tmp/list-clean-repo-team.out
    assert_no_dir "$REPO_COPY/.claude/skills"

    HOME="$HOME_DIR" ./install.sh --scope user sre >/tmp/install-user.out
    assert_dir "$HOME_DIR/.claude/skills/sre"
    assert_no_dir "$REPO_COPY/.claude/skills/sre"

    HOME="$HOME_DIR" ./install.sh --scope repo-team swe >/tmp/install-repo-team.out
    assert_dir "$REPO_COPY/.claude/skills/swe"
    if [[ -f "$REPO_COPY/.git/info/exclude" ]]; then
        ! grep -Fqx ".claude/skills/swe/" "$REPO_COPY/.git/info/exclude" || fail "repo-team install should not add local exclude"
    fi

    HOME="$HOME_DIR" ./install.sh --scope repo-user mysql-ops >/tmp/install-repo-user.out
    assert_dir "$REPO_COPY/.claude/skills/mysql-ops"
    assert_file_contains "$REPO_COPY/.git/info/exclude" ".claude/skills/mysql-ops/"

    HOME="$HOME_DIR" ./install.sh --scope repo-user --uninstall mysql-ops >/tmp/uninstall-repo-user.out
    assert_no_dir "$REPO_COPY/.claude/skills/mysql-ops"
    assert_file_contains "$REPO_COPY/.git/info/exclude" ".claude/skills/mysql-ops/"

    HOME="$HOME_DIR" ./install.sh --scope repo-team --list > /tmp/list-repo-team.out
    grep -F "Scope: repo-team" /tmp/list-repo-team.out >/dev/null || fail "list should show scope"
    grep -E '^  swe[[:space:]]+swe[[:space:]]+yes$' /tmp/list-repo-team.out >/dev/null || fail "list should report repo-team install"
)

echo "install scope tests passed"
