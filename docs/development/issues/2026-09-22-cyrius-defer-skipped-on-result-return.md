# cyrius `defer` block is skipped when a fn returns a value-form `Result`

**Status:** OPEN — upstream compiler defect, **filed with cyrius** as `docs/development/issues/2026-09-22-agnodrm-defer-skipped-on-value-form-result-return.md` (repro: `docs/development/issues/repros/2026-09-22-defer-skipped-on-result-return.cyr`) in the cyrius repo. Worked around in agnodrm 1.6.2 (no `defer` left in `src/`).
**Filed:** 2026-09-22
**Reporter:** agnodrm 1.6.2 (found by the raw-syscall → stdlib-helper sweep: before/after syscall traces showed no `close()` for fds the code `defer`-closes).
**cyrius versions observed:** 6.6.0, 6.6.2, 6.6.4 and 6.6.6 — every 6.6.x installed. The value-form `Result` arrived at 6.6.0.
**Severity:** HIGH for any consumer — a silent resource leak on every call of every affected fn, with no diagnostic. In agnodrm it leaked one fd (or socket) per call in eight fns and left a temp file behind per call in a ninth.

## Summary

A `defer { ... }` block runs when the function returns a single value, but **not** when it returns a
value-form `Result` / `Option` pair (`return Ok(x);`, `return Err(e);`, or a tail call such as
`return drm_err_io(...)` / `return other_result_fn(...)`).

## Reproducer

```cyr
include "lib/string.cyr"
include "lib/alloc.cyr"
include "lib/tagged.cyr"
include "lib/syscalls.cyr"
include "lib/fmt.cyr"

fn g_pair(p): i64 {                      # returns a Result pair
    var fd = sys_open(p, O_RDONLY, 0);
    if (fd < 0) { return Err(fd); }
    defer { sys_close(fd); }
    return Ok(fd);
}

fn g_plain(p): i64 {                     # returns a single value
    var fd = sys_open(p, O_RDONLY, 0);
    if (fd < 0) { return fd; }
    defer { sys_close(fd); }
    return fd;
}

fn main(): i64 {
    var i = 0;
    while (i < 4) { var t, v = g_pair("/etc/hostname"); fmt_int(v); syscall(1, 1, " ", 1); i = i + 1; }
    i = 0;
    while (i < 4) { var fd = g_plain("/etc/hostname"); fmt_int(fd); syscall(1, 1, " ", 1); i = i + 1; }
    return 0;
}
var rr = main();
syscall(60, rr);
```

Output on 6.6.0 / 6.6.2 / 6.6.4 / 6.6.6 (x86_64):

```
3 4 5 6 7 7 7 7
```

`g_pair` never closes (fds climb 3 → 6); `g_plain` closes every time (fd 7 is reused). Native
`gdb catch syscall` and `qemu-aarch64 -strace` traces agree: the pair-returning path issues no
`close()`. Expected: `3 3 3 3 3 3 3 3`.

## Impact on agnodrm (1.6.0 – 1.6.1)

Every `defer` in `src/` sat in a Result-returning fn, so none of them ever ran:

| fn | leaked per call |
|---|---|
| `drm_list_devices` | the `/dev/dri` directory fd |
| `fuse_parse_proc_mounts` | the `/proc/mounts` fd |
| `journald_send`, `journald_send_fields` | one AF_UNIX socket |
| `update_atomic_write` | the temp-file fd |
| `update_atomic_copy` | the source and temp fds |
| `update_load_state`, `update_check` | the state / manifest fd |
| `netns_apply_nftables_ruleset` | the `/run/agnos/nft-tmp-<pid>.conf` temp file (its `defer` was the unlink) |

A long-running caller eventually hits `EMFILE`; a logging daemon calling `journald_send` gets there
fastest.

## Workaround (1.6.2)

No `defer` in agnodrm sources. Each fn releases what it acquired explicitly on every exit path,
usually as soon as the resource is no longer needed (e.g. close right after the read). The rule is
recorded in `src/error.cyr`'s Result-conventions block and in CLAUDE.md's Cyrius Conventions.
`tests/tcyr/test_integration.tcyr` `test_fd_hygiene` pins it: it drives the success and the
fd-already-open error paths of the fd-holding fns three times and asserts the lowest free fd did not
move. Against the 1.6.1 code it fails with `got 37, expected 4` (33 leaked fds, 11 per round).

## When this closes

When cyrius runs `defer` on pair returns. Then `defer` may come back in agnodrm — but only with
`test_fd_hygiene` still passing, and only after re-running the reproducer above on the new pin.
