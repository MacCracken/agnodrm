# Agnosys Roadmap

> **Agnosys** is the AGNOS kernel interface library. Cyrius bindings for Linux
> kernel syscalls and security primitives. Consumers include only the modules
> they need.
>
> Genesis repo: [agnosticos](https://github.com/MacCracken/agnosticos)
>
> **Live state** (versions, sizes, counts, in-flight) → [`state.md`](state.md).
> Roadmap is durable: completed phases stay; future phases get appended.

## Scope

Agnosys owns **Cyrius bindings to Linux kernel interfaces**. It does NOT own:
- **Higher-level device abstraction** → yukti (consumes agnosys[udev])
- **Sandbox policy engine** → kavach (consumes agnosys[landlock,seccomp])
- **Firewall rules** → nein (consumes agnosys[netns])
- **Container runtime** → stiva (consumes agnosys[luks,dmverity])
- **Rendering pipeline** → soorat (consumes agnosys[drm])

## Phase 1 — Core (V0.1) ✅

- [x] `error` — SysError types, errno mapping, Result helpers
- [x] `syscall` — getpid/uid/hostname/sysinfo wrappers
- [x] `logging` — Log level control via AGNOSYS_LOG env var
- [x] CI/CD pipeline (ci.yml, release.yml)
- [x] Community files (SECURITY.md, CONTRIBUTING.md, CODE_OF_CONDUCT.md)

## Phase 2 — Security Modules ✅

- [x] `security` — Landlock filesystem sandboxing, seccomp-BPF syscall filtering, namespace creation
- [x] `mac` — SELinux/AppArmor detection and context management
- [x] `audit` — Kernel audit netlink socket, rule management
- [x] `pam` — PAM service inspection, passwd/who parsing

Consumer validation: **kavach**, **aegis**, **shakti**, **libro**

## Phase 3 — Storage, Integrity & Trust ✅

- [x] `luks` — LUKS2 encrypted volume management
- [x] `dmverity` — dm-verity integrity verification
- [x] `ima` — IMA measurements, policy rules
- [x] `certpin` — Certificate pin validation, SPKI computation
- [x] `tpm` — TPM2 device, PCR reading, seal/unseal
- [x] `secureboot` — Secure Boot EFI variable reading
- [x] `fuse` — FUSE mount parsing, mount/unmount

Consumer validation: **stiva**, **sigil**, **ark**

## Phase 4 — System Services & Device ✅

- [x] ~~`agent`~~ — *(moved to agnosai crate)*
- [x] `netns` — Network namespace create/destroy, veth, nftables
- [x] `udev` — Device enumeration via udevadm
- [x] `drm` — DRM device enumeration, ioctl version/caps
- [x] `journald` — Systemd journal send/query
- [x] `bootloader` — systemd-boot/GRUB detection, cmdline validation
- [x] `update` — Atomic file ops, version comparison

Consumer validation: **daimon**, **nein**, **yukti**, **soorat**, **argonaut**, **ark**

## Phase 5 — Cyrius Port (V0.60.0) ✅

## Phase 6 — Compiler Upgrade & Optimization (V0.90.0) ✅

## Phase 7 — Scaffold Hardening & Audit (V0.95.0) ✅

- [x] `cyrius audit` clean pass (24/24: compile, test, lint, format)
- [x] 197 integration assertions across all 20 modules
- [x] 5 bugs fixed (2 critical, 1 high, 2 medium)
- [x] Cyrius 2.4.0 upgrade with `cyrfmt`/`cyrlint`
- [x] Architecture overview documentation
- [x] Security notes rewritten for Cyrius

## V1.0 — Stable API ✅

Original checklist — closed:

- [x] Consumer migration from monolith `agnos-sys` — **tracked on consumer crates** (sigil, kavach, daimon, argonaut, stiva, nein, ...). 13/13 consumers unblocked
- [x] Quality gate in CI — `cyrius lint`, `cyrius vet`, `cyrius capacity --check`, API surface check, fuzz, integration tests. Bundled as `scripts/audit.sh` for local one-shot runs
- [x] Fuzz testing for parsers — `fuzz/certpin_pin.fcyr`, `fuzz/audit_nlmsg.fcyr`, `fuzz/pam_config.fcyr`. All run under `cyrius build` + 10s timeout at 500 iters in CI
- [x] Additional edge-case tests from audit observations — `test_edge_cases()` in `tests/tcyr/test_integration.tcyr` adds 25 boundary assertions

Freeze prerequisites added pre-1.0 — closed:

- [x] API surface snapshot — `docs/development/api-surface-1.0.md` (556 public fns, 20 modules, 0 outliers)
- [x] API surface regression check — `scripts/check-api-surface.sh`; fails on any public fn removed or arity-changed vs. `api-surface-1.0.snapshot`. Wired into CI
- [x] Capacity baseline — `docs/development/capacity-baseline.md`
- [x] README consumer quickstart — per-module and full-bundle patterns documented
- [x] Full naming sweep — 139 public fns renamed so every module carries its prefix. Zero remaining prefix outliers
- [x] Local audit runner — `scripts/audit.sh` (10 gates, mirrors CI)

## V1.0.1 — Toolchain Alignment & CI Hardening ✅ (2026-04-26)

- [x] Cyrius pin 5.2.0 → 5.7.6
- [x] `[build] modules` → `[lib] modules` refactor (binary 306,344 → 73,144 B, −76%)
- [x] CI/release workflows ported to yukti pattern (tarball install, deps verify, fmt-check, lint warn-fail, vet, dist gate, DCE, aarch64 best-effort, tag accepts both `vX.Y.Z` and `X.Y.Z`)
- [x] CLAUDE.md restructured to template (durable rules only); volatile state moved to `docs/development/state.md`
- [x] `docs/development/state.md` created
- [x] P(-1) Scaffold Hardening pass; security audit at `docs/audit/2026-04-26-audit.md`

## Phase 8 — Post-1.0 Backlog (replanned 2026-05-06)

Reorganized into 1.1.x (language-feature adoption) → 1.2.x (ecosystem) → 1.3+ (cross-repo).
The 2026-05-06 P(-1) review against the cyrius 5.9.1 feature surface (vidya
`content/cyrius/language/`) added new slots leveraging `defer`, first-class
slices, tagged-union sum types, exhaustive match, `secret var`, multi-width
struct fields, and `#derive(Serialize)` — none of which existed when the agnosys
port shipped at 5.7.6. See [ADR-004](../adr/004-1-1-x-roadmap-rework.md) for the
reasoning. Audit-derived fixes from the 2026-04-26 P(-1) all landed in 1.0.1
(see [`docs/audit/2026-04-26-audit.md`](../audit/2026-04-26-audit.md)); this
phase covers items that are not security-blocking.

### V1.1 — Language-feature adoption

Theme: leverage cyrius 5.8.x / 5.9.x features that landed after the agnosys
port. Min-cyrius pin stays at 5.9.x for the duration unless a specific bug fix
in a later 5.9.y matters (cyrius 5.9.x is the maintenance line — improvements
and optimizations only, not new features).

#### V1.1.0 — `#derive(accessors)` migration ✅ SHIPPED 2026-05-06

- [x] Migrated all 16 struct-bearing modules' accessors from `store64`/`load64` at fixed offsets to `#derive(accessors)` syntax. 37 derive structs total. (3 modules — error/audit/security — have legitimate non-derive cases documented inline; remaining modules had no heap structs to migrate.)
- [x] Snapshot updated additively — 561 → 721 public fns; no removals or arity changes.
- [x] Slot-by-slot patches: 1.0.6 (mac) → 1.0.7 (fuse/drm/bootloader) → 1.0.8 (dmverity/luks/certpin) → 1.0.9 (udev/journald/audit) → 1.0.10 (ima/tpm/secureboot) → 1.0.11 (pam/netns/update + cyrius 5.9.7) → 1.0.12 (tooling cleanup + cyrius 5.9.14) → 1.0.13 (closeout) → tagged as 1.1.0.

**Rationale:** removes hand-written offset arithmetic across the most-touched code in agnosys; reduces off-by-one risk; readable. Mechanical but invasive (touches every struct), so kept off the 1.0 freeze. Headline 1.1 cycle because every other 1.1.x slot interacts with the accessor surface.

#### V1.1.1 — `defer { }` adoption for resource cleanup ✅ SHIPPED 2026-05-06

- [x] Audit found that the work was already done during the original port — 24 `defer { sys_close(...) }` sites in place across mac/fuse/drm/audit/journald/luks/dmverity/ima/tpm/secureboot/pam/netns/update/security/logging.
- [x] Bench parity verified — no defer-epilogue overhead since no new defer sites added.
- [x] Leak audit — no early-return leaks found. The 9 non-defer `sys_close` sites (audit_open conditional close, drm_close API, bootloader/secureboot existence probes, netns close-before-subprocess, update_get_current_slot read-then-close, security_apply_landlock in-loop close) are all deliberate.

Slot shipped as a verification + audit pass; CHANGELOG `[1.1.1]` documents the findings and the deliberate non-defer cases. No source changes were required.

**Rationale:** exit-path safety; cyrius 5.8.x ships per-defer runtime flags so unreached defers skip cleanly. Today's flag+continue patterns are equivalent in correctness but harder to audit.

#### V1.1.2 — `ct_eq_bytes` in certpin ✅ SHIPPED 2026-05-06 (across 1.1.2 deferral + 1.1.3 reopen)

Initial filing at 1.1.2 deferred: `ct_eq` was not a builtin,
`lib/ct.cyr` shipped only `ct_select`, and `secret var` rejected
scalar declarations (didn't fit cstring-pointer pin storage).
Filed [`docs/development/issues/archive/2026-05-06-cyrius-ct-eq-bytes-stdlib.md`](../issues/archive/2026-05-06-cyrius-ct-eq-bytes-stdlib.md)
proposing `ct_eq_bytes(a, b, n)` for `lib/ct.cyr`.

Upstream resolved in cyrius 5.9.18; agnosys 1.1.3 reopened and
shipped the actual swap:

- [x] cyrius 5.9.18 added `ct_eq_bytes(a, b, n)` to `lib/ct.cyr`
  (canonical XOR-accumulate; doc-comment credits the agnosys
  filing).
- [x] `cyrius.cyml [deps].stdlib` += `"ct"` (auto-prepend).
- [x] `src/certpin.cyr fn certpin_ct_streq(a, b)` body shrunk
  from a 16-line hand-roll to a 5-line cstring wrapper that
  delegates the byte loop into `ct_eq_bytes(a, b, alen)`.
  Length-mismatch early-return preserved (pin length is
  non-secret in agnosys — 44-char base64 SHA-256, fixed by
  spec).
- [x] Bench parity verified: `ct_streq_equal` 125→129ns,
  `ct_streq_diff` 135→140ns (within run-to-run noise; no
  fn-call overhead measurable over the 16+ byte XOR loop).

`secret var` annotation deferred indefinitely — pin storage in
certpin flows through cstring pointers across struct boundaries,
which doesn't fit cyrius's array-only `secret var` contract.
Revisit if/when `secret var` gains a pointer-form or a separate
`secret_str` annotation.

**Rationale:** the compiler-backed primitive is the canonical path post-5.8.x (sigil's PQC code uses it). Our hand-rolled version works but isn't the supported pattern.

(Note: agnosys VERSION 1.1.3 shipped the V1.1.2 reopen; subsequent
slot version numbers may drift from slot numbers as deferrals get
reopened. Slot numbers here are conceptual labels, not version
tags. Refer to CHANGELOG for the operational version history.)

#### V1.1.3 — Exhaustive `match` coverage

- [ ] Adopt `cyrius lint`'s exhaustive-match warning across every enum dispatch in src/* (audit / security / syscall / mac / pam / luks / dmverity / ima / tpm / secureboot / udev / drm / netns / bootloader / update / fuse / journald).
- [ ] Add `_ =>` opt-out arms only where catch-all is the genuine intent (e.g. unknown-errno dispatch); explicit variants elsewhere.
- [ ] Wire `cyrius lint` (already CI-gated) to fail on the new warning class.

**Rationale:** catches new audit/syscall/security enum variants that miss handlers — exactly the class of drift that kernel-API tracking is most likely to introduce.

#### V1.1.4 — Tagged-union sum types in error.cyr

- [ ] Replace `lib/tagged.cyr`-backed Result/Option construction in `src/error.cyr` and the 10 modules using it (35 call sites: tagged_new / tag / payload / is_tag) with first-class `enum Result { Ok(v); Err(e); }` from cyrius 5.8.21+.
- [ ] Public Result-returning fn signatures unchanged — internal representation only.
- [ ] API surface snapshot: no drift expected; verify with `scripts/check-api-surface.sh`.

**Rationale:** the lib/tagged.cyr API still works but is the pre-5.8.21 hand-rolled pattern. First-class sum types compile to byte-identical layout for arity-1, and exhaustive-match (1.1.3) becomes load-bearing once Result is a real enum.

#### V1.1.5 — Multi-width struct fields for kernel binary protocols

- [ ] Annotate kernel-protocol structs with per-field widths (`magic: i32`, `version: i16`, `flags: i8`, etc.) — audit_status, audit_rule_data, dm_verity_args, IMA measurement records, TPM cmd headers, ELF/EFI variable layouts.
- [ ] Replace explicit `store8` / `store16` / `store32` / `load*` calls with named-field reads/writes.
- [ ] Validate against kernel ABI: each touched struct gets a fuzz round on its parser.

**Rationale:** cyrius 5.8.x ships width-correct codegen — `var x: i32 = …` does the right `mov dword [addr], eax`. Today's hand-rolled mixed-width store/load pattern is correct but loses the type system's ability to catch a `store64` where a `store32` was meant.

#### V1.1.6 — Slice migration for syscall + parser buffers

- [ ] Convert `var buf[N]; pass &buf, N` patterns (35 sites today) to `slice<u8>` where the buffer is consumed within a single fn scope.
- [ ] Use `slice_set` / `s.ptr` / `s.len` / `s[i]` (bounds-checked) in netlink frame builders, /proc parsers, EFI variable readers, audit nlmsg parsers.
- [ ] Heap-allocated large buffers stay heap-allocated — slices are layout-compatible with vec / Str so the canonical (ptr, len) primitives still apply.

**Rationale:** bounds-checked indexing on the agnosys parsers (audit netlink, fuse mount entries, EFI var bytes, IMA measurement records) closes the off-by-one class without a runtime cost we can't already amortize.

#### V1.1.7 — `#derive(Serialize)` for module status diagnostics

- [ ] Generate JSON serializers for status structs returned by query fns (mac status, audit status, ima status, secureboot state, tpm caps, drm caps).
- [ ] Consumer-facing benefit: kavach / sigil / argonaut can dump agnosys state to log without writing per-module formatters.
- [ ] Public API addition; document in CHANGELOG `Added`.

**Rationale:** consumer ergonomics. Today every consumer that wants to log agnosys state writes its own formatter. `#derive(Serialize)` ships the canonical one with the module.

### V1.2 — Ecosystem

Theme: consumer-facing wiring and platform discipline. Independent of the 1.1.x
language-feature surface — these are durable infrastructure improvements.

#### V1.2.0 — Multi-profile `cyrius distlib` (was 8.2)

- [ ] Add `[lib.security]` (security + mac + audit + pam) → `dist/agnosys-security.cyr`
- [ ] Add `[lib.storage]` (luks + dmverity + fuse) → `dist/agnosys-storage.cyr`
- [ ] Add `[lib.trust]` (tpm + ima + secureboot + certpin) → `dist/agnosys-trust.cyr`
- [ ] Add `[lib.system]` (journald + bootloader + udev + drm + netns + update) → `dist/agnosys-system.cyr`
- [ ] Add `[lib.core]` (error + syscall + logging) → `dist/agnosys-core.cyr` — kernel-safe subset for AGNOS-kernel direct consumption (no alloc, no syscall, pure enums/types)
- [ ] CI dist-staleness gate extended to all five profiles
- [ ] Release archive ships every profile bundle alongside the full `dist/agnosys.cyr`

**Rationale:** kavach pulls 324 KB today for what it actually uses (~50 KB security surface). Profile bundles cut consumer binary size and clarify the agnosys → consumer wiring. Headline 1.2 cycle because it changes the consumer-facing distribution shape — gets its own minor cycle.

#### V1.2.1 — `#ifplat` cosmetic migration (was 8.3)

- [ ] Migrate `#ifdef CYRIUS_ARCH_X86` / `#ifdef CYRIUS_ARCH_AARCH64` to `#ifplat x86` / `#ifplat aarch64` across `src/syscall_*_linux.cyr` and any other arch-gated blocks.
- [ ] Per-module Linux-only declaration: audit / pam / journald / dmverity / ima / secureboot are kernel-Linux-by-definition (kernel netlink frames, PAM config, dm-verity ioctls).
- [ ] Cross-platform candidates declared: `error`, `syscall` (already split via `lib/syscalls_*.cyr` in cyrius 5.5.x), `logging`, `certpin` (pure crypto, no syscalls).
- [ ] `docs/architecture/NNN-platform-matrix.md` documenting the matrix.
- [ ] Track upstream cyrius macOS/Windows port progress; revisit when consumer demand exists.

**Rationale:** purely cosmetic syntactic uplift on the arch-gated code, plus documentation discipline so accidental Linux-isms in portable modules get caught early.

#### V1.2.2 — Capability map per public fn (was 8.5)

- [ ] `docs/development/capability-map.md` listing every public fn → set of syscalls it can invoke
- [ ] `scripts/check-capabilities.sh` parses module source, derives the actual syscall set, diffs against the doc — fails CI on drift
- [ ] Consumers can map fn → syscall → seccomp filter without reading source

**Rationale:** `docs/SECURITY-NOTES.md` covers per-module concerns at prose level. A machine-checkable surface gives kavach/daimon a programmatic basis for seccomp policy generation.

#### V1.2.3 — Consumer integration CI (was 8.4)

- [ ] Nightly GitHub Actions job per consumer: clone, vendor agnosys main, build, run consumer's tests
- [ ] Failures open an issue tagged `consumer-break` (linked to consumer + agnosys commit)
- [ ] 13 consumers in scope (see `state.md` consumer table); start with sigil + kavach (highest module surface), expand

**Rationale:** v1.0 deferred this to "tracked on consumer crates" — i.e., manual. Automated drift detection means an agnosys patch that breaks sigil's TPM caller fails before that consumer notices.

#### V1.2.4 — `#deprecated` adoption channel

- [ ] Adopt cyrius's `#deprecated("reason / migration")` attribute for any post-1.0 API drift (graceful deprecation path before removal).
- [ ] Document the soft-removal protocol in CONTRIBUTING.md: deprecate → one-minor bake → remove with `Breaking` in CHANGELOG.

**Rationale:** today every public-fn rename is either a hard break (snapshot bump) or a frozen API call. `#deprecated` adds a third channel — warning at every call site, snapshot still passes, consumers see the warning in their CI before the actual removal.

### V1.3+ — Cross-repo / meta-tooling

#### V1.3.0 — `state.md` release post-hook (was 8.6)

- [x] state.md created at 1.0.1
- [ ] Release post-hook auto-bumps state.md (version, binary size, test counts)
- [ ] CI gate that fails the release if state.md `Last refresh` doesn't match the tag

**Rationale:** template's "release post-hook bumps state.md. If the hook doesn't, fix the hook — don't hand-maintain state." Lands when agnosticos meta-tooling supports it (cross-repo concern — hook lives in agnosticos toolchain, not this repo).

## V1.0+ Verification

- [x] **1.1.0** shipped 2026-05-06 — V1.1.0 (`#derive(accessors)`) complete; closeout patch (1.0.13) clean; 16 of 16 struct-bearing modules migrated. See CHANGELOG `[1.1.0]` for the consumer banner and `[1.0.13]` for the cumulative baseline.
- [ ] Subsequent V1.1.x slots (1.1.1 through 1.1.7) ship as patches against 1.1.
- [ ] **1.2.0** ships when V1.2.0 (multi-profile distlib) is complete; closeout against the consumer set.
- [ ] V1.2.x slots may ship in any order; gate is bench parity + audit clean.
- [ ] V1.3.0 ships when the agnosticos meta-tooling supports the release post-hook.

## Consumer Map (durable)

Volatile per-consumer status lives in [`state.md`](state.md). The mapping itself is durable:

| Consumer | Modules needed |
|----------|---------------|
| kavach | security (landlock, seccomp) |
| aegis | mac |
| shakti | pam |
| libro | audit |
| stiva | luks, dmverity |
| sigil | tpm, ima, secureboot, certpin |
| ark | fuse, update |
| argonaut | journald, bootloader |
| daimon | security (seccomp), certpin |
| nein | netns |
| yukti | udev |
| soorat | drm |
| hoosh | certpin |
