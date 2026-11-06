# Agnodrm — Claude Code Instructions

> **Core rule**: this file is **preferences, process, and procedures** — durable rules that change rarely. Volatile state (current version, binary sizes, test counts, in-flight work, consumer status, verification hosts) lives in [`docs/development/state.md`](docs/development/state.md), refreshed every release. Do not inline state here — inlined state rots within a minor.

---

## Project Identity

**Agnodrm** (agnos + DRM) — the AGNOS device / DRM model: udev device enumeration + DRM/KMS device-node access, on a small error + util support layer. Consumers include only the modules they need, or include `dist/agnodrm.cyr` for the full bundle. Born from **agnosys** (the former AGNOS kernel-interface library); the trust / security / syscall / logging subsystems decomposed out 2026-06-19 to sigil / kavach / aegis / cyrius / sakshi (see the agnosticos decomposition plan). The udev/drm device model survives here, plus a deferred Linux-eccentric group (bootloader / update / netns / fuse / journald) parked post-v1.

- **Type**: Shared library (flat, single-include modules + bundled distlib)
- **License**: GPL-3.0-only
- **Language**: Cyrius (toolchain pinned in `cyrius.cyml [package].cyrius`)
- **Version**: `VERSION` at the project root is the source of truth — do not inline the number here
- **Genesis repo**: [agnosticos](https://github.com/MacCracken/agnosticos)
- **Philosophy**: [AGNOS Philosophy & Intention](https://github.com/MacCracken/agnosticos/blob/main/docs/philosophy.md)
- **Standards**: [First-Party Standards](https://github.com/MacCracken/agnosticos/blob/main/docs/development/applications/first-party-standards.md) · [First-Party Documentation](https://github.com/MacCracken/agnosticos/blob/main/docs/development/applications/first-party-documentation.md)
- **Recipes**: [zugot](https://github.com/MacCracken/zugot) — takumi build recipes
- **Heritage**: Ported from Rust in 2026. Rust source deleted at 0.97.1, preserved in git history. Head-to-head numbers in [`docs/benchmarks-rust-vs-cyrius.md`](docs/benchmarks-rust-vs-cyrius.md).

## Goal

**Own the device model for AGNOS.** udev enumeration and DRM/KMS device-node access, on a small error and util layer, safe, measurable and auditable. Higher-level primitives are the consumer's job.

Scope boundaries (non-owned, by design):
- **Higher-level device abstraction** → yukti (meant to consume agnodrm[udev])
- **GPU detection / compute** → ai-hwaccel, mabda (meant to consume agnodrm[udev,drm])
- **Rendering pipeline** → soorat (meant to consume agnodrm[drm])
- **Firewall rules** → nein (meant to consume agnodrm[netns])
- **Trust, security, syscalls, logging** → sigil, kavach, aegis, cyrius, sakshi (moved out at 1.4.4)

## Current State

Volatile state lives in [`docs/development/state.md`](docs/development/state.md) — current version, module count, binary size, test/assertion counts, consumer status, in-flight slots, recent releases, verification hosts. Refreshed every release.

Per-module security considerations live in [`docs/SECURITY-NOTES.md`](docs/SECURITY-NOTES.md). Module map and data flow live in [`docs/architecture/overview.md`](docs/architecture/overview.md).

## Scaffolding

Project is a flat Cyrius library. **Do not manually create project structure** — use `cyrius` tooling. If the tools are missing something, fix the tools. Module discipline:

- `src/<module>.cyr` is included via `include "src/<module>.cyr"` from `src/main.cyr`
- `cyrius.cyml [lib] modules` lists the modules `cyrius distlib` concatenates into `dist/agnodrm.cyr`
- `cyrius.cyml [build]` does **not** carry `modules` — that re-includes through main.cyr's `include` directives and inflates the binary by ~76% (see CHANGELOG 1.0.1)

## Quick Start

```sh
cyrius build src/main.cyr build/agnodrm     # compile
CYRIUS_DCE=1 cyrius build ...               # release build with dead-code elim
cyrius run src/main.cyr                     # compile + run
cyrius check src/main.cyr                   # syntax check
cyrius test                                 # run tests/tcyr/*.tcyr
cyrius bench tests/bcyr/bench_all.bcyr      # run benchmarks
cyrius distlib                              # regenerate dist/agnodrm.cyr
cyrius capacity --check src/main.cyr        # compiler-table utilization gate
cyrius lint src/*.cyr                       # static checks
cyrius vet src/main.cyr                     # include-graph audit
cyrius fmt <file> [--check]                 # format / check
scripts/audit.sh                            # full local quality run (CI parity)
scripts/check-api-surface.sh                # diff public API vs. 1.0 snapshot
```

## Key Principles

- **Correctness is the optimum sovereignty** — if it's wrong, you don't own it; the bugs own you
- **Every change passes `scripts/audit.sh`** — CI runs the same gates and adds aarch64 under qemu; never claim a change is ready without it
- Test after EVERY change, not after the feature is "done"
- ONE change at a time — never bundle unrelated changes
- **Tests + benchmarks prove the change.** Don't claim perf wins without a bench diff
- **Own the stack.** If an AGNOS crate wraps an external lib, depend on the AGNOS crate
- **No magic.** Every operation is measurable, auditable, traceable
- **Packed errors on hot paths** — `drm_syserr_pack(kind, errno)` for zero-alloc
- **Heap errors on cold paths** — `drm_syserr_new(kind, errno, message)` when diagnostics matter
- **Caller-provided buffers** — avoid heap allocation in syscall wrappers; caller owns memory
- **Prefix all functions** — every public fn starts with its module prefix (`agnodrm_`, `udev_`, `drm_`, `journald_`, `netns_`, `bootloader_`, `update_`, `fuse_`). The exceptions are `is_syscall_err`, `result_print_err` and `wrap_syscall`, which collide with sigil's; remove them at 2.0. API surface frozen at `docs/development/api-surface-1.0.snapshot`; drift fails CI
- Programs call `main()` at top level: `var exit_code = main(); sys_exit(exit_code);`
- Source files only need project includes — stdlib auto-resolves from `cyrius.cyml [deps] stdlib`

## Rules (Hard Constraints)

- **Read the genesis repo's CLAUDE.md first** — [agnosticos/CLAUDE.md](https://github.com/MacCracken/agnosticos/blob/main/CLAUDE.md)
- **Do not commit or push** — the user handles all git operations (commit, push, tag)
- **NEVER use `gh` CLI** — use `curl` to GitHub API only
- Do not add runtime dependencies — keep agnodrm lean (zero non-stdlib deps today)
- Do not skip `scripts/audit.sh` before claiming a change is ready
- Do not skip benchmarks before claiming performance improvements
- Do not tag a version (patch, minor, or major — pin-only refreshes included) without running `./scripts/bench-history.sh`, committing the appended `bench-history.csv` row (tracked history; `BENCHMARKS.md` is gitignored/derived), and a delta/regression check vs. the prior version; record material perf changes in the CHANGELOG `Performance` section
- Do not skip fuzz verification before claiming a parser change works
- Do not commit `build/`
- Do not edit `dist/agnodrm.cyr` by hand — regenerate via `cyrius distlib`
- Do not hardcode toolchain versions in CI YAML — the `cyrius = "X.Y.Z"` pin in `cyrius.cyml [package]` is the only source of truth. A pin bump also replaces the line in `.github/toolchain.sha256` (see CI / Release), or every workflow fails at the toolchain step
- Do not rename a public function without bumping the API snapshot via `scripts/check-api-surface.sh --update` and updating CHANGELOG `Breaking`
- Do not use reserved keywords as variable names (`match`, `default`, `shared`, `in`, `secret`)
- Do not define functions with 7+ parameters — split into `module_thing_new(...)` + `module_thing_set_*(...)` pattern
- Do not use `exec_cmd()`, which runs a shell, with unsanitized input — command injection risk. `src/` does not use it at all
- **Do not issue raw syscalls** — call the stdlib's per-target helpers (`sys_*`, `file_*`, `x*` in `lib/syscalls*.cyr` / `lib/io.cyr` / `lib/fs.cyr`) and spell the per-target names (`SYS_*`, `O_*`, `STAT_*`, `SOCK_*`); never `syscall(N, …)` with a number, a raw open-flag literal, or a hard-coded struct offset. Numbers and flags differ per arch and per OS, and the toolchain only translates the rows it routes: raw literals are how 1.6.1's `O_DIRECT`-for-`O_DIRECTORY` and 1.6.2's `st_uid`-for-`st_mode` aarch64 bugs shipped. The one exception is a value the stdlib does not name (e.g. mode `0x1A4`), with a comment
- Do not trust external data (file content, network input, user args) without validation
- Do not run a host tool from a test: `efibootmgr`, `argonaut`, `sha256sum`, `bootctl`, `ip`, `nft`, `udevadm`, `journalctl` and `fusermount` go through the private seams (`dd` has none, and runs on fixture files) (`_update_root`, `_netns_ip_path`, `_netns_run_dir`, `_bootloader_bootctl`, `_bootloader_root`, `_udev_tool`, `_journald_tool`, `_journald_socket`, `_fuse_fusermount`), which are 0 outside `tests/tcyr`. Do not send to the host's journal socket from a test. Do not copy a sibling repo into scratch without excluding its build trees: stiva's `rust-old/` is 6 GB
- Do not create a temp file with a predictable name and `O_TRUNC` — a planted symlink redirects the write (audit F-1, fixed 1.7.0). Use `agnodrm_tmp_create`, which creates exclusively
- Do not reorder the A/B slot writes (state, marker, firmware) without walking the power-cut table in [`docs/architecture/001-slot-write-order.md`](docs/architecture/001-slot-write-order.md), which `tests/tcyr/test_powercut.tcyr` runs. 1.7.2's first repair got this wrong with every test green. A changed write count in that test is a new row to walk, not a number to bump. A durable write that does not go through `_update_commit_tmp` needs an `_update_cut` beside it, and that seam stays under `#ifdef AGNODRM_POWERCUT`, so no shipped build can stop mid-update
- Do not take a scratch buffer from `alloc()`: it never frees, and `arena_free` does not either. Use `_agnodrm_scratch_new` / `_agnodrm_scratch_free`, and return only heap copies
- Do not treat a green suite as proof of a repair to a state machine or parser: mutation-test it, and put it in front of an independent review. Every P(-1) repair round since 1.7.1 has had HIGH defects that passed all tests

## Process

### P(-1): Scaffold / Project Hardening (before any new features)

1. **Cleanliness** — `scripts/audit.sh` clean; all 14 gates pass
2. **Benchmark baseline** — `cyrius bench tests/bcyr/bench_all.bcyr`, record CSV via `scripts/bench-history.sh`
3. **Internal deep review** — gaps, optimizations, correctness, docs
4. **External research** — domain completeness, best practices, current CVE landscape for the kernel interfaces we bind
5. **Security audit** — input handling, syscall usage, buffer sizes, pointer validation. File findings in `docs/audit/YYYY-MM-DD-audit.md`
6. **Additional tests / benchmarks / fuzz harnesses** from findings
7. **Post-review benchmarks** — prove the wins against step 2
8. **Documentation audit** — ADRs for decisions made, source citations, guides for public API
9. **Repeat if heavy** — keep drilling until clean

### Work Loop (continuous)

1. **Work phase** — new features, roadmap items, bug fixes (see `docs/development/roadmap.md`)
2. **Build check** — `cyrius build src/main.cyr build/agnodrm`
3. **Test + benchmark additions** for new code
4. **Internal review** — performance, memory, correctness, edge cases
5. **Security check** — any new syscall usage, user input handling, buffer allocation
6. **Local audit** — `scripts/audit.sh` clean
7. **Documentation** — CHANGELOG, roadmap, `docs/development/state.md`, any ADR the change earned
8. **Version check** — `VERSION`, `cyrius.cyml`, CHANGELOG header in sync (`cyrius.cyml` reads VERSION via `${file:VERSION}`, so `./scripts/version-bump.sh <new>` is enough)
9. **Benchmark every version** — run `./scripts/bench-history.sh` on **every** version bump (patch, minor, major — including pin-only refreshes). It appends a row to **`bench-history.csv` (tracked — commit it; the cross-version perf record)** and regenerates **`BENCHMARKS.md` (gitignored — derived from the CSV by the script: the newest run against the one before it)**. Diff against the prior version's row; any regression beyond run-to-run noise is called out in the CHANGELOG `Performance` section, and an unexplained regression blocks the bump — never tag a version without the bench + delta check
10. **Regenerate `dist/agnodrm.cyr`** if any `src/*.cyr` changed
11. **Return to step 1**

### Security Hardening (before every release)

Per [first-party-standards § Security Hardening](https://github.com/MacCracken/agnosticos/blob/main/docs/development/applications/first-party-standards.md#security-hardening-new--required-before-every-release). Minimum:

1. **Input validation** — every fn accepting external data validates bounds, types, ranges
2. **Buffer safety** — every `var buf[N]` verified; N is **bytes**, max access < N. A pointer into one never outlives the call: see `var buf[N]` under Cyrius Conventions
3. **Syscall review** — every syscall validated: args checked, returns handled, error paths complete
4. **Pointer validation** — no raw pointer dereference of untrusted input without bounds
5. **No command injection** — use `exec_vec()` with explicit argv; never `exec_cmd()` with unsanitized input
6. **No path traversal** — file paths from external input validated, no `../` escape
7. **Known CVE review** — check the interfaces we bind (DRM ioctls, udev, FUSE, the journal socket, netns, nftables, systemd-boot, EFI variables) against current CVE databases
8. **Document findings** — all issues in `docs/audit/YYYY-MM-DD-audit.md`

Severity levels: **CRITICAL** (remote / privilege escalation), **HIGH** (moderate effort), **MEDIUM** (specific conditions), **LOW** (defense-in-depth).

### Closeout Pass (before every minor/major bump)

Run a closeout pass before tagging `X.Y.0` or `X.0.0`. Ship as the last patch of the current minor (e.g. `1.1.5` before `1.2.0`).

1. **Full test suite** — all `tests/tcyr/*.tcyr` pass, zero failures
2. **Benchmark baseline** — `cyrius bench`, save CSV via `scripts/bench-history.sh`; compare against prior closeout
3. **Dead code audit** — `cyrius build` reports `dead:` lines under DCE; record floor in CHANGELOG
4. **Refactor pass** — consolidate the minor's additions where parallel codepaths accreted
5. **Code review pass** — walk diffs end-to-end for missed guards, ABI leaks, off-by-ones, silently-ignored errors
6. **Cleanup sweep** — stale comments, dead `#ifdef` branches, unused includes, orphaned files
7. **Security re-scan** — quick grep for new `exec_cmd`, unchecked writes, unsanitized input, buffer size mismatches, large `var buf[N]` (≥64KB)
8. **Downstream check** — every consumer in `docs/development/state.md` still builds against the new version
9. **Doc sync** — CHANGELOG, roadmap, `docs/development/state.md`, CLAUDE.md (if durable content changed)
10. **Version verify** — `VERSION`, `cyrius.cyml`, CHANGELOG header, intended git tag all match
11. **Full build from clean** — `rm -rf build && cyrius deps && CYRIUS_DCE=1 cyrius build` passes clean
12. **API surface check** — `scripts/check-api-surface.sh` clean (no signature drift vs. snapshot)

### Task Sizing

- **Low/Medium effort**: batch freely — multiple items per work loop cycle
- **Large effort**: small bites only — break into sub-tasks, verify each before moving to the next
- **If unsure**: treat it as large

### Refactoring Policy

- Refactor when the code tells you to — duplication, unclear boundaries, measured bottlenecks
- Never refactor speculatively. Wait for the third instance before extracting an abstraction
- Every refactor must pass the same test + fuzz + benchmark gates as new code
- 3 failed attempts = defer and document — don't burn time in a rabbit hole

## Cyrius Conventions

- **Error encoding**: packed `kind << 16 | errno` (fast) or heap `{ kind, errno, message_ptr }` (diagnostic)
- **Result convention**: `Ok(value)` / `Err(error)` via `lib/tagged.cyr`
- **Error propagation** (6.6.x value form — a Result is a register pair): `var res_t, res_v = f(); if (is_err_result(res_t) == 1) { return Err(res_v); }`. Never `return res_t;` / `return res_v;` — the payload alone reaches the caller as a tag, so an `Err` reads as success (see `src/error.cyr`)
- **Syscall wrappers** return raw values; use `wrap_syscall(ret)` for Result wrapping
- **`defer` in a Result-returning fn is safe at the consumer floor** — cyrius 6.6.0–6.6.6 skipped a `defer` block when the fn returned a value-form Result, and agnodrm leaked one fd per call in nine fns until 1.6.2. It is fixed at 6.6.7, the floor since 1.7.1. Existing fds / sockets / temp files are released explicitly on each exit path; that stays, and new code may use either. `tests/tcyr/test_integration.tcyr` `test_fd_hygiene` guards both. Tracker (closed): [`docs/development/issues/archive/2026-09-22-cyrius-defer-skipped-on-result-return.md`](docs/development/issues/archive/2026-09-22-cyrius-defer-skipped-on-result-return.md)
- **Structs**: heap-allocated via `alloc()`, with accessors from `#derive(accessors)`. Kernel-ABI structs use typed fields or explicit widths
- **Strings**: null-terminated C strings at boundaries; `lib/str.cyr` fat pointers (`Str`) internally. Parser inputs from `str_split` expect `Str`, not cstring
- **`toml_get` family** in cyrius 5.x stdlib expects **cstr** keys, not `Str` — passing `str_from("key")` silently returns 0
- **Benchmarks**: `lib/bench.cyr` with `now_ns()`; CSV history via `scripts/bench-history.sh`
- **`var buf[N]` inside a function** is per-call stack storage at the consumer floor and up (measured at 6.6.10, 6.6.20, 6.7.9 and 6.7.18), until it passes the fn's frame budget: a 70,000-byte local was still on the stack at 6.7.18, and a 300,000-byte one went static with a compiler warning. Either way a pointer into one is not valid after the call, so copy out what a caller keeps. Older notes in this repo call all of them static, which was true of earlier toolchains
- **Heap large buffers** — a large `var buf[N]` risks static storage and the hazard above; use scratch
- **Enum values for constants** — don't consume `gvar_toks` slots (4,096 initialized globals limit)
- **No negative literals** — write `(0 - N)` not `-N`
- **No mixed `&&` / `||`** in one expression — nest `if` blocks
- **`return;` without value is invalid** — always `return 0;`
- **All `var` declarations are function-scoped** — no block scoping
- **Max limits per compilation unit**: 4,096 variables, 1,024 functions, 4,096 initialized globals — guarded by `cyrius capacity --check`
- **`break` in `while` loops is fine** (verified 2026-08-24 against cyrius 6.5.35). A rule forbidding `break` inside a `while` loop that declares `var`s — "use flag + `continue`" — was carried as a hard constraint from 2026-04-26 to 1.5.3. It does not reproduce: the break form and the flag+continue form produce identical results on **x86_64 and aarch64**, `defer` blocks registered before the loop still run on the break path, and vars declared after the break statement behave correctly. Do not re-add it without a failing reproducer; the evidence is in [`docs/audit/2026-08-24-audit.md`](docs/audit/2026-08-24-audit.md).
- **Initialized-globals counting rule** — only a top-level `var NAME = <non-literal>;` (call / identifier / expression initializer) consumes an initialized-globals slot; a bare integer-literal init (`var x = 42;`) takes the static-init fast path and enum members are const-folded, so neither counts. See the cyrius guide's **Global Initializers** section (`docs/guides/cyrius-guide.md` in the cyrius repo)

## CI / Release

- **Toolchain pin**: `cyrius = "X.Y.Z"` field in `cyrius.cyml [package]`. **No separate `.cyrius-toolchain` file, no `CYRIUS_VERSION` env in workflow YAML.** CI and release both `grep` the pin out of `cyrius.cyml`.
- **Tarball install**: CI fetches, with `curl -f`, `https://github.com/MacCracken/cyrius/releases/download/$VER/cyrius-$VER-x86_64-linux.tar.gz` rather than the floating `install.sh` from main, so a cyrius patch can't silently change a release-tagged build.
- **Dead code elimination**: every `cyrius build` in CI and release runs with `CYRIUS_DCE=1`. Binary size is a release metric — track it in `docs/development/state.md`.
- **Tag filter**: release workflow accepts both `vX.Y.Z` and `X.Y.Z` tag shapes; the version-verify step strips a leading `v` and asserts `VERSION == tag`, a CHANGELOG section for the tag, and a `Last refresh` in `docs/development/state.md` that names it.
- **Lockfile**: `cyrius.lock` gates dep hashes. `cyrius deps --locked` must run **before** anything else: `cyrius deps`, `check`, `build`, `distlib` and `capacity` all re-vendor `lib/` and rewrite the lock as a side effect, so a check made after them cannot fail. `scripts/audit.sh` runs it first, and CI and release run it before `cyrius deps`. It needs no `lib/`, and writes nothing.
- **Toolchain hash**: `.github/toolchain.sha256` holds `<sha256>  cyrius-X.Y.Z-x86_64-linux.tar.gz`, one line, committed. CI checks the tarball against it before unpacking, because the compiler runs in the job. On a pin bump, replace the line with the release's `cyrius-X.Y.Z-x86_64-linux.tar.gz.sha256` asset. The file holds a hash, not a version anyone reads: the pin stays the source of truth, and a mismatch between the two fails closed.
- **Workflow hardening**: `permissions: contents: read` by default and `contents: write` only on the release job, `persist-credentials: false` on every checkout, and actions pinned to commit SHAs with the tag in a comment.
- **fmt drift gate**: run the **`cyrfmt` binary** per file (`cyrfmt <file>` writes formatted source to stdout) and diff against the committed file; CI fails on any diff. **Do not use `cyrius fmt <file>` in a gate** — since cyrius 6.5.28 it **rewrites the file in place** and prints nothing, so diffing its stdout compares an empty stream against every file; that reported all of them as drifted at 1.5.2, where the empty output was misread as a "silent no-op". Never run it expecting a dry run (`--dry` is the report-only form). `cyrius fmt --check <file>` does work (exits 1 on unformatted input; verified at 6.6.6), but the `cyrfmt` stdout diff also shows *what* drifted. The gate must also **fail as a tooling error when the formatter returns empty output** — a formatter that produces nothing is broken, and must never be reported as source drift.
- **lint warn-fail**: `cyrius lint` per file; any `warn ` line fails CI.
- **cross-target build gate**: every build (x86_64, aarch64, **agnos**) runs in CI, in release, and in `scripts/audit.sh` gate 5. `--agnos` runs unconditionally — it is the stock x86_64 backend plus the `CYRIUS_TARGET_AGNOS` define, not a separate cross compiler, so there is no `cycc_*` presence check to skip it. Every compile's log — the three target builds, the test, fuzz and bench builds, in CI, release and `scripts/audit.sh` alike — goes through **`scripts/audit.sh --check-build-log <label> <log>`**, which promotes three warn-only classes to hard failures: **`warning: undefined function`** (a *reachable* undefined function is already a build error, but when DCE proves the call site unreachable cyrius only warns and exits 0 — how `_agnos_getenv` shipped at 1.5.2), **`non-exhaustive match over enum`**, and the value-form **`the tag is dropped`** (a Result-returning fn returning a single value on some path). `#deprecated` call-site warnings and `duplicate fn` warnings are exempt by design. The **aarch64** lane has refused undefined **tail** calls (`return f(...)`) and printed `#deprecated` warnings since cyrius 6.6.9; before that `cycc_aarch64` printed nothing and emitted a binary that SIGILLed ([tracker, closed](docs/development/issues/archive/2026-09-22-cyrius-aarch64-undefined-fn-silent.md)). The test files and fuzz harnesses run on aarch64 under `qemu-aarch64`, in CI and in release, so an aarch64-only branch gets run, not just built. Since cyrius reports an undefined function only inside a *reachable* fn, the agnos lane also builds `scripts/gen-api-probe.sh`'s probe, which calls every public fn — `src/main.cyr` alone reaches only the core modules and never compiled the other five modules' agnos arms. Capture build output to a file, never `| tee` — the default GitHub Actions step shell is `bash -e` with no `pipefail`, so a pipeline masks the compiler's exit status behind tee's.
- **dist staleness gate**: CI runs `cyrius distlib` and fails if `dist/agnodrm.cyr` differs from the committed copy.
- **Workflow layout**:
  - `.github/workflows/ci.yml` — toolchain → syntax → API surface → capacity → deps → fmt → lint → vet → dist gate → DCE build → ELF verify → aarch64 cross (best-effort) → aarch64 tests and fuzz under qemu → agnos cross → smoke → tests → fuzz → bench
  - `.github/workflows/release.yml` — version gate → CI gate → DCE build → aarch64 cross → agnos cross (verify only) → tests → fuzz → regenerate dist → archive (source tar, single-file `.cyr`, prebuilt x86_64 + aarch64 binaries, cyrius.lock, SHA256SUMS)
- **Concurrency**: CI uses `cancel-in-progress: true` keyed on workflow + ref.

## Docs

- [`docs/adr/`](docs/adr/) — architecture decision records. *Why X over Y?*
- [`docs/architecture/`](docs/architecture/) — non-obvious constraints and quirks. Module map, data flow, consumer wiring
- [`docs/audit/`](docs/audit/) — security audit reports, named `YYYY-MM-DD-audit.md`
- [`docs/guides/`](docs/guides/) — task-oriented how-tos
- [`docs/examples/`](docs/examples/) — runnable examples
- [`docs/development/roadmap.md`](docs/development/roadmap.md) — completed, backlog, future, v1.0+ criteria
- [`docs/development/state.md`](docs/development/state.md) — **live state snapshot, refreshed every release**
- [`docs/development/api-surface-1.0.md`](docs/development/api-surface-1.0.md) — public API snapshot (human-readable)
- [`docs/development/api-surface-1.0.snapshot`](docs/development/api-surface-1.0.snapshot) — machine-checkable (`module::fn/arity`)
- [`docs/development/capacity-baseline.md`](docs/development/capacity-baseline.md) — compiler-table utilization record
- [`docs/SECURITY-NOTES.md`](docs/SECURITY-NOTES.md) — per-module security considerations
- [`docs/benchmarks-rust-vs-cyrius.md`](docs/benchmarks-rust-vs-cyrius.md) — Rust → Cyrius port numbers (headliner; kept at `docs/` root deliberately)
- [`CHANGELOG.md`](CHANGELOG.md) — source of truth for all changes

New quirks land in `docs/architecture/` as numbered items (`NNN-kebab-case.md`). New decisions land in `docs/adr/` (use the agnosticos template). **Never renumber either series.**

## Documentation Structure

```
Root files (required):
  README.md, CHANGELOG.md, CLAUDE.md, CONTRIBUTING.md,
  SECURITY.md, CODE_OF_CONDUCT.md, LICENSE,
  VERSION, cyrius.cyml

docs/ (required):
  benchmarks-rust-vs-cyrius.md           — HEADLINER: Rust→Cyrius port numbers
  SECURITY-NOTES.md                       — per-module security considerations
  architecture/overview.md                — module map, data flow, consumers
  development/roadmap.md                  — completed, backlog, future
  development/state.md                    — live state snapshot (volatile)
  development/api-surface-1.0.md          — public API snapshot (human-readable)
  development/api-surface-1.0.snapshot    — machine-checkable (module::fn/arity)
  development/capacity-baseline.md        — compiler-table utilization record

docs/ (when earned):
  adr/        — architectural decision records
  audit/      — security audit reports (YYYY-MM-DD-audit.md)
  guides/     — usage guides, integration patterns
  examples/   — worked examples
  standards/  — external spec conformance
  sources.md  — source citations for algorithms/formulas
```

## .gitignore (Required)

```gitignore
# Build
/build/

# Resolved deps (auto-generated by cyrius deps)
# (kernel-interface lib has no git-pinned external deps today;
#  if any are added under [deps.<name>], gitignore the resolved
#  copies and keep only the lockfile and stdlib refresh)

# Release / toolchain artifacts
cyrius-*.tar.gz
*.tar.gz
SHA256SUMS

# IDE
.idea/
.vscode/
*.swp
*~

# OS
.DS_Store
Thumbs.db
```

## CHANGELOG Format

Follow [Keep a Changelog](https://keepachangelog.com/). Performance claims **must** include benchmark numbers. Breaking changes get a **Breaking** section with migration guide. Security fixes get a **Security** section with CVE references where applicable. See [first-party-documentation § CHANGELOG](https://github.com/MacCracken/agnosticos/blob/main/docs/development/applications/first-party-documentation.md#changelog) for the full conventions.
