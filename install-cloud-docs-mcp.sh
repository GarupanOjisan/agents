#!/usr/bin/env bash
set -euo pipefail

# Install cloud official-documentation MCP servers for Claude Code.
#
# Defaults to Claude Code local scope so unrelated repositories do not see
# cloud-specific MCP tools unless explicitly installed there.

SCOPE="local"
TARGET_REPO=""
INSTALL_GOOGLE=1
INSTALL_AWS=1
DRY_RUN=0
GOOGLE_API_KEY="${GOOGLE_DEVELOPER_KNOWLEDGE_API_KEY:-}"

usage() {
    cat <<EOF
Usage: $0 [options]

Options:
  --scope SCOPE              Claude MCP scope: local, project, user (default: local)
  --repo PATH                Run from this repository path before adding local/project MCP
  --google-api-key KEY       Google Developer Knowledge API key
  --google-api-key-env NAME  Read Google API key from environment variable NAME
  --skip-google              Do not install Google Developer Knowledge MCP
  --skip-aws                 Do not install AWS Knowledge MCP
  --dry-run                  Print commands without changing Claude Code config
  --help, -h                 Show this help

Environment:
  GOOGLE_DEVELOPER_KNOWLEDGE_API_KEY  Used when --google-api-key is omitted

Servers:
  google-dev-knowledge       https://developerknowledge.googleapis.com/mcp
  aws-knowledge-mcp-server   https://knowledge-mcp.global.api.aws
EOF
}

fail() {
    echo "[error] $*" >&2
    exit 1
}

run() {
    if [[ "$DRY_RUN" -eq 1 ]]; then
        printf '[dry-run]'
        printf ' %q' "$@"
        printf '\n'
    else
        "$@"
    fi
}

redacted_google_add() {
    printf '[dry-run] claude mcp add --scope %q --transport http google-dev-knowledge https://developerknowledge.googleapis.com/mcp --header %q\n' "$SCOPE" "X-Goog-Api-Key: REDACTED"
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --scope|-s)
            [[ $# -ge 2 ]] || fail "$1 requires one of: local, project, user"
            SCOPE="$2"
            shift 2
            ;;
        --scope=*)
            SCOPE="${1#--scope=}"
            shift
            ;;
        --repo|--target-repo|--target)
            [[ $# -ge 2 ]] || fail "$1 requires a repository path"
            TARGET_REPO="$2"
            shift 2
            ;;
        --repo=*|--target-repo=*|--target=*)
            TARGET_REPO="${1#*=}"
            shift
            ;;
        --google-api-key)
            [[ $# -ge 2 ]] || fail "$1 requires a key"
            GOOGLE_API_KEY="$2"
            shift 2
            ;;
        --google-api-key=*)
            GOOGLE_API_KEY="${1#--google-api-key=}"
            shift
            ;;
        --google-api-key-env)
            [[ $# -ge 2 ]] || fail "$1 requires an environment variable name"
            key_var="$2"
            GOOGLE_API_KEY="${!key_var:-}"
            shift 2
            ;;
        --google-api-key-env=*)
            key_var="${1#--google-api-key-env=}"
            GOOGLE_API_KEY="${!key_var:-}"
            shift
            ;;
        --skip-google)
            INSTALL_GOOGLE=0
            shift
            ;;
        --skip-aws)
            INSTALL_AWS=0
            shift
            ;;
        --dry-run)
            DRY_RUN=1
            shift
            ;;
        --help|-h)
            usage
            exit 0
            ;;
        *)
            fail "unknown option: $1"
            ;;
    esac
done

case "$SCOPE" in
    local|project|user)
        ;;
    *)
        fail "--scope must be one of: local, project, user"
        ;;
esac

if [[ "$DRY_RUN" -eq 0 ]]; then
    command -v claude >/dev/null 2>&1 || fail "claude CLI not found"
fi

if [[ -n "$TARGET_REPO" ]]; then
    [[ -d "$TARGET_REPO" ]] || fail "target repository does not exist: $TARGET_REPO"
    cd "$TARGET_REPO"
fi

if [[ "$INSTALL_GOOGLE" -eq 1 && -z "$GOOGLE_API_KEY" ]]; then
    fail "Google Developer Knowledge MCP requires an API key. Set GOOGLE_DEVELOPER_KNOWLEDGE_API_KEY, pass --google-api-key, or use --skip-google."
fi

if [[ "$INSTALL_GOOGLE" -eq 1 ]]; then
    run claude mcp remove --scope "$SCOPE" google-dev-knowledge >/dev/null 2>&1 || true
    if [[ "$DRY_RUN" -eq 1 ]]; then
        redacted_google_add
    else
        claude mcp add --scope "$SCOPE" --transport http google-dev-knowledge https://developerknowledge.googleapis.com/mcp --header "X-Goog-Api-Key: ${GOOGLE_API_KEY}"
    fi
fi

if [[ "$INSTALL_AWS" -eq 1 ]]; then
    run claude mcp remove --scope "$SCOPE" aws-knowledge-mcp-server >/dev/null 2>&1 || true
    run claude mcp add --scope "$SCOPE" --transport http aws-knowledge-mcp-server https://knowledge-mcp.global.api.aws
fi

if [[ "$DRY_RUN" -eq 0 ]]; then
    echo "[info] Installed requested MCP server(s) at Claude Code scope: ${SCOPE}"
    echo "[info] Restart Claude Code or run 'claude mcp list' to verify."
fi
