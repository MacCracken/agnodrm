#!/usr/bin/env bash
set -euo pipefail

# Run Cyrius benchmarks, append results to CSV history, and regenerate BENCHMARKS.md
# (latest run vs. the run before it) from that CSV.
#
# One row is the median of BENCH_ROUNDS passes (default 3) over BENCH_LAYOUTS code layouts
# (default 5), each pinned to BENCH_CPU (default the last CPU this process may use) where
# taskset exists.
#
# A single unpinned run is not a measurement: 1.7.3's read memeq_16 +50% with no code change.
# Pinning alone is not one either. It measures one arbitrary layout very precisely, and
# moving code moves strlen_16ch 36% with no change to it, far past the noise in any one
# layout. So each layout puts a padding function ahead of every include, a different fraction
# of a cache line each, and a row is what holds across them: the same move then reads 0%.
# --no-deps, because a plain build prepends the stdlib ahead of the source, where padding
# moves none of it. Three code-only changes still moved 3 of 23 rows over 5%, the worst by
# 14%, so a small move in one row is not a finding.
#
# Usage:
#   ./scripts/bench-history.sh              # defaults to bench-history.csv
#   ./scripts/bench-history.sh results.csv  # custom output file
#   BENCHMARKS_MD=out.md ./scripts/bench-history.sh results.csv
#   BENCH_ROUNDS=9 BENCH_LAYOUTS=8 BENCH_CPU=3 ./scripts/bench-history.sh
#
# bench-history.csv is TRACKED (the cross-version record); BENCHMARKS.md is
# gitignored and derived — never edit it by hand.

HISTORY_FILE="${1:-bench-history.csv}"
BENCHMARKS_MD="${BENCHMARKS_MD:-BENCHMARKS.md}"
BENCH_ROUNDS="${BENCH_ROUNDS:-3}"
BENCH_LAYOUTS="${BENCH_LAYOUTS:-5}"
BENCH_CPU="${BENCH_CPU:-}"
for setting in "BENCH_ROUNDS=$BENCH_ROUNDS" "BENCH_LAYOUTS=$BENCH_LAYOUTS"; do
    case "${setting#*=}" in
        '' | *[!0-9]* | 0) echo "ERROR: ${setting%%=*} must be a positive integer, not '${setting#*=}'"; exit 1 ;;
    esac
done
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
echo "║        agnodrm benchmark suite           ║"
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

# One binary per layout. Layout 0 is the source as it stands.
LAYOUT=0
while [ "$LAYOUT" -lt "$BENCH_LAYOUTS" ]; do
    LAYOUT_SRC="build/bench_layout_$LAYOUT.bcyr"
    {
        if [ "$LAYOUT" -gt 0 ]; then
            echo "fn _bench_pad(): i64 {"
            echo "    var x = 0;"
            PAD=0
            while [ "$PAD" -lt "$LAYOUT" ]; do  # 13 bytes each, so these land apart in 64
                echo "    x = x + 1;"
                PAD=$((PAD + 1))
            done
            echo "    return x;"
            echo "}"
        fi
        cat "$BENCH_SRC"
    } > "$LAYOUT_SRC"
    env -u CYRIUS_DCE $CYRB build --no-deps "$LAYOUT_SRC" "build/bench_$LAYOUT" 2>&1
    LAYOUT=$((LAYOUT + 1))
done
echo ""

# Run every layout in every round, so drift over the run lands on all of them alike. The last
# run is shown; all of them are parsed.
PIN=""
if command -v taskset >/dev/null 2>&1; then
    # "pid 1's current affinity list: 0-7,12": nproc - 1 is not in that set under a cpuset.
    [ -n "$BENCH_CPU" ] || BENCH_CPU=$(taskset -cp $$ | sed 's/.*: //; s/.*[-,]//')
    PIN="taskset -c $BENCH_CPU"
fi
BENCH_OUTPUT=""
ROUND=1
while [ "$ROUND" -le "$BENCH_ROUNDS" ]; do
    LAYOUT=0
    while [ "$LAYOUT" -lt "$BENCH_LAYOUTS" ]; do
        ROUND_OUTPUT=$($PIN "./build/bench_$LAYOUT" 2>&1) || {
            echo "$ROUND_OUTPUT"
            echo "ERROR: bench round $ROUND, layout $LAYOUT failed${PIN:+ under $PIN}"
            exit 1
        }
        BENCH_OUTPUT="$BENCH_OUTPUT
$ROUND_OUTPUT"
        LAYOUT=$((LAYOUT + 1))
    done
    ROUND=$((ROUND + 1))
done
echo "$ROUND_OUTPUT"
echo ""
echo "Recording the median of $BENCH_ROUNDS rounds over $BENCH_LAYOUTS layouts${PIN:+, $PIN}."
echo ""

# Parse result rows like: "  getpid: 307ns avg (min=303ns max=372ns) [1000000 iters]".
#
# Only those rows are recorded. Since cyrius 6.6.5 bench_report also prints a
# "[timer floor ...]" line and, for some rows, a "[per op in ps: ...]" line;
# neither contains " avg ", so the row selector below skips both, and the
# min/max inside a row are never read.
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
        if (!(name in seen)) { seen[name] = 1; order[++names] = name }
        vals[name, ++got[name]] = ns
    }
    END {
        if (bad) exit 1
        for (i = 1; i <= names; i++) {
            name = order[i]
            m = got[name]
            # Insertion sort: POSIX awk has none, and CI runs mawk.
            for (j = 2; j <= m; j++) {
                x = vals[name, j]
                k = j - 1
                while (k >= 1 && vals[name, k] > x) { vals[name, k + 1] = vals[name, k]; k-- }
                vals[name, k + 1] = x
            }
            mid = vals[name, int((m + 1) / 2)]
            if (m % 2 == 0) mid = int((mid + vals[name, m / 2 + 1]) / 2)
            printf "%s,%s,%s,%s,%d\n", ts, c, br, name, mid
        }
    }
')

COUNT=$(printf '%s' "$ROWS" | grep -c . || true)
[ "$COUNT" -gt 0 ] || { echo "ERROR: no benchmark rows parsed — output format changed?"; exit 1; }
printf '%s\n' "$ROWS" >> "$HISTORY_FILE"

# BENCHMARKS.md: the newest run in the CSV against the run before it. A run is
# one (timestamp, commit) pair — every row of one invocation shares both. Rows
# are listed in the newest run's order; a row the previous run lacks is "new".
# POSIX awk only (CI's ubuntu awk is mawk).
awk -F, -v src="$HISTORY_FILE" '
    NR == 1 { next }
    {
        run = $1 " " $2
        if (!(run in seen)) { seen[run] = 1; runs[++n] = run }
        v[run, $4] = $5
        order[run, ++cnt[run]] = $4
    }
    END {
        cur = runs[n]; prev = ""
        if (n > 1) prev = runs[n - 1]
        split(cur, c, " ")
        print "# agnodrm benchmarks"
        print ""
        print "Generated by `scripts/bench-history.sh` from `" src "` — do not edit."
        print "Average ns per op; lower is better. Each column is one median across code layouts"
        print "and pinned rounds; compare runs from the same host only."
        print ""
        if (prev == "") { ph = "previous" } else { split(prev, p, " "); ph = p[2] " (" p[1] ")" }
        printf "| Benchmark | %s | %s (%s) | Δ |\n", ph, c[2], c[1]
        print "|---|---:|---:|---:|"
        for (i = 1; i <= cnt[cur]; i++) {
            name = order[cur, i]; now = v[cur, name] + 0
            was = "—"; d = "new"
            if (prev != "" && ((prev, name) in v)) {
                was = v[prev, name] + 0
                d = "—"
                if (was > 0) d = sprintf("%+.1f%%", (now - was) * 100 / was)
                was = was " ns"
            }
            printf "| `%s` | %s | %d ns | %s |\n", name, was, now, d
        }
    }' "$HISTORY_FILE" > "$BENCHMARKS_MD"

echo "════════════════════════════════════════════"
echo "  ${COUNT} benchmarks recorded"
echo "  CSV:      ${HISTORY_FILE}"
echo "  Markdown: ${BENCHMARKS_MD}"
echo "════════════════════════════════════════════"
