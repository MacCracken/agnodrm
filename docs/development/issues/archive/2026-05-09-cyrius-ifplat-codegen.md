# cyrius `#ifplat <arch>` directive doesn't gate the non-matching arch's body

**Status:** CLOSED — obsolete for agnodrm (archived 2026-09-22 at 1.6.2). The two arch-peer files it would have migrated left the repo in the 1.4.4 decomposition; agnodrm now has no arch-gated code at all.
**Filed:** 2026-05-09
**Reporter:** agnosys 1.1.14 (during V1.1.15 / V1.2.1 `#ifplat` migration attempt — see `docs/development/state.md` V1.1.x slot list).
**cyrius version observed:** 5.10.19 (verified `cc5_aarch64 5.10.19`).
**Severity:** LOW — workaround (continue using `#ifdef CYRIUS_ARCH_<UPPER>`) is documented in cyrius's own `lib/syscalls.cyr` v5.4.19 note. Don't refile.

## Pre-existing note in cyrius

`lib/syscalls.cyr` (cyrius v5.4.19+) explicitly defers the same migration:

> v5.4.19 added the `#ifplat` preprocessor directive (sugar for `#ifdef CYRIUS_ARCH_<UPPER>`) but the call-site migration of this file and its peers to the new surface is deferred: under certain test shapes the migrated form triggers a codegen regression not yet root-caused. Directive available for new consumers; existing `#ifdef` call sites stay on the proven path until the regression ...

This issue is the call-site reproducer for that note from agnosys's perspective.

## Reproduction

agnosys's two arch-peer files self-gate with `#ifdef CYRIUS_ARCH_<UPPER>` so a single `dist/agnosys.cyr` bundle can ship both peers and only the matching arch's block compiles. Migrating to `#ifplat <arch>` produces:

### `src/syscall_x86_64_linux.cyr` (the migration)

```cyr
# was: #ifdef CYRIUS_ARCH_X86
#ifplat x86

enum SysNrAgnos {
    SYS_PRCTL = 157;
    AGNOS_SYS_FSYNC = 74;
    AGNOS_SYS_RENAME = 82;
}

fn agnosys_fsync(fd) {
    return syscall(AGNOS_SYS_FSYNC, fd);
}

fn agnosys_rename(old_path, new_path) {
    return syscall(AGNOS_SYS_RENAME, old_path, new_path);
}

#endif
```

### `src/syscall_aarch64_linux.cyr` (peer; uses `AT_FDCWD` from stdlib)

```cyr
# was: #ifdef CYRIUS_ARCH_AARCH64
#ifplat aarch64

enum SysNrAgnos {
    AGNOS_SYS_FSYNC = 82;
    AGNOS_SYS_RENAMEAT2 = 276;
}

fn agnosys_rename(old_path, new_path) {
    # AT_FDCWD comes from lib/syscalls_aarch64_linux.cyr (stdlib; aarch64-only).
    return syscall(AGNOS_SYS_RENAMEAT2, AT_FDCWD, old_path, AT_FDCWD, new_path, 0);
}

#endif
```

### Build output (x86_64 target, agnosys main.cyr)

```
compile src/main.cyr -> build/agnosys [x86_64]
  warning:src/syscall_aarch64_linux.cyr:31: duplicate fn 'agnosys_fsync' (last definition wins)
  warning:src/syscall_aarch64_linux.cyr:38: duplicate fn 'agnosys_rename' (last definition wins)
  error:src/syscall_aarch64_linux.cyr:39: undefined variable 'AT_FDCWD' (missing include or enum?)
FAIL
```

The errors originate from the aarch64-peer file — which on x86_64 build SHOULD be entirely gated out by `#ifplat aarch64`, but cc5 still parses the body. The undefined `AT_FDCWD` is the giveaway: that symbol is defined in `lib/syscalls_aarch64_linux.cyr` (only included on aarch64 builds), so the fact that x86 cc5 reaches it means the gate failed.

### Reverting to `#ifdef CYRIUS_ARCH_X86 / AARCH64`

Same source, same cyrius 5.10.19, only `#ifplat <arch>` → `#ifdef CYRIUS_ARCH_<UPPER>` change: x86 build clean, aarch64 cross-build clean, both run on real hardware. So the gate works for `#ifdef`; only `#ifplat` fails.

## Why this matters for agnosys

V1.1.15 / V1.2.1 was scoped as the cosmetic migration of agnosys's two arch peers to the modern `#ifplat` form. The slot deferred when the migration triggered the documented regression. agnosys reverted to `#ifdef CYRIUS_ARCH_<UPPER>` and tracks the deferral here.

## Mitigation when fixed

Two-line sed migration:

```sh
sed -i 's|^#ifdef CYRIUS_ARCH_X86$|#ifplat x86|' src/syscall_x86_64_linux.cyr
sed -i 's|^#ifdef CYRIUS_ARCH_AARCH64$|#ifplat aarch64|' src/syscall_aarch64_linux.cyr
```

Plus a comment update in `src/syscall_arch.cyr`. Total: 3 file diffs.

## Why this isn't filed upstream as a fresh issue

Cyrius's own stdlib note above is canonical; an agnosys-side ticket would just duplicate it. Wait for cyrius's stdlib to migrate first — that's the signal that the regression is fixed.

## Reproduction artifact

The two pre-migration files (working) are committed at agnosys HEAD; the migrated forms above are exact diffs. Build is reproducible with the sed commands shown.

## Status

- agnosys cyrius pin: 5.10.19 (no change — pin stays).
- agnosys V1.1.15 / V1.2.1: deferred. Slot reopens when cyrius lands the `#ifplat` codegen fix.

## Resolution (archived 2026-09-22, agnodrm 1.6.2)

**Nothing left to migrate.** `src/syscall_x86_64_linux.cyr` and `src/syscall_aarch64_linux.cyr` moved to
cyrius's stdlib with the rest of the syscall layer in the agnosys → agnodrm decomposition (1.4.4). A grep
of `src/`, `tests/` and `fuzz/` at 1.6.2 finds **zero** `CYRIUS_ARCH_*` or `#ifplat` sites: per-arch
differences are now the stdlib peers' job (per-target `SYS_*` / `O_*` names, which 1.6.1 and 1.6.2 adopted).

The underlying upstream note is still in place at cyrius 6.6.6 — `lib/syscalls.cyr` keeps its own call
sites on `#ifdef CYRIUS_ARCH_*` — so the advice stands for any future arch-gated code: use
`#ifdef CYRIUS_ARCH_<UPPER>`, not `#ifplat`. CONTRIBUTING.md carries that rule and now links here.
