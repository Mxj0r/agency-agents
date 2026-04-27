#!/usr/bin/env bash
#
# extract-strings.sh — Extract all localizable strings from agency-agents.
#
# Reads all .md agent files and produces locale JSON files with:
#   { "agent-name": { "name": "", "description": "", "vibe": "" }, ... }
#
# Usage:
#   ./scripts/i18n/extract-strings.sh [--locale en] [--out scripts/i18n/
#
# The output is the master template for translators.
# Copy it to agent-names-<locale>.json and fill in translations.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
OUT_DIR="${2:-${SCRIPT_DIR}}"
LOCALE="${1:-en}"

AGENT_DIRS=(
    academic design engineering finance game-development marketing paid-media
    product project-management sales specialized spatial-computing support testing freelancing
)

echo "Extracting strings to $OUT_DIR/agent-names-$LOCALE.json"

# Use Python for reliable JSON/YAML extraction
python3 - << 'PYEOF'
import json, sys, os, re, glob

base = os.environ.get("REPO_ROOT", ".")
out = {}

agent_dirs = [
    "academic", "design", "engineering", "finance", "game-development",
    "marketing", "paid-media", "product", "project-management", "sales",
    "specialized", "spatial-computing", "support", "testing", "freelancing"
]

for cat in agent_dirs:
    dir_path = os.path.join(base, cat)
    if not os.path.isdir(dir_path):
        continue
    for f in glob.glob(os.path.join(dir_path, "*.md")):
        rel = os.path.relpath(f, base)
        with open(f, "r", errors="replace") as fh:
            content = fh.read()

        # Extract frontmatter
        fm_match = re.match(r'^---\n(.*?)\n---', content, re.DOTALL)
        if not fm_match:
            continue
        fm = fm_match.group(1)

        def get(key):
            m = re.search(rf'^{key}:\s*(.*)$', fm, re.MULTILINE)
            return m.group(1).strip() if m else ""

        name = get("name")
        if not name:
            continue

        # Build agent key from filename
        key = os.path.basename(f)[:-3]  # strip .md

        # Extract vibe (may span multiple lines)
        vibe_m = re.search(r'^vibe:\s*(.*)$', fm, re.MULTILINE)
        vibe = vibe_m.group(1).strip() if vibe_m else ""

        out[key] = {
            "name": name,
            "description": get("description"),
            "vibe": vibe,
            "category": cat
        }

# Write output sorted by category then name
output = json.dumps(out, indent=2, ensure_ascii=False, sort_keys=False)
# Sort keys for cleaner diffs
sorted_out = json.dumps(dict(sorted(out.items(), key=lambda x: (x[1]["category"], x[0]))), indent=2)

with open(os.path.join(os.environ.get("OUT_DIR", "."), f"agent-names-{os.environ.get('LOCALE', 'en')}.json"), "w") as fh:
    fh.write(sorted_out)

print(f"Extracted {len(out)} agents")
PYEOF
