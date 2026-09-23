#!/usr/bin/env bash
set -euo pipefail

# Run Cyrius benchmarks, append results to CSV history, and generate BENCHMARKS.md
#
# Usage:
#   ./scripts/bench-history.sh              # defaults to bench-history.csv
#   ./scripts/bench-history.sh results.csv  # custom output file

HISTORY_FILE="${1:-bench-history.csv}"
BENCHMARKS_MD="BENCHMARKS.md"
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
COMMIT=$(git rev-parse --short HEAD 2>/dev/null || echo "unknown")
BRANCH=$(git branch --show-current 2>/dev/null || echo "unknown")

# Find cyrius
CYRB="${CYRB:-}"
if [ -z "$CYRB" ]; then
    if command -v cyrius >/dev/null 2>&1; then CYRB=cyrius
    elif [ -x "$HOME/.cyrius/bin/cyrius" ]; then CYRB="$HOME/.cyrius/bin/cyrius"
    elif [ -x "./build/cyrius" ]; then CYRB="./build/cyrius"
    else echo "ERROR: cyrius not found"; exit 1; fi
fi

# Create header if file doesn't exist
if [ ! -f "$HISTORY_FILE" ]; then
    echo "timestamp,commit,branch,benchmark,estimate_ns" > "$HISTORY_FILE"
fi

echo "╔══════════════════════════════════════════╗"
echo "║        agnosys benchmark suite           ║"
echo "╠══════════════════════════════════════════╣"
echo "║  commit: $COMMIT"
echo "║  branch: $BRANCH"
echo "║  date:   $TIMESTAMP"
echo "╚══════════════════════════════════════════╝"
echo ""

# Build benchmark binary
mkdir -p build
if [ -f tests/bcyr/bench_all.bcyr ]; then
    BENCH_SRC=tests/bcyr/bench_all.bcyr
elif [ -f tests/bcyr/bench_compare.bcyr ]; then
    BENCH_SRC=tests/bcyr/bench_compare.bcyr
else
    echo "No benchmark file found"
    exit 1
fi

$CYRB build "$BENCH_SRC" build/bench 2>&1
echo ""

# Run benchmarks and capture output
BENCH_OUTPUT=$(./build/bench 2>&1)
echo "$BENCH_OUTPUT"
echo ""

# Parse result rows like: "  getpid: 307ns avg (min=303ns max=372ns) [1000000 iters]".
#
# bench_report prints "<int>ns" below 1us and "<major>.<fff><us|ms|s>" above it,
# where fff is zero-padded thousandths of the unit (e.g. "1.070us") — so every
# value converts to an exact integer ns. The old parser expected an integer
# before "us", so the first bench to cross 1us ("validate_cmdline_safe", at the
# 6.6.x pin) broke arithmetic expansion and killed the script mid-append, and an
# "ms" row was never recognized at all.
#
# Rows are parsed in full BEFORE anything is appended, so a row the converter
# does not understand fails the run with the CSV untouched rather than leaving
# a partial run in the tracked history.
ROWS=$(echo "$BENCH_OUTPUT" | awk -v ts="$TIMESTAMP" -v c="$COMMIT" -v br="$BRANCH" '
    function to_ns(t,   n, u, dot, ip, fr) {
        n = t; sub(/[a-z]+$/, "", n)
        u = t; sub(/^[0-9.]+/, "", u)
        if (n !~ /^[0-9]+(\.[0-9]+)?$/) return -1
        dot = index(n, ".")
        if (dot) { ip = substr(n, 1, dot - 1) + 0; fr = substr(substr(n, dot + 1) "000", 1, 3) + 0 }
        else     { ip = n + 0; fr = 0 }
        if (u == "ns") return ip
        if (u == "us") return ip * 1000 + fr
        if (u == "ms") return ip * 1000000 + fr * 1000
        if (u == "s")  return ip * 1000000000 + fr * 1000000
        return -1
    }
    / avg / && /: / {
        name = $0; sub(/^[[:space:]]+/, "", name); sub(/:.*/, "", name)
        val = $0;  sub(/^[^:]*: /, "", val);        sub(/ avg.*/, "", val)
        ns = to_ns(val)
        if (ns < 0) { print "unparseable bench row: " $0 > "/dev/stderr"; bad = 1; exit 1 }
        printf "%s,%s,%s,%s,%d\n", ts, c, br, name, ns
    }
    END { if (bad) exit 1 }
')

COUNT=$(printf '%s' "$ROWS" | grep -c . || true)
[ "$COUNT" -gt 0 ] || { echo "ERROR: no benchmark rows parsed — output format changed?"; exit 1; }
printf '%s\n' "$ROWS" >> "$HISTORY_FILE"

echo "════════════════════════════════════════════"
echo "  ${COUNT} benchmarks recorded"
echo "  CSV:      ${HISTORY_FILE}"
echo "  Markdown: ${BENCHMARKS_MD}"
echo "════════════════════════════════════════════"
