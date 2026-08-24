#!/usr/bin/env bash
# audit.sh — local one-shot quality gate.
# Mirrors what CI runs so contributors can verify before pushing.
#
# Gates (each must pass):
#   1. Syntax check    — every src/*.cyr
#   2. API surface     — snapshot diff + prose-doc diff
#   3. Capability map  — diff docs/development/capability-map.md vs. src/
#   4. Capacity        — cyrius capacity --check src/main.cyr (<85% all tables)
#   5. Build           — src/main.cyr → build/agnodrm (x86_64 + aarch64 + agnos), verify ELF
#   6. Smoke           — ./build/agnodrm prints "agnodrm ready"
#   7. Tests           — cyrius test (tests/tcyr/*.tcyr)
#   8. Fmt drift       — cyrfmt output must match every committed source file
#   9. Lint            — cyrius lint findings (warnings + untracked deferrals), all 4 globs
#  10. Vet             — cyrius vet src/main.cyr (include-graph audit)
#  11. Fuzz            — every fuzz/*.fcyr, 10s timeout, must exit 0
#  12. Benchmarks      — tests/bcyr/bench_all.bcyr runs to completion
set -euo pipefail

GREEN='\033[32m'; RED='\033[31m'; DIM='\033[2m'; NC='\033[0m'
pass()  { printf "  ${GREEN}ok${NC}     %s\n" "$1"; }
fail()  { printf "  ${RED}FAIL${NC}   %s\n" "$1"; exit 1; }
stage() { printf "\n${DIM}[%s]${NC} %s\n" "$1" "$2"; }

# check_build_log <label> <logfile> — promote warn-only build diagnostics
# to hard failures. cyrius exits 0 for both of these:
#   * "non-exhaustive"            — a match missing an enum handler (5.8.22+)
#   * "warning: undefined function" — a call to a symbol that never got
#     defined, when DCE proves the call site unreachable. That is exactly
#     how 1.5.2's `_agnos_getenv` slipped through: `[deps] stdlib` omitted
#     `args`, so `--agnos` builds warned and exited 0, and any getenv() on
#     agnos would have jumped to an unresolved symbol. A reachable
#     undefined function is already a build error; the unreachable one is
#     only a warning, so it needs this gate.
check_build_log() {
    grep -q "non-exhaustive" "$2" && {
        grep "non-exhaustive" "$2"
        fail "$1: non-exhaustive match"
    }
    grep -q "warning: undefined function" "$2" && {
        grep "warning: undefined function" "$2"
        fail "$1: undefined function"
    }
    return 0
}

stage 1/12 "syntax check"
for f in src/*.cyr; do
    cyrius check "$f" > /dev/null 2>&1 || fail "check: $f"
done
pass "$(ls src/*.cyr | wc -l) files"

stage 2/12 "API surface"
scripts/check-api-surface.sh | tail -1 | grep -q '^ok' || fail "api surface drift"
scripts/gen-api-surface-prose.sh --check > /dev/null 2>&1 || fail "api-surface prose stale (run scripts/gen-api-surface-prose.sh)"
pass "snapshot + prose match"

stage 3/12 "capability map"
scripts/gen-capability-map.sh --check > /dev/null 2>&1 || fail "capability-map drift (run scripts/gen-capability-map.sh)"
pass "map matches src/"

stage 4/12 "capacity gate"
cyrius capacity --check src/main.cyr > /dev/null 2>&1 || fail "capacity >= 85%"
pass "all tables under 85%"

stage 5/12 "build"
mkdir -p build
cyrius build src/main.cyr build/agnodrm > /tmp/audit_build.log 2>&1 || { cat /tmp/audit_build.log; fail "build"; }
check_build_log "x86_64" /tmp/audit_build.log
xxd -l 4 build/agnodrm | grep -q "7f45 4c46" || fail "ELF magic"
# Also cross-build for aarch64 if the toolchain is present locally.
# CI runs this same gate; catching it locally avoids "passes audit
# but breaks CI" surprises (per the 1.1.8 → 1.1.9 sub-8-byte
# struct-field-load incident; full diagnosis at
# docs/development/issues/2026-05-07-cyrius-aarch64-sub-8-byte-struct-load.md).
if command -v cycc_aarch64 >/dev/null 2>&1 || [ -x "$HOME/.cyrius/bin/cycc_aarch64" ]; then
    cyrius build --aarch64 src/main.cyr build/agnodrm-aarch64 > /tmp/audit_build_aarch64.log 2>&1 \
        || { cat /tmp/audit_build_aarch64.log; fail "aarch64 build"; }
    check_build_log "aarch64" /tmp/audit_build_aarch64.log
fi
# And cross-build for agnos. Unlike aarch64 this needs no extra compiler
# binary — `--agnos` is the stock x86_64 backend plus -D CYRIUS_TARGET_AGNOS
# — so it runs unconditionally. agnodrm carries #ifdef CYRIUS_TARGET_AGNOS
# gating across drm/udev/fuse/bootloader/netns/journald/update (1.4.6, 1.5.0);
# without this gate those codepaths compile in a configuration nothing checks.
cyrius build --agnos src/main.cyr build/agnodrm-agnos > /tmp/audit_build_agnos.log 2>&1 \
    || { cat /tmp/audit_build_agnos.log; fail "agnos build"; }
check_build_log "agnos" /tmp/audit_build_agnos.log
xxd -l 4 build/agnodrm-agnos | grep -q "7f45 4c46" || fail "agnos ELF magic"
pass "build/agnodrm ($(wc -c < build/agnodrm) bytes), agnos ($(wc -c < build/agnodrm-agnos) bytes)"

stage 6/12 "smoke"
./build/agnodrm 2>&1 | grep -q "agnodrm ready" || fail "smoke"
pass "agnodrm ready"

stage 7/12 "tests"
cyrius test > /tmp/audit_test.log 2>&1 || { cat /tmp/audit_test.log; fail "tests"; }
grep -q "^[0-9]* passed, 0 failed" /tmp/audit_test.log || fail "test count"
pass "$(grep -oE '^[0-9]+ passed' /tmp/audit_test.log | head -1)"

stage 8/12 "fmt drift"
# Gate the FORMATTER, not just the sources.
#
# Invoke the `cyrfmt` binary directly — NOT `cyrius fmt <file>`. As of cyrius
# 6.5.35 that subcommand is a silent no-op: zero bytes on stdout, exit 0. CI's
# gate diffed its output against each file, so it compared an empty stream to
# all 14 sources and failed every one with "needs fmt" while nothing had
# actually drifted (hit on the 6.5.27 -> 6.5.35 pin bump at 1.5.2). This gate
# did not exist locally at the time, which is why the false positive was not
# caught until it reached CI.
#
# The empty-output check is the durable part: a formatter that produces nothing
# is BROKEN, and that must surface as a tooling failure rather than being
# laundered into a source-drift report. Same file set as CI's fmt step.
command -v cyrfmt > /dev/null 2>&1 || fail "fmt: cyrfmt not on PATH (toolchain incomplete)"
fmt_tmp=$(mktemp)
fmt_n=0
for f in src/*.cyr tests/tcyr/*.tcyr tests/bcyr/*.bcyr fuzz/*.fcyr; do
    [ -f "$f" ] || continue
    # stderr deliberately not suppressed — a cyrfmt error should be visible.
    cyrfmt "$f" > "$fmt_tmp" || { rm -f "$fmt_tmp"; fail "fmt: cyrfmt errored on $f (formatter error, not drift)"; }
    if [ -s "$f" ] && [ ! -s "$fmt_tmp" ]; then
        rm -f "$fmt_tmp"
        fail "fmt: cyrfmt produced no output for non-empty $f — formatter broken, NOT source drift"
    fi
    if ! diff -q "$fmt_tmp" "$f" > /dev/null 2>&1; then
        diff -u "$f" "$fmt_tmp" | head -20 || true   # diff exits 1 on difference; pipefail would kill us before fail()
        rm -f "$fmt_tmp"
        fail "fmt: drift in $f (run: cyrfmt $f > tmp && mv tmp $f)"
    fi
    fmt_n=$((fmt_n + 1))
done
rm -f "$fmt_tmp"
pass "$fmt_n files match cyrfmt"

stage 9/12 "lint"
# Gate the LINTER's FINDINGS, not just its exit code.
#
# Two holes this replaces, both found in the 1.5.3 P(-1) sweep:
#   1. `cyrius lint` exits 0 even when it reports findings, so the old
#      `cyrius lint "$f" || fail` could never fire — it caught only cyrlint
#      failing to execute at all. The gate was inert for its whole life.
#   2. It looked at `src/*.cyr` only, while CI lints src + tests + benches +
#      fuzz, so a finding in a test or fuzz harness passed locally and failed
#      in CI. Same mirror gap the fmt gate had.
#
# cyrlint ends each file with "<n> untracked deferrals" and "<n> warnings".
# Parse those counters. If neither line is present the output shape changed —
# fail loudly rather than silently passing everything (the 1.5.2 fmt-gate
# lesson: a broken tool must never read as a clean result).
lint_files=0
lint_warn_total=0
lint_defer_total=0
for f in src/*.cyr tests/tcyr/*.tcyr tests/bcyr/*.bcyr fuzz/*.fcyr; do
    [ -f "$f" ] || continue
    out=$(cyrius lint "$f" 2>&1) || fail "lint: cyrlint errored on $f (linter error, not a finding)"
    echo "$out" | grep -qE '[0-9]+ warnings' \
        || { echo "$out"; fail "lint: unrecognized cyrlint output for $f — tooling changed, gate cannot be trusted"; }
    w=$(echo "$out" | grep -oE '[0-9]+ warnings' | tail -1 | grep -oE '^[0-9]+' || true)
    d=$(echo "$out" | grep -oE '[0-9]+ untracked deferrals' | tail -1 | grep -oE '^[0-9]+' || true)
    [ -n "$w" ] || w=0
    [ -n "$d" ] || d=0
    if [ "$w" -ne 0 ] || [ "$d" -ne 0 ]; then
        echo "$out" | grep -E '^\s*(warn|deferral) ' || true
        lint_warn_total=$((lint_warn_total + w))
        lint_defer_total=$((lint_defer_total + d))
    fi
    lint_files=$((lint_files + 1))
done
[ "$lint_warn_total" -eq 0 ] \
    || fail "lint: $lint_warn_total warning(s)"
# Untracked deferrals are gated too: cyrlint wants every TODO/FIXME/"not yet"
# cross-referenced to a CHANGELOG / roadmap / issue entry, or marked
# #skip-lint when the phrase is incidental prose. 12 had accumulated unseen
# because neither gate looked (audit.sh checked only the exit code; CI greps
# for "warn " lines, which deferral lines do not match). Cleared in 1.5.3.
[ "$lint_defer_total" -eq 0 ] \
    || fail "lint: $lint_defer_total untracked deferral(s) — cross-reference each, or mark #skip-lint"
pass "$lint_files files, 0 warnings, 0 untracked deferrals"

stage 10/12 "vet"
# cyrius 5.7.x changed vet's output; we now rely on exit code only.
cyrius vet src/main.cyr > /dev/null 2>&1 || fail "vet"
pass "include-graph clean"

stage 11/12 "fuzz"
if ls fuzz/*.fcyr > /dev/null 2>&1; then
    for f in fuzz/*.fcyr; do
        name=$(basename "$f" .fcyr)
        cyrius build "$f" "build/$name" > /dev/null 2>&1 || fail "fuzz build: $name"
        timeout 10 "build/$name" 500 > /dev/null 2>&1 || fail "fuzz crash: $name"
    done
    pass "$(ls fuzz/*.fcyr | wc -l) harnesses"
else
    pass "no harnesses (skipped)"
fi

stage 12/12 "benchmarks"
cyrius build tests/bcyr/bench_all.bcyr build/bench_all > /dev/null 2>&1 || fail "bench build"
./build/bench_all > /tmp/audit_bench.log 2>&1 || fail "bench run"
grep -q "done" /tmp/audit_bench.log || fail "bench incomplete"
pass "$(grep -oE '[0-9]+ groups, [0-9]+ benchmarks' /tmp/audit_bench.log | head -1)"

rm -f /tmp/audit_test.log /tmp/audit_vet.log /tmp/audit_bench.log
printf "\n${GREEN}audit clean${NC} — all 12 gates pass\n"
