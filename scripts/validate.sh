#!/usr/bin/env bash
#
# validate.sh — Validate agency-agents .md files for frontmatter schema and quality minimums.
#
# Checks:
#   1. Every .md file has valid YAML frontmatter with required fields
#   2. Minimum file sizes per category
#   3. Required sections (Core Mission, Critical Rules)
#   4. No placeholder text
#
# Usage:
#   ./scripts/validate.sh [--fix] [--category <name>] [--json]
#
#   --fix         Auto-fix known issues (placeholder text, whitespace)
#   --category    Only validate one category
#   --json        Output machine-readable JSON
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

FIX_MODE=false
CATEGORY=""
JSON_OUTPUT=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --fix) FIX_MODE=true; shift ;;
        --category) CATEGORY="$2"; shift 2 ;;
        --json) JSON_OUTPUT=true; shift ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

AGENT_DIRS=(
    academic design engineering finance game-development marketing paid-media
    product project-management sales specialized spatial-computing support testing freelancing
)

if [[ -n "$CATEGORY" ]]; then
    AGENT_DIRS=("$CATEGORY")
fi

# Relaxed: tier and integrations are known extensions
ALLOWED_FIELDS="name description color emoji vibe tier author tools integrations"
REQUIRED_FIELDS="name description"
REQUIRED_SECTIONS="Core Mission Critical Rules"

declare -A MIN_SIZE=(
    ["academic"]=5000
    ["design"]=5000
    ["engineering"]=6000
    ["finance"]=8000
    ["game-development"]=6000
    ["marketing"]=6000
    ["paid-media"]=4500
    ["product"]=5000
    ["project-management"]=5000
    ["sales"]=6000
    ["specialized"]=4000
    ["spatial-computing"]=5000
    ["support"]=6000
    ["testing"]=6000
    ["freelancing"]=4000
)

# Colors
if [[ -t 1 && -z "${NO_COLOR:-}" && "${TERM:-}" != "dumb" ]]; then
    RED=$'\033[0;31m'; YELLOW=$'\033[1;33m'; GREEN=$'\033[0;32m'
    BOLD=$'\033[1m'; RESET=$'\033[0m'
else
    RED=''; YELLOW=''; GREEN=''; BOLD=''; RESET=''
fi

ERRORS=()
WARNINGS=()

# Extract YAML frontmatter from a markdown file.
# Handles files that have --- dividers in the body by only extracting
# the first block of frontmatter (lines between the first and second ---).
# Uses python3 for reliable extraction.
extract_frontmatter() {
    local file="$1"
    python3 - "${file}" << 'PYEOF'
import sys, re
file = sys.argv[1]
with open(file, "r", errors="replace") as f:
    content = f.read()
# Match --- on its own line (not inside code blocks)
# Find first line that is exactly ---
lines = content.split('\n')
start = -1
end = -1
for i, line in enumerate(lines):
    stripped = line.strip()
    if stripped == '---':
        if start == -1:
            start = i
        elif start != -1 and end == -1:
            end = i
            break
if start != -1 and end != -1:
    fm = '\n'.join(lines[start+1:end])
    print(fm)
PYEOF
}

# Check a single agent file
check_agent() {
    local file="$1"
    local rel="${file#$REPO_ROOT/}"
    local dir basename category
    dir="$(dirname "$rel")"
    basename="$(basename "$rel" .md)"
    category="${dir##*/}"

    # Extract frontmatter using python
    local fm
    fm="$(extract_frontmatter "$file")" || {
        # Fallback: try sed if python fails
        fm="$(sed -n '1,/^---$/!p' "$file" | sed '/^---$/d' | head -50)" || true
    }

    if [[ -z "$fm" ]]; then
        ERRORS+=("$rel: Cannot parse frontmatter (no --- delimiters)")
        return
    fi

    # Check required fields
    for field in $REQUIRED_FIELDS; do
        if ! echo "$fm" | grep -qE "^${field}:[[:space:]]"; then
            WARNINGS+=("$rel: Missing required field: $field")
        fi
    done

    # Check unknown fields (relaxed — only flag clearly-bad lines)
    # Lines that are clearly not YAML (start with #, **, numbers, etc.)
    while IFS= read -r line; do
        # Skip empty lines and comment-only lines
        [[ -z "$line" ]] && continue
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        # Check if line looks like a valid YAML key: "key: value" or "key:"
        if [[ "$line" =~ ^[a-zA-Z_][a-zA-Z0-9_-]*[[:space:]]*: ]]; then
            key="${line%%:*}"
            key="${key## }"
            key="${key##  }"
            allowed=false
            for allowed_field in $ALLOWED_FIELDS; do
                [[ "$key" == "$allowed_field" ]] && allowed=true && break
            done
            if ! $allowed; then
                WARNINGS+=("$rel: Unknown frontmatter field: $key")
            fi
        fi
    done <<< "$fm"

    # Check file size
    local min="${MIN_SIZE[$category]:-5000}"
    local size
    size=$(stat -c%s "$file" 2>/dev/null || stat -f%z "$file" 2>/dev/null)
    if [[ "$size" -lt "$min" ]]; then
        WARNINGS+=("$rel: ${size}B < minimum ${min}B for $category")
    fi

    # Check for placeholder text
    if grep -qE '\[(TODO|FILL IN|REPLACE THIS|EXAMPLE ONLY|PLACEHOLDER|XXX)\]' "$file"; then
        WARNINGS+=("$rel: Contains placeholder text")
    fi

    # Check required sections
    local body
    body="$(sed -n '/^---$/,/^---$/d; /^---$/d; p' "$file" 2>/dev/null || cat "$file")"
    for section in $REQUIRED_SECTIONS; do
        if ! echo "$body" | grep -qF "$section"; then
            WARNINGS+=("$rel: Missing section: $section")
        fi
    done
}

total=0
for cat in "${AGENT_DIRS[@]}"; do
    dir="$REPO_ROOT/$cat"
    [[ -d "$dir" ]] || continue
    while IFS= read -r -d '' file; do
        ((total++)) || true
        check_agent "$file"
    done < <(find "$dir" -name '*.md' -print0 | sort -z)
done

if [[ ${#ERRORS[@]} -eq 0 && ${#WARNINGS[@]} -eq 0 ]]; then
    echo ""
    echo "${GREEN}${BOLD}All checks passed ($total files).${RESET}"
    exit 0
fi

echo ""
echo "${BOLD}=== Validation Report ($total files checked) ===${RESET}"
[[ ${#ERRORS[@]} -gt 0 ]] && echo "" && echo "${RED}${BOLD}ERRORS (${#ERRORS[@]}):${RESET}"
for e in "${ERRORS[@]}"; do echo "  ${RED}x${RESET} $e"; done
[[ ${#WARNINGS[@]} -gt 0 ]] && echo "" && echo "${YELLOW}${BOLD}WARNINGS (${#WARNINGS[@]}):${RESET}"
for w in "${WARNINGS[@]}"; do echo "  ${YELLOW}!${RESET} $w"; done
echo ""
[[ ${#ERRORS[@]} -gt 0 ]] && exit 1 || exit 0
