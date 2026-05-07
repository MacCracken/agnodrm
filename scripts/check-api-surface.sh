#!/usr/bin/env bash
# check-api-surface.sh — diff the current public API surface against the 1.0 snapshot.
#
# Thin wrapper around `cyrius api-surface`. As of cyrius 5.9.13, the official
# command supports both project-only scoping (--scope=project) and an alternate
# snapshot path (--snapshot=PATH), so the entire previous in-script
# fn/derive walker is gone. History:
#
#   pre-5.9.9   the official scanner ignored #derive(accessors) emissions;
#               this script carried an awk extension that emitted the
#               synthesized accessor pairs into the snapshot.
#   5.9.9       derive blindness fixed.
#   5.9.12      --scope=project added; stdlib entries no longer included.
#   5.9.13      --snapshot=PATH honored; this script can finally be a
#               one-liner.
#
# Usage:
#   scripts/check-api-surface.sh              # diff vs. committed snapshot
#   scripts/check-api-surface.sh --update     # regenerate snapshot
#
# Tracked upstream in
# docs/development/issues/archive/2026-05-06-cyrius-api-surface-derive-blind.md
# (resolved, archived).
set -euo pipefail
exec cyrius api-surface "$@" \
    --scope=project \
    --snapshot=docs/development/api-surface-1.0.snapshot
