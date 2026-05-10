#!/usr/bin/env bash
set -euo pipefail

# Bump VERSION file. Agents and CI: STOP HERE — git operations
# (commit / tag / push) are owned by the maintainer, not by any
# automated process. See CLAUDE.md "Rules (Hard Constraints)".
NEW_VERSION="${1:?Usage: $0 <new-version>}"

echo "$NEW_VERSION" > VERSION

echo "VERSION file updated to $NEW_VERSION."
echo ""
echo "Maintainer-only follow-up (NOT for agents):"
echo "  - review the diff"
echo "  - commit / tag / push at maintainer discretion"
