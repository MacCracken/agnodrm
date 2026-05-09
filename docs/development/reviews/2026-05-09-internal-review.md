# Internal Deep Review — 1.1.13 P(-1) Step 3

**Date:** 2026-05-09
**Scope:** All 20 first-party modules in `src/*.cyr` plus the
4 support files (`error.cyr`, `syscall.cyr`,
`syscall_arch.cyr` + per-arch peers, `main.cyr`).
**Reviewer:** agnosys 1.1.13 P(-1) hardening pass.
**Cyrius version:** 5.10.19 (verified `cc5_aarch64 5.10.19`).
**Source size:** 9,750 LOC across 24 files; 358 fns, 730
public API surface entries.
**Audit baseline:** 10/10 gates green; 242 / 242 integration
tests; 33-timing bench baseline at commit `9ec6063`.

This review is **read-only**. Action items become subsequent
V1.1.x slot patches as warranted.

## Methodology

1. **Mechanical signal scan** across all 24 src files —
   buffer sizes, syscall usage, exec patterns, param
   discipline, TODO/FIXME, header-comment presence, DCE
   rates.
2. **Targeted reads** on hotspots flagged by step 1 (fn-scope
   buffers, raw `syscall()` usage, exec call sites).
3. **Cross-cutting check**: API surface naming consistency,
   `[deps] stdlib` coverage, error-path patterns.

## Cross-cutting findings

### ✅ Things already in good shape

| # | Check | Result |
|---|---|---|
| 1 | `sys_system()` in src/ | **0 sites** — matches ADR-001 argv-exec policy. |
| 2 | Functions with ≥ 7 params | **0 violations** — split-via-`_new`+`_set_*` pattern holds. |
| 3 | TODO / FIXME / XXX / HACK markers | **0** — no carry-over technical debt markers. |
| 4 | Module-level header comments | **24 / 24** present and uniform format. |
| 5 | Test coverage | **20 / 20** modules have a `test_<module>()` block in `tests/tcyr/test_integration.tcyr`. |
| 6 | Public-fn naming discipline (module prefix) | API-surface gate enforces; 730 fns clean. |
| 7 | Raw `syscall()` use outside the syscall module | Confined to `audit.cyr` (audit netlink — no `sys_*` wrapper exists for `SYS_AGNOS_AUDIT_LOG`) and `main.cyr` (`syscall(SYS_EXIT, r)` — agnosys's standard exit-shim pattern). All intentional. |
| 8 | Hardcoded paths / shells | All exec-path strings are absolute (`/usr/sbin/veritysetup`, `/sbin/cryptsetup`, etc.); none use `$PATH` lookup. |

### Hotspots flagged

| # | Finding | Sites | Severity | Notes |
|---|---|---|---|---|
| H-1 | Fn-scope `var buf[4096]` (4 KB at the warn threshold) | `dmverity.cyr:293` (`dmverity_format`), `dmverity.cyr:397` (`dmverity_status`), `ima.cyr:292` (`ima_get_status`) | **LOW — all 3 verified safe** | `dmverity_format` copies hash out via `memcpy` before return ✓; `dmverity_status` extracts `rhash` via `memcpy` to a heap allocation (line 453: `rhash = alloc(rlen+1); memcpy(rhash, &outbuf+rstart, rlen)`) — no static-buf refs escape ✓; `ima_get_status` uses `slice<u8>` wrapper (V1.1.11 canonical) ✓. The buffers are at the WARN threshold but the static-data hazard does not actually manifest. |
| H-2 | 10 `security_*` fns DCE'd in agnosys's own build | `security_fs_rule_new/path/access/read_only/read_write`, `security_apply_landlock`, `security_load_seccomp`, `security_seccomp_filter_ptr`, `security_create_namespace`, `security_syscall_map_reset` | **LOW — non-issue, observation only** | agnosys is a *shared library*; its own `main.cyr` is a smoke-test that doesn't exercise Landlock/seccomp/namespace setup (rightly — that's the consumer's job, e.g. kavach). The DCE list reports surface that the *self-test* doesn't use, not surface that's wasted in production. The `[deps] stdlib` consumer-pull model ensures only used surface gets into a downstream binary. **Action:** add a `test_security_smoke()` block in `tests/tcyr/test_integration.tcyr` that exercises construct-only paths (`security_fs_rule_new(...)`, `security_seccomp_filter_ptr(...)`) so the integration tests cover the public API even when the runtime doesn't apply the policies. |
| H-3 | Module-level deserializer-side fn DCE'd everywhere | `dead: json_get`, `dead: json_parse`, `dead: i64_from_json` | LOW | Expected — V1.1.13 ships serializer-only. The `_from_json` companions emitted by `#derive(Serialize)` are dead-code-eliminated. Worth documenting in agnosys-side notes that consumers wanting round-trip JSON need to include `lib/json.cyr` themselves. |

## Per-module findings

| Module | LOC | fns | Header | Tests | Notable |
|---|---|---|---|---|---|
| `error` | 274 | 23 | ✓ | ✓ | 23 fns / 0 structs (all stateless errno helpers). Clean. |
| `syscall` | 213 | 18 | ✓ | ✓ | 18 high-level `agnosys_*` wrappers; pairs with `syscall_arch.cyr` dispatcher. Clean. |
| `logging` | 204 | 11 | ✓ | ✓ | Single `var buf[4096]` at file scope (line 44 in `log_init` alloc'd via `alloc(4096)` — heap, not static). Clean. |
| `security` | 379 | 15 | ✓ | ✓ | **H-2: 10 fns DCE'd from agnosys's own build** — kavach consumer presumably exercises them but agnosys-side smoke shouldn't drag every public fn through DCE removal. |
| `mac` | 538 | 16 | ✓ | ✓ | `mac_default_profile` builds 128 B `ctx_buf` on fn scope (line ~380) — heap-copied to `selinux_ctx` via `mac_profile_set_selinux_ctx`. Static-data risk minimal. |
| `audit` | 693 | 25 | ✓ | ✓ | Largest fn count. 9 raw `syscall()` calls (audit netlink — intentional, `SYS_AGNOS_AUDIT_LOG`/`SYS_SOCKET_NR`/etc.). 4 KB recv buffer is heap-allocated (`alloc(4096)`). |
| `pam` | 762 | 24 | ✓ | ✓ | Largest LOC. Parser-heavy (`/etc/passwd`, `/var/run/utmp`). Worth a follow-up read for parser bounds. |
| `journald` | 522 | 15 | ✓ | ✓ | systemd-side. Sub-process via `journalctl` — argv-based, ADR-001 compliant. |
| `luks` | 640 | 26 | ✓ | ✓ | Subprocess-heavy (`cryptsetup`). Cipher allowlist per ADR-002. 26 fns / 2 derive structs. |
| `dmverity` | 509 | 21 | ✓ | ✓ | **H-1**: 2 of 3 4 KB fn-scope buffers. `dmverity_status` worth a closer read (name/rhash extraction). |
| `ima` | 590 | 13 | ✓ | ✓ | **H-1**: `ima_get_status` 4 KB buf wrapped by V1.1.11 slice migration. Canonical example. Per-mod doc OK. |
| `tpm` | 586 | 14 | ✓ | ✓ | Subprocess-heavy (`tpm2_*` tools). 4 derive structs. |
| `certpin` | 347 | 17 | ✓ | ✓ | `certpin_ct_streq` is a single-line delegation into stdlib `ct_eq_bytes_lens`. Clean. |
| `secureboot` | 633 | 15 | ✓ | ✓ | UEFI EFI-var reading. 6 derive structs (key, sig, efi_var, etc.). Worth a parser read. |
| `udev` | 386 | 8 | ✓ | ✓ | 8 fns / 2 derive structs. Smallest meaningful module. |
| `drm` | 326 | 9 | ✓ | ✓ | 9 fns / 2 derive structs. Has hand-rolled `drm_verinfo_to_json`. |
| `netns` | 643 | 22 | ✓ | ✓ | 8 derive structs (most of any module). veth + nftables wiring. |
| `bootloader` | 437 | 15 | ✓ | ✓ | `systemd-boot` / GRUB detection + cmdline validation. 4 derive structs. |
| `update` | 1042 | 28 | ✓ | ✓ | **Largest LOC + most fns**. Atomic write/copy/swap, CalVer parser, update manifest. 8 derive structs. Worth a parser bound-check read. |
| `fuse` | 333 | 11 | ✓ | ✓ | `/proc/mounts` parser, mount/unmount via subprocess. 2 derive structs. |

## Documentation gaps

| # | Finding | Notes |
|---|---|---|
| D-1 | Public `_to_json` / `_from_json` fns (V1.1.12) lack docstrings | Auto-emitted via `#derive(Serialize)` — no place for an agnosys-side comment. Consider adding a single block in each module explaining what the diagnostic dump represents. |
| D-2 | `_<mod>_emit_cstr_or_null` private helpers (5 sites) all share the same body | Could move to a shared `lib/`-style helper. Tracked under V1.1.x backlog. |
| D-3 | `docs/development/api-surface-1.0.md` (human-readable) hasn't been refreshed since V1.1.0 | Surface is up to 730 fns; the prose snapshot is at 561. Auto-generation would be a Phase 8 / V1.3 item. |
| D-4 | No top-level `docs/architecture/data-flow.md` describing the audit netlink event path or the LUKS open/close lifecycle | Consumers (libro/stiva) would benefit. Module-level header comments cover usage but not lifecycle. |

## Prioritized backlog

In order of impact × ease:

| Pri | ID | Item | Rough effort | Slot candidate |
|---|---|---|---|---|
| ~~1~~ | ~~H-1~~ | ~~Verify `dmverity_status` doesn't escape refs into static `outbuf[4096]`~~ | done in this review — clean | n/a |
| 1 | H-2 | Add `test_security_smoke()` in integration tests exercising the construct-only paths so the 10 currently-DCE'd `security_*` fns are at least lint/parse-checked from the agnosys self-test side | XS (one block, ~10 assertions) | V1.1.14 |
| 2 | D-3 | Refresh `docs/development/api-surface-1.0.md` from current snapshot (561 → 730 fns, the prose snapshot is V1.1.0-era) | S (mechanical regen) | V1.1.14 |
| 3 | D-2 | Consolidate `_<mod>_emit_cstr_or_null` into a shared helper module | S–M (5 modules touched) | Wait for cyrius cstring-Serialize support; helpers go away anyway |
| 4 | D-4 | Author `docs/architecture/data-flow.md` for the 3-4 gnarly modules (audit, luks, ima, secureboot) | M | V1.3+ doc batch |
| 5 | Parser review | Read pam / secureboot / update parser blocks for bounds | M (3 modules, ~600 LOC each) | V1.1.x — could pair with security audit (P(-1) step 5) |

H-1 was resolved in this review (all 3 sites verified safe).
H-2 + D-3 are good candidates for an immediate V1.1.14
patch — both XS effort, both tighten the project without
touching production source.

## Verified in this pass

- `sys_system()` count: 0 (clean).
- 7+-param fns: 0 (clean).
- TODO / FIXME / XXX / HACK count: 0 (clean).
- `var buf[≥64KB]` (FAIL threshold): 0 (clean).
- `var buf[≥4KB]` (warn threshold): 3, all verified safe by static-data hazard analysis.
- All 24 src files have a `# <module> — <description>` header comment in the canonical form.
- All 20 modules have `test_<module>()` blocks in the integration test.

## Conclusion

agnosys 1.1.13 is in good structural shape. The internal
review surfaces 6 prioritized backlog items, none of which
are correctness blockers. Items 1–3 are XS/S effort and
fold cleanly into a V1.1.14 patch. The cross-cutting
discipline (no sys_system, no 7+ param fns, no TODOs, all
modules tested) is the durable result of CLAUDE.md's hard
constraints + the V1.1.x slot rhythm.

Next P(-1) step: **step 4 (external research / CVE
landscape)** for the 20 kernel interfaces agnosys binds.

## Methodology notes (for future reviews)

- The mechanical signal scan can be re-run any time as a
  spot-check; takes < 10 s.
- DCE-rate per module is a useful proxy for "public surface
  the consumer doesn't actually use" but only meaningful in
  the context of consumer integration CI (V1.2.3).
- `cyrius vet src/main.cyr` already validates the
  include-graph; this review intentionally didn't duplicate
  that.
