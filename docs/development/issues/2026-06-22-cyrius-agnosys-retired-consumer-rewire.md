# agnosys → agnodrm decomposition: cyrius retired its stale stdlib snapshot → consumer rewire

**Filed:** 2026-06-22 · **Type:** decomposition completion + downstream rewire (ecosystem-owned) · **Driver:** cyrius v6.2.37 deleted its vendored `lib/agnosys.cyr`. This closes the **cyrius-stdlib side** of the `agnosys → agnodrm` decomposition (see `2026-06-18-agnosys-to-agnodrm-decomposition-plan.md`) and tracks the last consumer migrations.

## What changed (cyrius v6.2.37)

cyrius's stdlib carried a **frozen pre-decomposition `lib/agnosys.cyr` (1.4.3 snapshot, 10,198 lines / 736 public fns)** — a leftover from before agnosys became **agnodrm 1.4.4**. It was deleted entirely. The trigger was an agnos-filed issue (agnosys's Linux-MAC `security_*` fns ungated → `cyrius build --agnos` hard-errors on `SYS_LANDLOCK_*`); cyrius premise-checked it as **under-scoped** (8 constants / 11 fns hard-error — landlock PLUS `O_RDONLY/O_WRONLY/O_CREAT/O_TRUNC/O_EXCL` in `mac_read_file`/`mac_write_file`/`audit_read_proc_events`/`pam_*`/`luks_write_keyfile`/`ima_*`/`tpm_seal`) and recognized the whole module as the stale snapshot it was. Per the decomposition, every subsystem already moved to its home — trust/firmware → **sigil**, security/mac/audit → **kavach**, pam → **aegis**, logging → **sakshi**, Linux-eccentric (bootloader/update/netns/fuse/journald) → **agnodrm** — and cyrius's only surviving role (uname/sysinfo) is native in cyrius `lib/sys.cyr` (the v6.1.28 + v6.2.23 carve).

## Replacement surface (cyrius `lib/sys.cyr`)

`sys_uname(out)`, `uname_hostname/release/machine(uts)`, `sys_sysinfo(out)`, `sysinfo_uptime/total_memory/free_memory/procs(info)`, `sys_gettid()`, `sys_geteuid()`, `is_root()` — all `#ifdef`-gated per target with the agnos (40-byte sysinfo / 64-byte uname) vs Linux (120/390-byte) struct divergence handled.

## Who must rewire

Only one consumer resolved cyrius's **stdlib** `agnosys`: **chakshu** (`"agnosys"` in its `cyrius.cyml` `stdlib = [...]`). mihi/iam resolve agnosys as a **git dependency** (`[deps.agnosys]` → `dist/agnosys-core.cyr` @ tag 1.4.0) and are unaffected by the cyrius deletion — but mihi's bundle is the *reason* chakshu needed it.

### mihi (kernel-interface lib) — the root rewire
- `mihi/src/kernel.cyr:21` calls `agnosys_uname(uts)`. Migrate to cyrius `lib/sys.cyr` `sys_uname(out)`.
- **API note (not 1:1):** `agnosys_uname` returns a Result (`Ok(out)` / `err_from_syscall_ret(ret)`); `sys_uname` returns the **raw** syscall ret (`0` / `-errno`). Adapt: `var r = sys_uname(&uts); if (r < 0) { /* -errno */ }`. `uname_hostname/release/machine` are identical (`uts + offset`).
- Once `dist/mihi.cyr` no longer references `agnosys_*`, drop mihi's `[deps.agnosys]` git stanza. Then chakshu/iam's transitive need disappears.

### chakshu (system monitor)
- Drop `"agnosys"` from `stdlib = [...]` in `cyrius.cyml`. chakshu's own `src/` calls no `agnosys_*` fn — it pulled agnosys only to satisfy `agnosys_uname` referenced inside the vendored `dist/mihi.cyr`. Until mihi's bundle is rewired, chakshu can carry `agnosys_uname` via `[deps.agnosys]` git-core (mihi/iam's pattern) instead of the deleted stdlib entry.

### iam (fastfetch-equivalent)
- Transitive via mihi; redirect-safe today (`[deps.agnosys]` git-core 1.4.0). No action until mihi's bundle is rewired, then drop the transitive `[deps.agnosys]`.

## Interim state (honest)

cyrius v6.2.37 deletes the stdlib module **before** chakshu rewires (cyrius user's call — "delete now"). Between that cut and chakshu's `cyrius.cyml` change, chakshu's `cyrius deps` fails to resolve `agnosys` on **all** targets (its `--agnos` build was already broken by the ungated landlock/O_* constants). No other repo is affected.

## Verification after rewires land
- chakshu: `cyrius build src/main.cyr` (host) **and** `cyrius build --agnos src/main.cyr` both clean.
- mihi: `dist/mihi.cyr` regenerated (`cyrius distlib`) with zero `agnosys_*` references; `cyrius build --agnos` clean.

## Cross-ref
- cyrius CHANGELOG **[6.2.37]** (the deletion) · cyrius `docs/development/issues/archived/2026-06-22-agnosys-stdlib-security-fns-not-agnos-gated.md` (the originating agnos-filed issue, RESOLVED-by-retirement).
