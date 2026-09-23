# cycc_aarch64 misses undefined *tail* calls and never prints `#deprecated` warnings

**Status:** OPEN — upstream toolchain gaps, **filed with cyrius** as
`docs/development/issues/2026-09-22-agnodrm-aarch64-undefined-tail-call-not-refused.md` (repro in
`repros/2026-09-22-aarch64-undefined-tail-call.cyr`) and
`docs/development/issues/2026-09-22-agnodrm-aarch64-deprecated-warning-never-fires.md` in the cyrius
repo. agnodrm is not exposed today (see below).
**Filed:** 2026-09-22
**Reporter:** agnodrm 1.6.2 (noticed by the fuzz-harness include fix and the `#deprecated` adoption,
then isolated by probe).
**cyrius versions observed:** 6.6.0, 6.6.2, 6.6.4, 6.6.5, 6.6.6.
**Severity:** MEDIUM for agnodrm's gates (one class is invisible on one lane); HIGH for a consumer with
aarch64-only code (a missing symbol ships and traps at runtime).

## 1. Undefined **tail** calls are not refused on aarch64

```cyr
include "lib/syscalls.cyr"
fn main(): i64 { return no_such_fn(2); }
var r = main();
sys_exit(r);
```

| build | result |
|---|---|
| x86_64 / `--agnos` | `warning: undefined function 'no_such_fn'` + `error: refusing to emit binary ...`; exit 1 |
| `--aarch64` | **no diagnostic**, exit 0; the binary SIGILLs under `qemu-aarch64` |
| `--aarch64`, non-tail (`var x = no_such_fn(2); return x + 1;`) | refused like x86_64; exit 1 |

The aarch64 backend emits a tail call as fixup type 4; its undefined-fn check only counts types 2
and 3, so the v6.3.2 hard error never sees a tail call. Non-tail undefined calls *are* caught on
aarch64. agnodrm's own case — `fuzz/fuse_parse.fcyr` without `src/util.cyr`, where every missing
callee was a `return agnodrm_run_checked(...)` tail call — is why the gap first looked total.

## 2. `#deprecated` call-site warnings never print on aarch64

The same source prints `'<fn>' is deprecated: <msg>` on x86_64 and agnos, and nothing on
`--aarch64`, for tail and non-tail calls alike (6.6.0 – 6.6.6). The build and the binary are correct.

## Why agnodrm is not exposed

agnodrm has no aarch64-only code: no `CYRIUS_ARCH_*` / `#ifplat` sites since the 1.4.4
decomposition. Every line the aarch64 lane compiles is also compiled by the x86_64 and agnos lanes,
which refuse undefined calls, tail or not, and print deprecation warnings: in CI, in the release
workflow and in `scripts/audit.sh`. Any future aarch64-only branch must be *run* under
`qemu-aarch64`, not just built, until (1) closes.

## When this closes

When the cyrius filings above resolve. Re-run both probes on the new pin.
