#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# install.sh — Install skills from this repo to Claude Code skill scopes
# ============================================================
#
# Usage:
#   ./install.sh                         # Install all skills to user scope
#   ./install.sh sre                     # Install specific skill(s) by name
#   ./install.sh --scope repo-team sre   # Install to .claude/skills for team sharing
#   ./install.sh --scope repo-user sre   # Install to .claude/skills and exclude locally
#   ./install.sh --scope repo-user --repo /path/to/repo sre
#   ./install.sh --list                  # List available skills in user scope
#   ./install.sh --uninstall sre         # Uninstall a skill from user scope
#
# Skills are discovered by finding SKILL.md files with a
# `name:` field in their YAML frontmatter. Each skill directory
# (SKILL.md + references/ etc.) is copied to the selected scope.

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
TARGET_REPO_DIR="$REPO_DIR"
SCOPE="user"
SKILLS_DIR=""

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# --- helpers -------------------------------------------------------

log_info()  { echo -e "${CYAN}[info]${NC}  $*"; }
log_ok()    { echo -e "${GREEN}[ok]${NC}    $*"; }
log_warn()  { echo -e "${YELLOW}[warn]${NC}  $*"; }
log_err()   { echo -e "${RED}[error]${NC} $*" >&2; }

normalize_scope() {
    local scope="$1"
    case "$scope" in
        user|global)
            echo "user"
            ;;
        repo|repository|project|team|repo-team|repository-team|project-team)
            echo "repo-team"
            ;;
        local|repo-user|repository-user|project-user|user-repo)
            echo "repo-user"
            ;;
        *)
            return 1
            ;;
    esac
}

scope_description() {
    case "$SCOPE" in
        user)
            echo "user/global (${HOME}/.claude/skills)"
            ;;
        repo-team)
            echo "repository/team-shared (${TARGET_REPO_DIR}/.claude/skills)"
            ;;
        repo-user)
            echo "repository/user-only (${TARGET_REPO_DIR}/.claude/skills, locally excluded via .git/info/exclude)"
            ;;
    esac
}

resolve_skills_dir() {
    case "$SCOPE" in
        user)
            echo "${HOME}/.claude/skills"
            ;;
        repo-team|repo-user)
            echo "${TARGET_REPO_DIR}/.claude/skills"
            ;;
    esac
}

resolve_target_repo() {
    local repo="$1"
    if [[ ! -d "$repo" ]]; then
        log_err "Target repository directory does not exist: $repo"
        exit 1
    fi
    (cd "$repo" && pwd)
}

add_repo_user_exclude() {
    local name="$1"
    local exclude_file="${TARGET_REPO_DIR}/.git/info/exclude"
    local pattern=".claude/skills/${name}/"

    if [[ ! -d "${TARGET_REPO_DIR}/.git" ]]; then
        log_warn "${name}: cannot add repo-user exclude because ${TARGET_REPO_DIR}/.git does not exist"
        return 0
    fi

    mkdir -p "$(dirname "$exclude_file")"
    touch "$exclude_file"
    if ! grep -Fqx "$pattern" "$exclude_file"; then
        echo "$pattern" >> "$exclude_file"
        log_info "${name}: added ${pattern} to .git/info/exclude"
    fi
}

# Extract the `name:` value from SKILL.md YAML frontmatter
extract_skill_name() {
    local skill_file="$1"
    sed -n '/^---$/,/^---$/p' "$skill_file" | grep '^name:' | head -1 | sed 's/^name:[[:space:]]*//'
}

# Discover skills — populates SKILL_NAMES[] and SKILL_DIRS[] arrays (parallel indexed)
SKILL_NAMES=()
SKILL_DIRS=()

discover_skills() {
    SKILL_NAMES=()
    SKILL_DIRS=()
    while IFS= read -r skill_file; do
        local skill_dir
        skill_dir="$(dirname "$skill_file")"
        local name
        name="$(extract_skill_name "$skill_file")"
        if [[ -n "$name" ]]; then
            SKILL_NAMES+=("$name")
            SKILL_DIRS+=("$skill_dir")
        else
            log_warn "Skipping ${skill_file} — no 'name:' in frontmatter"
        fi
    done < <(find "$REPO_DIR" -name SKILL.md -not -path '*/.claude/*' -not -path '*/node_modules/*' | sort)
}

# Lookup skill dir by name. Prints dir or empty string.
lookup_skill_dir() {
    local target="$1"
    local i
    for (( i=0; i<${#SKILL_NAMES[@]}; i++ )); do
        if [[ "${SKILL_NAMES[$i]}" == "$target" ]]; then
            echo "${SKILL_DIRS[$i]}"
            return 0
        fi
    done
    return 1
}

# Install a single skill
install_skill() {
    local name="$1"
    local src_dir="$2"
    local dest_dir="${SKILLS_DIR}/${name}"

    # Determine what to copy: SKILL.md + references/
    local items=("SKILL.md")
    if [[ -d "${src_dir}/references" ]]; then
        items+=("references")
    fi

    # Update if already installed
    if [[ -d "$dest_dir" ]]; then
        log_warn "${name}: already installed, updating..."
        rm -rf "$dest_dir"
    fi

    mkdir -p "$dest_dir"

    for item in "${items[@]}"; do
        if [[ -d "${src_dir}/${item}" ]]; then
            cp -R "${src_dir}/${item}" "${dest_dir}/${item}"
        elif [[ -f "${src_dir}/${item}" ]]; then
            cp "${src_dir}/${item}" "${dest_dir}/${item}"
        fi
    done

    if [[ "$SCOPE" == "repo-user" ]]; then
        add_repo_user_exclude "$name"
    fi

    log_ok "${name}: installed to ${dest_dir}"
}

# Uninstall a skill
uninstall_skill() {
    local name="$1"
    local dest_dir="${SKILLS_DIR}/${name}"

    if [[ -d "$dest_dir" ]]; then
        rm -rf "$dest_dir"
        log_ok "${name}: uninstalled"
    else
        log_warn "${name}: not installed"
    fi
}

# --- main ----------------------------------------------------------

main() {
    # Parse arguments
    local mode="install"
    local targets=()

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --list|-l)
                mode="list"
                shift
                ;;
            --uninstall|-u)
                mode="uninstall"
                shift
                ;;
            --scope|-s)
                if [[ $# -lt 2 ]]; then
                    log_err "--scope requires one of: user, repo-team, repo-user"
                    exit 1
                fi
                if ! SCOPE="$(normalize_scope "$2")"; then
                    log_err "Unknown scope: $2"
                    echo "  Available scopes: user (global), repo-team, repo-user"
                    exit 1
                fi
                shift 2
                ;;
            --scope=*)
                local raw_scope="${1#--scope=}"
                if ! SCOPE="$(normalize_scope "$raw_scope")"; then
                    log_err "Unknown scope: $raw_scope"
                    echo "  Available scopes: user (global), repo-team, repo-user"
                    exit 1
                fi
                shift
                ;;
            --repo|--target-repo|--target)
                if [[ $# -lt 2 ]]; then
                    log_err "$1 requires a repository path"
                    exit 1
                fi
                TARGET_REPO_DIR="$(resolve_target_repo "$2")"
                shift 2
                ;;
            --repo=*|--target-repo=*|--target=*)
                local raw_repo="${1#*=}"
                TARGET_REPO_DIR="$(resolve_target_repo "$raw_repo")"
                shift
                ;;
            --help|-h)
                mode="help"
                shift
                ;;
            *)
                targets+=("$1")
                shift
                ;;
        esac
    done

    SKILLS_DIR="$(resolve_skills_dir)"

    # Discover all skills in repo
    discover_skills

    if [[ ${#SKILL_NAMES[@]} -eq 0 ]]; then
        log_err "No skills found in ${REPO_DIR}"
        exit 1
    fi

    case "$mode" in
        help)
            echo "Usage: $0 [options] [skill_name ...]"
            echo ""
            echo "Options:"
            echo "  --scope, -s SCOPE  Install/list/uninstall scope: user, repo-team, repo-user"
            echo "  --repo PATH        Target repository for repo-team/repo-user scopes"
            echo "  --list, -l         List available skills"
            echo "  --uninstall, -u    Uninstall specified skill(s)"
            echo "  --help, -h         Show this help"
            echo ""
            echo "Scopes:"
            echo "  user       Global user scope: ~/.claude/skills"
            echo "  repo-team  Repository team-shared scope: REPO/.claude/skills"
            echo "  repo-user  Repository user-only scope: REPO/.claude/skills plus REPO/.git/info/exclude"
            echo ""
            echo "Examples:"
            echo "  $0                         Install all skills to user scope"
            echo "  $0 sre security-ciso       Install specific skills to user scope"
            echo "  $0 --scope repo-team sre   Install a team-shared project skill"
            echo "  $0 --scope repo-user sre   Install a local-only project skill"
            echo "  $0 --scope repo-user --repo /path/to/app sre cloud-troubleshooting"
            echo "  $0 -s repo-team --list     List project team-shared installs"
            echo "  $0 -s user -u sre          Uninstall a user-scope skill"
            ;;

        list)
            echo ""
            echo "Available skills in ${REPO_DIR}:"
            echo "Scope: ${SCOPE} ($(scope_description))"
            echo ""
            printf "  %-20s %-50s %s\n" "NAME" "SOURCE" "INSTALLED"
            printf "  %-20s %-50s %s\n" "----" "------" "---------"

            # Sort by name for display
            local sorted
            sorted="$(printf '%s\n' "${SKILL_NAMES[@]}" | sort)"
            while IFS= read -r name; do
                local src_dir
                src_dir="$(lookup_skill_dir "$name")"
                local rel_path="${src_dir#"$REPO_DIR/"}"
                local installed="no"
                [[ -d "${SKILLS_DIR}/${name}" ]] && installed="yes"
                printf "  %-20s %-50s %s\n" "$name" "$rel_path" "$installed"
            done <<< "$sorted"
            echo ""
            ;;

        uninstall)
            if [[ ${#targets[@]} -eq 0 ]]; then
                log_err "Specify skill name(s) to uninstall"
                exit 1
            fi
            for t in "${targets[@]}"; do
                uninstall_skill "$t"
            done
            ;;

        install)
            # If no targets specified, install all
            if [[ ${#targets[@]} -eq 0 ]]; then
                targets=("${SKILL_NAMES[@]}")
            fi

            local count_ok=0
            local count_fail=0

            # Sort targets
            local sorted_targets
            sorted_targets="$(printf '%s\n' "${targets[@]}" | sort)"
            while IFS= read -r t; do
                local src_dir
                if src_dir="$(lookup_skill_dir "$t")"; then
                    install_skill "$t" "$src_dir"
                    (( count_ok++ )) || true
                else
                    log_err "${t}: skill not found in repo"
                    echo "  Available: ${SKILL_NAMES[*]}"
                    (( count_fail++ )) || true
                fi
            done <<< "$sorted_targets"

            echo ""
            log_info "Done: ${count_ok} installed, ${count_fail} failed"

            if [[ $count_ok -gt 0 ]]; then
                echo ""
                log_info "Restart Claude Code to activate the new skill(s)."
            fi
            ;;
    esac
}

main "$@"
