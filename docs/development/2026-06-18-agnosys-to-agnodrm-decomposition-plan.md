# Surgical plan: agnosys → agnodrm decomposition

**Date:** 2026-06-18 · **Status:** approved disposition, pre-execution
**Driver:** the cross-target ABI audit showed agnosys is over-scoped — a Linux
security/firmware daemon wearing the "agnostic-systems" name, with a syscall
layer redundant against cyrius. It decomposes: each subsystem to its proper home,
the device/DRM core survives as **`agnodrm`**.

## Core finding — cyrius already owns the agnostic-systems syscall layer
cyrius's language libs are the canonical cross-platform syscall/io surface:
`syscalls_x86_64_{linux,agnos}.cyr` (per-target raw `sys_*`) + `io.cyr`
(portable `file_open`/`read`/`write`/`stat`) + `fs.cyr` + `process.cyr` + `args.cyr`.
agnosys's `syscall.cyr` is *"thin wrappers… Requires: lib/syscalls.cyr"* — it sits
on top of cyrius. So agnosys's syscall layer is redundant; cyrius wins.

## Disposition (final)

| agnosys module(s) | Disposition | Destination |
|---|---|---|
| `udev`, `drm` (+ `error`, `util` they need) | **SURVIVE — rename repo → `agnodrm`** | the device/DRM model |
| `syscall_x86_64_linux`, `syscall_aarch64_linux`, `syscall_arch` | **DELETE** | cyrius `syscalls_*.cyr` is canonical |
| `syscall.cyr` (Result wrappers + `getpid`/`uname`/`sysinfo`) | **FOLD value-add → cyrius** | cyrius gains the sysinfo/uname/getpid helpers; agnosys syscall layer retired |
| `logging`, `journald` | **FOLD** | **sakshi** (logging) |
| `security` (Landlock/seccomp) | **FOLD** | **kavach** (it uses landlock_/seccomp_ 37×) |
| `mac` (SELinux/AppArmor) | **FOLD** | **kavach** (it uses mac_key/mac_hex — NOT aegis; usage-corrected 2026-06-18) |
| `audit` | **FOLD** | **kavach** (audit_chain) primary; **libro** also uses audit_entries — shared, home TBD |
| `pam` | **FOLD (preserve — do NOT drop)** | **aegis** (security daemon). PAM is cross-platform auth (UNIX *and* DOS both lean on it) — keep the work. The agnos-PAM equivalent is **TBD** (some form will exist; shape undecided); lands in aegis Linux-backed now with the agnos auth model a tracked open question. (Corrected 2026-06-18 — was wrongly marked DROP.) |
| `luks`, `dmverity` | **FOLD** | **sigil** (trust/crypto — disk encryption/integrity) |
| `ima`, `tpm`, `secureboot`, `certpin` | **FOLD** | **sigil** (measured boot / firmware trust / cert pinning) |
| `bootloader`, `update` | **DEFER → post-v1** | **Linux-eccentric, orphaned.** No consumer: agnova defines its OWN `BootloaderType`/`BootloaderConfig` (doesn't use agnosys's); gnoboot doesn't dep agnosys; kybernet/iam/libro/nein don't use them. The whole boot/A-B-update group is deeply Linux-specific — there's no agnos story yet, so preserve in place and revisit post-v1 (user, 2026-06-19). |
| `netns`, `fuse`, `journald` | **DEFER → post-v1** | part of the Linux-eccentric group (network namespaces / FUSE / systemd-journal) — no agnos analog; preserve in place, revisit post-v1 (user, 2026-06-19). |

## agnodrm — the surviving lib

**Scope:** device enumeration (udev) + DRM/KMS device-node access. The "get a
handle to the device" substrate. Cross-platform by design: Linux udev/drm today,
agnos's device model as the target — agnos-destined, Linux the bootstrap backend.

**Device/GPU stack (resolves the agnodrm↔mabda↔ai-hwaccel redundancy):**
```
ai-hwaccel  (GPU detection: which device + capabilities)  ─┐
                                                           ├─▶ agnodrm
mabda       (GPU foundation: compute / render)            ─┘   (enumerate + open DRM node)
```
- **agnodrm** owns *access*: enumerate devices, open the DRM/KMS node, hand back a device handle. No GPU-compute logic.
- **ai-hwaccel** sits over agnodrm — *detection* (probe which GPU, what it can do).
- **mabda** consumes agnodrm for the *device handle*, then does compute/render.

Each owns exactly one concern; no overlap.

## cyrius redundancy resolution (matched note for the language agent)
1. agnosys's per-arch syscall-number files duplicate `cyrius/lib/syscalls_x86_64_linux.cyr` / `syscalls_aarch64_linux.cyr` → **deleted** as agnosys vacates.
2. `syscall.cyr`'s genuine value-add (`getpid`/`getuid`/`uname`/`sysinfo` Result-typed helpers) **moves into cyrius** so there's one system-info surface, cross-target.
3. File/dir/process ops that agnosys hand-rolled use cyrius `io.cyr`/`fs.cyr`/`process.cyr` — no agnosys copies.

## Execution order (revised — substrate drops LAST)

**Key structural fact (fold-1 analysis):** `logging.cyr` and `syscall.cyr` are
*shared substrate* — every subsystem calls them. So they cannot lead; each
subsystem rewires its `log_*`→`sakshi_*` and syscall usage→cyrius **as it moves**,
and the orphaned substrate is dropped only once its last consumer is gone.
(`logging.cyr`'s entire consumer surface is a single `log_warn` in `audit.cyr`.)

1. **sigil** ← luks, dmverity, ima, tpm, secureboot, certpin — the trust/firmware
   cluster (one coherent move; rewire substrate as it lands, `#ifndef`-guard the
   Linux mechanisms with agnos-native mapping as TODO).
2. **kavach** ← security (Landlock/seccomp); **aegis** ← mac; **phylax/libro** ← audit.
   *(audit carries its lone `log_warn`→`sakshi_warn`; this orphans `logging.cyr`.)*
3. **aegis** ← `pam` ✅ DONE (aegis 1.1.0) — preserve, cross-platform auth.
4. **DEFER → post-v1 (the Linux-eccentric group):** `bootloader`, `update` (orphaned —
   agnova has its own, gnoboot doesn't dep agnosys), `netns`, `fuse`, `journald`.
   No agnos story yet; preserve in place, revisit post-v1.
5. **DROP** the now-orphaned substrate: `logging.cyr` (redundant with sakshi),
   `syscall_*`/`syscall_arch` (redundant with cyrius). `syscall.cyr`'s value-add
   (sysinfo/uname/getpid) → **cyrius** (filed request — language agent).
6. **Rename** agnosys repo → **agnodrm**; trim to udev/drm/error/util; wire
   ai-hwaccel + mabda to consume it; redraw the device seam.

Each fold is a per-repo issue/PR in the *destination* repo (the consumer owns the
landing), not dumped on cyrius — same discipline as the cross-target ABI filings.

## Status (2026-06-19)
- ✅ **sigil 3.8.1** — trust/firmware internalized. ✅ **kavach 3.5.0** — security/mac/audit internalized. ✅ **aegis 1.1.0** — pam folded in.
- ✅ **sakshi 2.4.0** — logging fold: `log_msg_kv` → `sakshi_log_kv` (routed through `_sk_emit`, all targets; 73/0 tests). `log_init_from_env` NOT ported (Linux `/proc/self/environ`, no consumer) → sakshi roadmap as portable `getenv`-based. journald stays post-v1. This makes `logging.cyr` fully droppable at the rename (its last consumer, `audit`, already in kavach).
- ✅ **cyrius request filed** — `cyrius/docs/development/issues/2026-06-19-stdlib-sysinfo-uname-process-identity-cross-target.md`: `syscall.cyr`'s sysinfo/uname/process-identity value-add → cyrius (per-target structs, Result-typed). Per-arch `syscall_*` files just deleted (cyrius's `syscalls_*.cyr` is canonical).
- ✅ **downstream repair roadmap items filed** — libro (re-source tpm from sigil), kybernet (remap core→agnodrm, storage+trust→sigil), phylax (sigil pin 3.8.0→3.8.1, transitive-only).
- ✅ **sigil 3.9.0 — P2 DONE: trust API promoted to `dist/sigil.cyr`.** The blocker is cleared — sigil's dist now exports **105 trust fns** (`tpm_seal`/`tpm_unseal`/`tpm_detect`/`tpm_verify_measured_boot`, IMA, SecureBoot, cert-pin, dmverity, luks). Verified: no duplicate-fn, bundle compiles + `tpm_detect` resolves, self-contained, suite 1475/0. **The downstream tpm rewire (libro/kybernet) is now actionable** — gated only on the rename trigger, no longer on sigil.
- ✅ **CI fallout fixed.** (1) sigil's doc-coverage gate (`cyrius doc --check dist/sigil.cyr`) — the 46 newly-bundled trust fns were undocumented; added adjacent doc comments to all (sys_error 15, tpm_core 13, ima_core 11, certpin_core 7), now 75/0. (2) agnosys's `consumer-integration.yml` matrix still listed **kavach + sigil** as consumers, but both severed `[deps.agnosys]` in the decomposition → vendoring agnosys into them failed. Repointed to the real heavy consumers **kybernet** (`cyrius test src/test.cyr`, 177/0) + **libro** (`cyrius build src/main.cyr`, compiles against agnosys main). Note: bare `cyrius test` is a no-op for these (no `.tcyr`); explicit entry/build is required. (3) sigil's `tests/tcyr/agnosys.tcyr` (trust-wrapper integration test) still `include`d the dropped `lib/agnosys.cyr` — a stale vestige from before 3.8.1 internalized the trust stack; in CI's fresh `lib/` it's file-not-found → `FAIL: agnosys`. Repointed it to the internalized `src/{sys_error,sys_util,sysinfo,*_core}.cyr` modules; now 26/0. Also fixed two latent `scripts/check.sh` snags (pre-existing, not from the decomposition): `CC` default `cc3` → `cycc` (the compiler was renamed at cyrius 6.0.0; `cc3`/`cc5` no longer exist), and `tests/tcyr/var_array_semantics.tcyr` was a diagnostic probe printing a `VERDICT:` line instead of the `N passed/failed` summary check.sh greps → converted to `assert_summary` (faithful to its existing exit-code semantics). sigil test suite now fully green via check.sh. (check.sh's *benchmark* section still SIGILLs under its raw `cat|cycc` path — undefined `_sigil_random_fill` — but that's a pre-existing check.sh-only limitation; sigil CI benches via `cyrius bench`, which passes.)
- ⏸ **post-v1**: bootloader/update/netns/fuse/journald (Linux-eccentric, no agnos story).
- ✅ **agnodrm rename EXECUTED (structural core), 2026-06-19.** Folder `agnosys`→`agnodrm` (remote was already `agnodrm.git`). Deleted the 15 moved modules (trust 6, security/mac/audit 3, pam, logging, syscall×4). Survivors: **error, util, udev, drm** (device core) + **journald, netns, bootloader, update, fuse** (deferred post-v1) + main. Manifest rewritten (`name=agnodrm`, `[lib]`=survivors, the 5 domain profiles → single `[lib.core]`=error/util/udev/drm). `main.cyr` rewritten as a device-model smoke — **builds + runs clean**. Dist regenerated (`dist/agnodrm.cyr` + `dist/agnodrm-core.cyr`, 43 core fns). Identity updated: agnodrm README + CLAUDE headers, agnosticos genesis table row.
- ✅ **CI sweep + audit green (2026-06-19).** All three workflows swept to `agnodrm` + `core`-only profile: `ci.yml` (build/dist/smoke), `release.yml` (archive/asset names), `consumer-integration.yml` (**paused** — cron disabled + job `if: false` — its consumers break against trimmed agnodrm until they rewire; eventual consumers are ai-hwaccel/mabda). Generated-doc gates regenerated: api-surface snapshot+prose (730→315 fns), capability-map. `scripts/audit.sh` swept (build/agnodrm, "agnodrm ready"). **Test suite trimmed**: `test_integration.tcyr` 22→9 survivor tests (93/0); `bench_all.bcyr` 11→6 survivor benches; deleted 5 obsolete fuzzers (pam/audit/certpin/luks) + `bench_compare`. Made the deferred survivors self-contained: journald inlined `SYS_SOCKET_NR`/`SYS_SENDTO_NR`, util.cyr inlined `agnosys_fsync`/`agnosys_rename` (`UTIL_SYS_*` consts, avoid stdlib collision). **`scripts/audit.sh` now passes all 11/11 stages.**
- ✅ **VERSION cut 1.4.4** (2026-06-19) — patch line continued (user's call); CHANGELOG Breaking+Changed entry; dist stamped; version-stamped gen-docs refreshed.
- ✅ **`util.cyr` symbol rename DONE** — `agnosys_*` → `agnodrm_*` across all 9 helpers + 12 call sites; history prose preserved; audit 11/11 still green.
- ✅ **Doc audit DONE (active layer)** — README/CLAUDE/CONTRIBUTING/SECURITY/util-header/state.md (module table → 9 survivors + metrics)/roadmap.md (scope + consumer map → ai-hwaccel/mabda/soorat/nein)/doc-health (+ 1.4.4 rename-audit ledger entry)/agnosticos genesis. Historical docs (ADRs/audit/issues/reviews/pre-1.4.4 CHANGELOG+history) preserved. Deep historical-doc polish staged in doc-health.
- ✅ **Downstream rewire (3 of 5) DONE + patched:**
  - **libro 2.7.5** — tpm → sigil 3.9.0 (dropped `[deps.agnosys]`, removed the agnosys include); `cyrius build -D LIBRO_TPM` OK.
  - **nein 1.5.4** — dropped the vestigial `[deps.agnosys]` (no symbol used; broken `../agnosys` path); build clean.
  - **kybernet 1.3.5** — dropped agnosys-core (vestigial) + storage/trust → new `[deps.sigil]` 3.9.0; bumped libro 2.7.4→2.7.5; `cyrius test` 177/0 (CI needs libro 2.7.5 tag live).
  - ⏸ **mihi + iam — DEFERRED (gated on the cyrius uname/sysinfo request).** mihi uses `agnosys_uname` + `UTS_*` (the uname surface whose replacement is the filed cyrius request); iam is transitive via mihi. Both redirect-safe (git+tag 1.4.0, not broken). Roadmap items added to both. Drop when cyrius adopts uname (or inline a uname wrapper sooner).

## Open / watch
- agnodrm's cross-target device backend (Linux udev/drm vs agnos device model) is its own port — handle as the agnos device consumers actually need it ("hit them as we hit them").
- Where a folded subsystem has no agnos-native analog yet (IMA/TPM/SecureBoot trust), it lands in sigil `#ifndef CYRIUS_TARGET_AGNOS`-guarded with the agnos mapping a tracked TODO.
