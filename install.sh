#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# install.sh — Install skills from this repo to ~/.claude/skills/
# ============================================================
#
# Usage:
#   ./install.sh            # Install all skills
#   ./install.sh sre        # Install specific skill(s) by name
#   ./install.sh soc sre    # Install multiple specific skills
#   ./install.sh --list     # List available skills
#   ./install.sh --uninstall sre  # Uninstall a skill
#
# Skills are discovered by finding SKILL.md files with a
# `name:` field in their YAML frontmatter. Each skill directory
# (SKILL.md + references/ etc.) is copied to ~/.claude/skills/{name}/.

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
SKILLS_DIR="${HOME}/.claude/skills"

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
    mkdir -p "$SKILLS_DIR"

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
            echo "  --list, -l        List available skills"
            echo "  --uninstall, -u   Uninstall specified skill(s)"
            echo "  --help, -h        Show this help"
            echo ""
            echo "Examples:"
            echo "  $0                Install all skills"
            echo "  $0 sre soc        Install specific skills"
            echo "  $0 -u sre         Uninstall a skill"
            ;;

        list)
            echo ""
            echo "Available skills in ${REPO_DIR}:"
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
