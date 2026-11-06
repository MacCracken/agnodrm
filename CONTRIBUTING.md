# Contributing to Agnodrm

Thank you for your interest in contributing.

## Prerequisites

- [Cyrius](https://github.com/MacCracken/cyrius) toolchain pinned in `cyrius.cyml` (currently **6.7.18**; consumers need ≥ 6.6.10; install via `curl -sSfL https://raw.githubusercontent.com/MacCracken/cyrius/main/scripts/install.sh | sh`, then `cyriusly use $(grep -oP '(?<=^cyrius = ")[^"]+' cyrius.cyml)`)
- Linux x86_64 (primary host) or aarch64 (cross-build via `cycc_aarch64`, renamed from `cc5_aarch64` in Cyrius 6.0); macOS and Windows are not supported: see the roadmap
- `./lib/` is gitignored — populated on first build by `cyrius deps` from the `[deps] stdlib` list

## Development Workflow

1. Fork and clone
2. Create a feature branch from `main`
3. `cyrius deps` to populate `./lib/` from the pinned cyrius stdlib
4. Make your changes under `src/`, `tests/`, `fuzz/`, or `docs/`
5. **Run `scripts/audit.sh`** — 14 gates, as CI runs them (syntax → API surface (snapshot + prose) → capability map → capacity → build → smoke → tests → fmt drift → lint → vet → fuzz → benchmarks → dist staleness → lockfile)
6. If you added, renamed or removed a public function, update the snapshot intentionally: `scripts/check-api-surface.sh --update` and record the rename in `CHANGELOG.md` under `Breaking`
7. If any `src/*.cyr` changed, regenerate both bundles: `cyrius distlib && cyrius distlib core`
8. If `src/*.cyr` comments / public surface changed, regenerate the prose + capability map: `scripts/gen-api-surface-prose.sh && scripts/gen-capability-map.sh`
9. Open a PR

## Commands

| Command | Description |
|---------|-------------|
| `cyrius deps` | Vendor the pinned stdlib into `./lib/` (gitignored) |
| `cyrius build src/main.cyr build/agnodrm` | Compile |
| `cyrius build --aarch64 src/main.cyr build/agnodrm-aarch64` | Cross-build for aarch64 |
| `cyrius run src/main.cyr` | Compile + run |
| `cyrius check src/<module>.cyr` | Syntax check |
| `cyrius test` | Run `tests/tcyr/*.tcyr` |
| `cyrius lint src/<module>.cyr` | Static analysis |
| `cyrius vet src/main.cyr` | Include-graph audit |
| `cyrius capacity --check src/main.cyr` | 85% table-utilization gate |
| `cyrius distlib [<profile>]` | Regenerate `dist/agnodrm.cyr` (or `dist/agnodrm-core.cyr` — only the `core` profile remains post-decomposition) |
| `scripts/audit.sh` | Full 14-gate local quality run |
| `scripts/check-api-surface.sh` | Diff public API vs. snapshot |
| `scripts/gen-api-surface-prose.sh [--check]` | Regen / check `api-surface-1.0.md` prose |
| `scripts/gen-capability-map.sh [--check]` | Regen / check `capability-map.md` |
| `scripts/bench-history.sh` | Append a bench-history row, the median of pinned rounds, and regen `BENCHMARKS.md` |

## Adding a Module

The 1.0 surface is **frozen** — adding new modules is rare and requires a major-cycle conversation. If you do:

1. Create `src/<module>.cyr`. Prefix every public function with `<module>_` (see CLAUDE.md for why — it's a freeze-gated convention)
2. Return `Ok(value)` / `Err(error)` via `lib/tagged.cyr` for any function that can fail
3. Use the error constructors from `src/error.cyr` (`drm_err_invalid_argument`, `drm_err_io`, `drm_err_not_supported`, ...) rather than building errors by hand
4. Add `include "src/<module>.cyr"` where appropriate (typically test harnesses)
5. Register the module in `cyrius.cyml`'s `[lib] modules` list in declared order (per ADR-003 — **not** `[build] modules`)
6. If it belongs in the device-model core, add it to `[lib.core]` too
7. Run `cyrius distlib && cyrius distlib core` to refresh both bundles
8. Add integration assertions in `tests/tcyr/test_integration.tcyr` (at least 5 per module)
9. Add a fuzz harness in `fuzz/<module>_<parser>.fcyr` if the module exposes a parser
10. Update `README.md`, `CLAUDE.md`, `docs/architecture/overview.md` module tables; the auto-generated `api-surface-1.0.md` + `capability-map.md` pick up the new fns on next regen

## Cyrius Conventions

- Default type is i64. Multi-width primitives are available (`i8`/`i16`/`i32`/`i64`)
- Structs: heap-allocated via `alloc()`, with `#derive(accessors)`. `src/` has 15, in 7 modules. Serializers are hand-rolled: `#derive(Serialize)` prints a cstring field as its address
- Strings: null-terminated C strings at boundaries; `lib/str.cyr` fat pointers (`Str`) internally. Parsers built on `str_split` expect `Str`, not cstring — wrap with `str_from(cstr)` when calling from outside
- Error propagation (a Result is a register pair since cyrius 6.6.0): `var res_t, res_v = f(); if (is_err_result(res_t) == 1) { return Err(res_v); }` — never `return res_v;`, which hands the caller the payload as a tag so an `Err` reads as success
- Release fds / temp files on every exit path of a fn that returns a Result. `defer` is safe for that since cyrius 6.6.7, below the consumer floor; existing code releases explicitly (see CLAUDE.md)
- No raw syscalls: use the stdlib's `sys_*` / `file_*` helpers and per-target `SYS_*` / `O_*` / `STAT_*` names, never `syscall(N, …)`, flag literals or struct offsets
- Comments: `#` to end of line
- Reserved keywords (cannot be used as var names): `match`, `default`, `shared`, `in`, `secret`
- Max 6 function parameters — 7+ trigger a create/set split (CLAUDE.md)
- `#define LINUX` at the top of a file is a legacy no-op — no stdlib file reads it at cyrius 6.6.20; the target is the compiler's predefined `CYRIUS_TARGET_*` / `CYRIUS_ARCH_*`. Existing lines are harmless; new files don't need one
- Arch-gated blocks, if one is ever needed again, use `#ifdef CYRIUS_ARCH_X86 / AARCH64` (NOT `#ifplat` — see [`docs/development/issues/archive/2026-05-09-cyrius-ifplat-codegen.md`](docs/development/issues/archive/2026-05-09-cyrius-ifplat-codegen.md)). Prefer the stdlib's per-target `SYS_*` / `O_*` names and `sys_*` helpers, which make most arch gating unnecessary

## Code Style

- One module per `src/<module>.cyr` file, `lib.cyr` equivalent is `src/<module>.cyr` itself — there's no per-module lib entry point in agnodrm
- Module-level comment block at the top describing subsystem coverage
- Function naming: `<module>_<struct>_<field>` for accessors (e.g. `bootloader_entry_title`, `udev_devinfo_syspath`), `<module>_<verb>_<noun>` for actions (`drm_list_devices`, `netns_create_agent_netns`)
- Constants via `enum` blocks (avoids global var slot limits)
- Caller-provided buffers for hot-path functions (avoid heap allocation in syscall wrappers)
- Packed errors (`drm_syserr_pack`) for fast paths, heap errors (`drm_syserr_new`) when diagnostics matter

## Deprecating a Public Function

A public function goes in steps, so a consumer sees a warning before it sees a break:

1. Add `#deprecated("what to use instead; removed in agnodrm X.0.0")` on the line above it. Every call site then warns at
   compile time, and the API snapshot still passes.
2. Say so under `Deprecated` in the CHANGELOG, and add it to the roadmap's V2.0 backlog with a migration note.
3. Leave it for at least one minor release.
4. Remove it at the next major, with a `Breaking` entry in the CHANGELOG and `scripts/check-api-surface.sh --update`.

## Commits, Tags, Releases

- The maintainer (Robert MacCracken) handles all git operations — do not push, tag, or release
- Version is bumped via `./scripts/version-bump.sh <new-version>`; `VERSION` is the single source of truth (read into `cyrius.cyml` via `${file:VERSION}`)
- SemVer. 1.0.0 froze the API. The two breaks since, at 1.4.4 and 1.6.0, were recorded, and anything breaking now waits for the V2.0 backlog
