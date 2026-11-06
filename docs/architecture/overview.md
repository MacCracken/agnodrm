# Architecture Overview

## Layout

```
agnodrm/
├── src/           9 modules + main entry point
│   ├── main.cyr   self-test entry, includes the core modules
│   ├── error.cyr  error kinds, errno mapping, Result helpers
│   ├── util.cyr   subprocess capture, exclusive temp files, read/write, scratch memory
│   ├── udev.cyr   device enumeration via udevadm
│   ├── drm.cyr    DRM device enumeration, version and capability ioctls
│   ├── journald.cyr  systemd journal send/query
│   ├── netns.cyr  network namespace create/destroy, veth, nftables
│   ├── bootloader.cyr  systemd-boot/GRUB detection, BLS entries, cmdline validation
│   ├── update.cyr  atomic file ops, version compare, A/B slot flow
│   └── fuse.cyr   FUSE mount parsing, mount/unmount
├── lib/           vendored Cyrius stdlib, gitignored; populated by `cyrius deps` from the
│                  `[deps] stdlib` list in cyrius.cyml
├── dist/          bundled distributions (`cyrius distlib [profile]` output)
│   ├── agnodrm.cyr       all nine modules concatenated
│   ├── agnodrm-core.cyr  error + util + udev + drm
│   └── *.deps            the stdlib leaves each bundle needs, read by `cyrius deps`
├── tests/
│   ├── tcyr/      test_integration, and test_powercut for the A/B flows
│   └── bcyr/      benchmarks (.bcyr)
├── fuzz/          parser fuzz harnesses (.fcyr)
├── scripts/       audit.sh, version-bump.sh, bench-history.sh, check-api-surface.sh,
│                  gen-api-probe.sh, gen-api-surface-prose.sh, gen-capability-map.sh
└── build/         compiled binaries (gitignored)
```

## Include Model

Cyrius uses a flat include model, and each `.cyr` file is a module. A consumer takes one of two bundles through
`[deps.agnodrm]`; see the README. Inside this repo, tests include what they need from `lib/` and `src/` directly:

```
include "lib/alloc.cyr"
include "lib/syscalls.cyr"
include "src/error.cyr"
include "src/udev.cyr"
```

Cyrius provides **include-once semantics**, so a file included twice is processed once. Modules include most of their
dependencies, and `cyrius check` accepts each alone. `cyrius distlib [profile]` reads the `[lib]` or
`[lib.core]` `modules` list from `cyrius.cyml`, concatenates in declared order and strips the `src/` includes, so a bundle
needs only the stdlib leaves in its `.deps`.

## Data Flow

```
                   ┌─────────────────────────────────────────┐
                   │           Consumer Programs              │
                   └──────────────┬──────────────────────────┘
                                  │ dist/agnodrm-core.cyr or dist/agnodrm.cyr
                   ┌──────────────▼──────────────────────────┐
                   │             src/ modules (9)             │
                   │  error → util → udev, drm, journald, ... │
                   └──────────────┬──────────────────────────┘
                                  │ stdlib, and argv-exec of host tools
                   ┌──────────────▼──────────────────────────┐
                   │    lib/ stdlib      udevadm, journalctl, │
                   │                     ip, nft, bootctl ... │
                   └──────────────┬──────────────────────────┘
                                  │ sys_* helpers
                   ┌──────────────▼──────────────────────────┐
                   │    Linux x86_64 / aarch64, or agnos      │
                   └─────────────────────────────────────────┘
```

The per-module surface, down to each syscall wrapper, subprocess and path, is in
[`../development/capability-map.md`](../development/capability-map.md), generated from the source.

## Module Dependency Graph

Every module depends on **error.cyr** and most on **util.cyr**. Beyond those:

| Group | Modules | Kernel or system interface |
|-------|---------|----------------------------|
| Core, device | udev, drm | udevadm, `/dev/dri` ioctls |
| Deferred, logging | journald | `/run/systemd/journal/socket`, journalctl |
| Deferred, network | netns | ip, nft |
| Deferred, boot | bootloader, update | `/boot`, `/efi`, bootctl, efibootmgr, dd |
| Deferred, storage | fuse | `/proc/mounts`, fusermount |

## Error Convention

Two error encodings, chosen by call site:

- **Packed (hot path)**: `drm_syserr_pack(kind, errno)` — `kind << 16 | errno`, zero-alloc
- **Heap (diagnostic)**: `drm_syserr_new(kind, errno, message)` — a heap struct with a message

A Result is a register pair, so a call that can fail reads:

```
var res_t, res_v = some_function();
if (is_err_result(res_t) == 1) { return Err(res_v); }
```

Never `return res_t;` or `return res_v;`: the payload alone reaches the caller as a tag, so an `Err` reads as success.

## Memory Model

- **`alloc()`** is a bump allocator and never frees, so it holds results the caller keeps.
- **`_agnodrm_scratch_new` / `_agnodrm_scratch_free`** take scratch from `mmap` and give it back, on Linux. A working buffer goes here.
- **`var buf[N]` inside a fn** is static data, not stack, so it is good for one call's work and never for a returned value.
- No garbage collection and no reference counting.
- Strings are null-terminated C strings at boundaries, and fat `Str` pointers through `lib/str.cyr` inside.

## Consumers

Who each module is meant for is in the [roadmap](../development/roadmap.md#consumer-map-durable), and who actually pulls the
bundle is in [`state.md`](../development/state.md).
