# agnosys: `sys_stat` x86_64 portability gap in `fuse_validate_mountpoint`

**Filed:** 2026-05-01
**Reporter:** sigil 3.0 (downstream consumer of agnosys 1.0.4)
**agnosys version observed:** 1.0.4
**cyrius version active:** 5.7.48
**Severity:** LOW (latent runtime crash; benign for current
consumers because no production caller hits the function)

## Summary

`src/fuse.cyr:267` calls `sys_stat(path, statbuf)` inside
`fuse_validate_mountpoint`. Cyrius 5.7.48's stdlib provides
`sys_stat` only in `lib/syscalls_aarch64_linux.cyr`; the
x86_64 peer file `lib/syscalls_x86_64_linux.cyr` does not
expose a `sys_stat` wrapper. agnosys's own
`src/syscall_x86_64_linux.cyr` does not fill the gap either.

Result: every x86_64 consumer build that includes the bundled
`dist/agnosys.cyr` emits

```
warning: undefined function 'sys_stat'
error: undefined function 'sys_stat' (will crash at runtime)
```

at link time. The cyrius compiler stubs the function so build
succeeds, but any caller that actually reaches
`fuse_validate_mountpoint` on x86_64 will SEGV at runtime.

## Reproduction

Any x86_64 consumer that pulls `lib/agnosys.cyr` into a build:

```bash
cd /home/macro/Repos/sigil
CYRIUS_DCE=1 cyrius build programs/smoke.cyr build/sigil
# → warning: undefined function 'sys_stat'
# → error: undefined function 'sys_stat' (will crash at runtime)
```

DCE marks `fuse_validate_mountpoint` unreachable in sigil's
case (no FUSE call site), so the link-time warning is benign
for sigil. Any consumer that *does* call
`fuse_validate_mountpoint` on x86_64 hits the runtime crash.

## Root cause

stdlib surface gap — `sys_stat` is aarch64-only in cyrius
5.7.48. The aarch64 wrapper at
`lib/syscalls_aarch64_linux.cyr:346` is built on top of
`SYS_NEWFSTATAT (79)` with `AT_FDCWD`. The x86_64 peer file
does not include the equivalent wrapper.

Cross-reference: yukti 2.2.1 hit the same gap and shipped its
own `sys_stat` shim at `dist/yukti.cyr:40` —

```
fn sys_stat(path, buf) {
    # x86_64 newfstatat(AT_FDCWD, path, buf, 0)
    return syscall(262, -100, path, buf, 0);
}
```

Per `dist/yukti.cyr:38-40` and `docs/development/cyrius-usage.md`,
yukti's stance: "Stdlib provides sys_stat on aarch64 only; fill
the x86 gap so yukti src/ can call sys_stat(path, buf)
portably."

## Options

### Option A — fix agnosys-side (preferred for fast turnaround)

Add the same x86 shim to `src/syscall_x86_64_linux.cyr`:

```
#ifdef CYRIUS_ARCH_X86
fn sys_stat(path, buf) {
    # x86_64 newfstatat(AT_FDCWD, path, buf, 0). AT_FDCWD = -100.
    return syscall(262, -100, path, buf, 0);
}
#endif
```

This brings agnosys to parity with yukti's stance and fixes
all downstream consumers without waiting on cyrius. Risk:
duplicated shim across yukti / agnosys / future consumers —
each has to maintain its own copy of the same 1-line wrapper.

### Option B — push to cyrius stdlib (proper long-term fix)

Add `sys_stat` (and consider `sys_fstat`) to
`lib/syscalls_x86_64_linux.cyr` so the surface matches the
aarch64 peer. This is the durable answer: every consumer that
needs `sys_stat` portably gets it from the stdlib without
re-shimming. Risk: longer turnaround through the cyrius
release cycle.

Recommended path: Option A in agnosys 1.0.5 to unblock
downstream now, then push Option B upstream for cyrius 5.8.x
(or whichever minor's accepting stdlib portability work next).
agnosys can drop its shim once the stdlib version lands.

## Downstream observations

- **sigil 3.0** (this filing's origin): emits the warning on
  every default x86_64 build. DCE eliminates the call site, so
  no runtime impact today. Documented in sigil's CHANGELOG
  Unreleased section as a pre-existing benign warning carried
  in via the agnosys 1.0.4 merge.
- **yukti 2.2.1**: sidestepped via its own shim; not affected.
