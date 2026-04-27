#!/usr/bin/env bash
#
# convert-hermes.sh — Convert agency-agents .md files to Hermes SKILL.md format.
#
# Reads all .md agent files and generates SKILL.md files at:
#   ~/.hermes/skills/<category>-<agent>/SKILL.md
#
# Each skill includes:
#   - YAML frontmatter (name, description, tier, category, tags, trigger keywords)
#   - Full agent body as the skill prompt
#
# Usage:
#   ./scripts/convert-hermes.sh [--dry-run] [--out <dir>] [--category <name>]
#
#   --dry-run    Preview output without writing files
#   --out <dir>  Output directory (default: ~/.hermes/skills/)
#   --category   Only convert one category (e.g. engineering)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
OUT_DIR="${HOME}/.hermes/skills"

DRY_RUN=false
TARGET_CATEGORY=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --dry-run) DRY_RUN=true; shift ;;
        --out) OUT_DIR="$2"; shift 2 ;;
        --category) TARGET_CATEGORY="$2"; shift 2 ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

AGENT_DIRS=(
    academic design engineering finance game-development marketing paid-media
    product project-management sales specialized spatial-computing support testing freelancing
)

[[ -n "$TARGET_CATEGORY" ]] && AGENT_DIRS=("$TARGET_CATEGORY")

# Category display metadata
declare -A CATEGORY_META=(
    ["engineering"]="Engineering Development"
    ["marketing"]="Marketing Growth"
    ["sales"]="Sales Pipeline"
    ["support"]="Support Operations"
    ["design"]="Design Creative"
    ["finance"]="Finance Accounting"
    ["product"]="Product Management"
    ["project-management"]="Project Management"
    ["specialized"]="Specialized Domain"
    ["game-development"]="Game Development"
    ["spatial-computing"]="Spatial Computing XR"
    ["academic"]="Academic Research"
    ["paid-media"]="Paid Media"
    ["testing"]="Testing QA"
    ["freelancing"]="Freelance Services"
)

# Colors
if [[ -t 1 && -z "${NO_COLOR:-}" && "${TERM:-}" != "dumb" ]]; then
    GREEN=$'\033[0;32m'; YELLOW=$'\033[1;33m'; RED=$'\033[0;31m'
    BOLD=$'\033[1m'; RESET=$'\033[0m'
else
    GREEN=''; YELLOW=''; RED=''; BOLD=''; RESET=''
fi

info()    { printf "${GREEN}[OK]${RESET}  %s\n" "$*"; }
warn()    { printf "${YELLOW}[!!]${RESET}  %s\n" "$*"; }

count=0

convert_agent() {
    local src="$1"
    local rel="${src#$REPO_ROOT/}"
    local category
    category="$(dirname "$rel")"
    local basename
    basename="$(basename "$rel" .md)"

    # Extract frontmatter fields (simple grep approach, handles quoted values)
    local name description color emoji vibe tier
    name="$(sed -n '/^---$/,/^---$/p' "$src" | sed '1d;$d' | grep '^name:' | head -1 | sed 's/^name: *//')"
    description="$(sed -n '/^---$/,/^---$/p' "$src" | sed '1d;$d' | grep '^description:' | head -1 | sed 's/^description: *//')"
    color="$(sed -n '/^---$/,/^---$/p' "$src" | sed '1d;$d' | grep '^color:' | head -1 | sed 's/^color: *//')"
    emoji="$(sed -n '/^---$/,/^---$/p' "$src" | sed '1d;$d' | grep '^emoji:' | head -1 | sed 's/^emoji: *//')"
    vibe="$(sed -n '/^---$/,/^---$/p' "$src" | sed '1d;$d' | grep '^vibe:' | head -1 | sed 's/^vibe: *//')"
    tier="$(sed -n '/^---$/,/^---$/p' "$src" | sed '1d;$d' | grep '^tier:' | head -1 | sed 's/^tier: *//')"

    # Extract body (everything after second ---)
    local body
    body="$(awk '/^---$/&&++c==2' "$src")"

    # Generate skill directory name
    local skill_dir="${category}-${basename}"
    skill_dir="$(echo "$skill_dir" | tr ' ' '-' | tr '[A-Z]' '[a-z]' | sed 's/[^a-z0-9-]/-/g' | sed 's/--*/-/g')"

    # Defaults
    [[ -z "$tier" ]] && tier="specialist"
    local cat_meta="${CATEGORY_META[$category]:-$category}"
    local skill_name="${emoji:+$emoji }${name}"

    if $DRY_RUN; then
        info "Would write: $OUT_DIR/${skill_dir}/SKILL.md"
        ((count++)) || true
        return
    fi

    local out_path="${OUT_DIR}/${skill_dir}"
    mkdir -p "$out_path"

    # Build trigger keywords from name and description
    local kw_string="${category}, ${basename}, ${name}, ${description}"
    kw_string="$(echo "$kw_string" | tr ' ,' '\n\n' | sort -u | grep -v '^$' | tr '\n' ',' | sed 's/,$//' | sed 's/,/, /g')"

    # Write SKILL.md
    cat > "$out_path/SKILL.md" << EOF
---
name: ${skill_name}
description: ${description}
tier: ${tier}
category: ${cat_meta}
tags: [${category}, ${basename}]
trigger:
  keywords: [${kw_string}]
  platforms: [web, terminal, file]
---
# ${skill_name}

${body}
EOF

    info "$skill_dir/SKILL.md"
    ((count++)) || true
}

echo ""
echo "${BOLD}=== Hermes Agent Converter ===${RESET}"
echo "Source: $REPO_ROOT"
echo "Output: $OUT_DIR"
$DRY_RUN && echo "${YELLOW}[DRY RUN — no files written]${RESET}"
echo ""

for category in "${AGENT_DIRS[@]}"; do
    dir="$REPO_ROOT/$category"
    [[ -d "$dir" ]] || continue
    echo "${BOLD}${category}/${RESET}"
    while IFS= read -r -d '' file; do
        convert_agent "$file" 2>&1 | while read -r line; do
            echo "  $line"
        done
    done < <(find "$dir" -name '*.md' -print0 | sort -z)
done

echo ""
info "Converted $count agents"
[[ $count -gt 0 ]] && echo "" && echo "Skills installed at: $OUT_DIR/"
[[ $count -gt 0 ]] && echo "Activate with: hermes skills install <name>"
