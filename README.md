# Agnodrm

> **Agnodrm** (agnos + DRM) — the AGNOS device / DRM model

udev device enumeration + DRM/KMS device-node access, on a small error + util support layer. Consumers take one of two bundles: `dist/agnodrm-core.cyr` for the device model, or `dist/agnodrm.cyr` for all nine modules. Born from **agnosys** (the former AGNOS kernel-interface library), which decomposed 2026-06-19: its trust / security / syscall / logging subsystems moved to their proper homes (sigil / kavach / aegis / cyrius / sakshi); the udev/drm device model survives here, alongside a deferred Linux-eccentric group (bootloader / update / netns / fuse / journald) parked post-v1.

_Current version, module count, sizes, and in-flight work live in [`docs/development/state.md`](docs/development/state.md)._

## Architecture

```
Intended consumers:
  ai-hwaccel, mabda ──→ agnodrm[udev,drm]            (GPU detection, compute)
  yukti             ──→ agnodrm[udev]                (device hotplug)
  soorat            ──→ agnodrm[drm]                 (GPU rendering)
  nein              ──→ agnodrm[netns]               (network namespaces)
  argonaut          ──→ agnodrm[journald,bootloader] (init system)
  ark               ──→ agnodrm[fuse,update]         (package management)
```

None of these is wired yet: see the [Forward plan](docs/development/roadmap.md#forward-plan).

## Modules (9)

| Module | Group | Description |
|--------|-------|-------------|
| error | core | Unified error type with errno mapping, packed + heap dual encoding |
| util | core | Shared helpers: subprocess capture, exclusive temp files, read/write, fsync |
| udev | core | Device enumeration via udevadm |
| drm | core | DRM/KMS device enumeration, version and capability ioctls |
| journald | deferred | Systemd journal structured log send/query |
| netns | deferred | Network namespace create/destroy, veth, nftables |
| bootloader | deferred | systemd-boot/GRUB detection, BLS entries, cmdline validation |
| update | deferred | Atomic file operations, version comparison, A/B slot flow |
| fuse | deferred | FUSE mount parsing, mount/unmount |

The trust, security, syscall and logging modules of the former agnosys moved to sigil, kavach, aegis, cyrius and sakshi at
1.4.4. The deferred group is parked post-v1. What each module does on each target is in
[`docs/architecture/002-platform-matrix.md`](docs/architecture/002-platform-matrix.md).

## Limits

- **Linux is the implementation.** On agnos the device calls answer "none" or `not_supported`: see the platform matrix.
- **DRM is enumeration and two ioctls,** version and capability. There is no mode-setting. `drm_list_devices` lists `card*`
  nodes, not render nodes.
- **Boot entries can be read, not trusted.** The cmdline validator is a denylist, and for a UKI or an EFI program `options`
  is at most part of the story: see `bootloader_entry_boot_kind`.
- **The A/B update flow cannot run yet.** `update_apply` needs `agnos.slot=` on the kernel cmdline, and nothing emits it. The
  flow is tested against a model of the boot, not against real firmware.
- **Updates are not authenticated.** The sha256 catches a corrupt image, not a forged one.
- **Not thread-safe, and `alloc` never frees.** Parsers use static buffers, and results stay in the heap for the life of the
  process, so a long-lived poller grows.

## Build

```sh
cyrius build src/main.cyr build/agnodrm   # compile
cyrius run src/main.cyr                   # compile + run
cyrius check src/main.cyr                 # syntax check only
cyrius test                               # run tests/tcyr/*.tcyr
cyrius distlib                            # regenerate dist/agnodrm.cyr (all nine modules)
cyrius distlib core                       # regenerate dist/agnodrm-core.cyr
scripts/audit.sh                          # full local quality run (14 gates, as CI runs them)
```

## Consumer quickstart

Two bundles ship, and a dependency picks one. `cyrius deps` reads the bundle's `.deps` sidecar for the stdlib leaves it needs.

| Bundle | Modules | Size |
|---|---|---|
| `dist/agnodrm-core.cyr` | error + util + udev + drm | ~60 KB |
| `dist/agnodrm.cyr` | all nine | ~270 KB |

```toml
# cyrius.cyml
[deps.agnodrm]
git = "https://github.com/MacCracken/agnodrm.git"
tag = "1.8.0"
modules = ["dist/agnodrm-core.cyr"]
```

```cyrius
include "lib/agnodrm-core.cyr"

fn main(): i64 {
    alloc_init();
    var cards = alloc(16 * 8);
    var res_t, res_v = drm_list_devices(cards, 16);
    if (is_err_result(res_t) == 1) { return 1; }
    println_int(res_v);
    return 0;
}
var r = main();
sys_exit(r);
```

See [`docs/development/capacity-baseline.md`](docs/development/capacity-baseline.md) for the full compiler-table footprint.

## Quality gates

Every change must pass `scripts/audit.sh`: 14 gates. CI runs the same gates, and adds aarch64 tests and fuzz under qemu:

```
syntax → API surface (snapshot + prose) → capability map → capacity →
build → smoke → tests → fmt drift → lint → vet → fuzz → benchmarks →
dist staleness → lockfile
```

| Gate | Command |
|---|---|
| API surface diff | [`scripts/check-api-surface.sh`](scripts/check-api-surface.sh) |
| API surface prose staleness | [`scripts/gen-api-surface-prose.sh`](scripts/gen-api-surface-prose.sh) `--check` |
| Capability map staleness | [`scripts/gen-capability-map.sh`](scripts/gen-capability-map.sh) `--check` |
| Capacity (<85% all tables) | `cyrius capacity --check src/main.cyr` |
| Fmt drift | `cyrfmt <file>` output must match the committed file (**not** `cyrius fmt` — it rewrites in place and prints nothing) |
| Tests | `cyrius test` |
| Fuzz (10 harnesses) | `fuzz/*.fcyr` under `timeout 10` |
| Benchmarks (23 across 7 groups) | `tests/bcyr/bench_all.bcyr` |
| Dist staleness | `cyrius distlib` and `cyrius distlib core` regenerate the committed bundles exactly |
| Lockfile | `cyrius deps --locked`, first and last: other gates re-vendor `lib/` |

## Docs

- [`docs/benchmarks-rust-vs-cyrius.md`](docs/benchmarks-rust-vs-cyrius.md) — **Rust-vs-Cyrius head-to-head** from the port (0.50.0 Rust, 147 criterion benchmarks → 0.97.1 Cyrius, 30 batch-amortized benchmarks)
- [`docs/architecture/overview.md`](docs/architecture/overview.md) — module map, data flow, consumers
- [`docs/SECURITY-NOTES.md`](docs/SECURITY-NOTES.md) — per-module security considerations
- [`docs/development/state.md`](docs/development/state.md) — live state snapshot (refreshed every release)
- [`docs/development/roadmap.md`](docs/development/roadmap.md) — the Forward plan, the V2.0 backlog, and every completed phase
- [`docs/development/api-surface-1.0.md`](docs/development/api-surface-1.0.md) — auto-generated public API prose
- [`docs/development/capability-map.md`](docs/development/capability-map.md) — per-module kernel-surface map (syscalls, sys_*, exec paths, fs paths) for downstream sandbox-policy authoring
- [`docs/development/capacity-baseline.md`](docs/development/capacity-baseline.md) — compiler-table utilization
- [`docs/doc-health.md`](docs/doc-health.md) — documentation currency ledger (fresh / stale / archive buckets)

## License

GPL-3.0-only
