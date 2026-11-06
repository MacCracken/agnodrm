# Agnodrm Roadmap

> **Agnodrm** is the AGNOS device / DRM model — udev device enumeration +
> DRM/KMS device-node access, on a small error/util support layer. Renamed from
> **agnosys** (the AGNOS kernel-interface library) at 1.4.4; the
> trust/security/syscall/logging subsystems decomposed out to
> sigil/kavach/aegis/cyrius/sakshi.
>
> Genesis repo: [agnosticos](https://github.com/MacCracken/agnosticos)
>
> **Live state** (versions, sizes, counts, in-flight) → [`state.md`](state.md).
> **What is next** is the [Forward plan](#forward-plan), the one list of open work. The
> sections after it are history: completed phases stay, and what each left open has moved
> up. **The phases from Phase 1 down predate the agnosys → agnodrm decomposition** — they
> record how the full library was built before its non-device subsystems moved to their
> proper homes (so they still list the moved modules).

## Scope

Agnodrm owns **device access** — udev enumeration + DRM/KMS — on a small
error/util support layer, plus a deferred Linux-eccentric group (journald /
netns / bootloader / update / fuse) parked post-v1. It does NOT own:
- **GPU detection / compute** → ai-hwaccel + mabda (meant to consume agnodrm[udev,drm])
- **Rendering pipeline** → soorat (meant to consume agnodrm[drm])
- **Firewall rules** → nein (meant to consume agnodrm[netns])
- **Trust / security / firmware / syscall / logging** — moved out at 1.4.4 to
  sigil / kavach / aegis / cyrius / sakshi (see the decomposition plan).

## Forward plan

Every open item is here, so there is one list to keep honest. **S** fits in a sitting. **M** needs its own tests and fuzz.
**L** needs a decision first. The order can change; an item should not vanish without a note.

Two facts from the 1.7.3 review set that order:

- **Nothing calls this library yet.** No repo in the workspace calls any of the 329 public fns. ai-hwaccel, mabda, soorat
  and nein are the intended consumers, and none is wired.
- **The A/B flow has no boot stack.** No repo outside this one reads `next-slot`, emits `agnos.slot=`, creates the
  `AGNOS-A` / `AGNOS-B` boot entries or calls `efibootmgr`, and `update_apply` refuses without `agnos.slot=`. The flow is
  tested against a model of a design, not against anything that boots.

### 1.7.3 — quick items ✅

- [x] `tests/tcyr/test_powercut.tcyr`: a power cut at every durable write of the A/B flows, made permanent.
- [x] `test_integration` no longer runs the host's `sha256sum`, and the digest check catches 3 more mutants.
- [x] A deadline on `journald_query`, for a `--grep` that never finishes.
- [x] The four committed qemu core dumps removed. See
      [`issues/archive/2026-10-07-committed-qemu-core-dumps.md`](issues/archive/2026-10-07-committed-qemu-core-dumps.md).
- [x] The test files run on aarch64 in CI, under qemu.
- [x] A release fails unless `state.md` and the CHANGELOG name its tag.
- [x] `netns_truncate_veth` carries `#deprecated`, and CONTRIBUTING has the removal protocol.
- [x] [`001-slot-write-order.md`](../architecture/001-slot-write-order.md) no longer says argonaut reads the marker.
- [x] Closed on review: `map_get_miss` (1.7.2 pinned the seed), `defer` (the floor is past 6.6.7), and the `#ifplat`
      migration (`src/` has no arch gates left).

### 1.8.0 — Finish what is local ✅

Work this repo could do and prove alone. All additive; no consumer has to move.

- [x] **The 1.7.x closeout pass.** Run here rather than as a last 1.7.x patch, as 1.7.0 did.
- [x] **BLS `efi`, `uki`, `uki-url` and `extra` keys** on `bootloader_entry`, and `bootloader_entry_boot_kind`, which applies
      systemd-boot's rule, so a validator can tell when `options` is not the command line.
- [x] **The journal's sealed-memfd path.** Checked against a real `systemd-journald` in a private namespace.
- [x] **Clear the rename residue.** The README, `overview.md` and `SECURITY.md` described the 20-module library, so they were
      rewritten rather than renamed.
- [x] **Platform matrix:** [`002-platform-matrix.md`](../architecture/002-platform-matrix.md).
- [x] **Fuzz on aarch64 in CI, and tests and fuzz in `release.yml`.** CI also gained the prose and capability-map gates.
- [x] **`bench-history.sh` pins a core and records a median.**
- [x] **`memeq_16`.** Closed: not real. The source is identical, and 6.6.20 and 6.7.18 both read 28 ns in a pinned A/B.
- [x] **Allocator lock cost.** Closed: not real since cyrius 6.3.17, where the lock is a no-op until a thread starts.
- [x] **The closeout's reviews.** 3 HIGH and 8 MEDIUM, in new and older code, all repaired: audit F-61 to F-77.

### 1.8.1 — The rest of what is local ✅

- [x] **`bootctl list --json`.** `bootloader_list_boot_entries` asks for it first, and takes text only from a bootctl that
      cannot give it. Checked against a real `bootctl` 262, read-only, and over private trees holding addons, extras, a UKI
      named with a space and a line bootctl drops. `is_default` is set from it, the one place that is safe.
- [x] **Review of the above.** 4 HIGH, 3 MEDIUM, 5 LOW, one accepted: [`2026-11-06-audit.md`](../audit/2026-11-06-audit.md). A file's
      boot keys now win over bootctl's, and every UKI in `/EFI/Linux` is accounted for.
- [x] **Fuzz the parsers that had no harness:** `bootloader_parse_loader_conf`, `_update_efi_bootnum`, `_update_efi_bootnext`,
      `_fuse_parse_mounts`, `_fuse_type_ok`.
- [x] **Deadlines on the other tools.** Everything the library runs now has one but `fuse_mount`'s helper, which needs its
      terminal. `agnodrm_run_capture` and `agnodrm_run_checked` stay unbounded, since a caller's own tool may be slow for good
      reason.
- [x] **`bench-history.sh` measures across code layouts.** Over three code-only changes, `strlen_16ch` moved 36% in one layout
      and 0% across five. Rows moving over 5% fall from 4 to 3 of 23, and the worst from 50% to 14%. That is better, not cured,
      so a small move in one row is still not a finding.
- [x] **`JSON` helpers shared.** The third reader was the point to move `update`'s and `journald`'s into `util`.

Nothing local is left in 1.8.x. What comes next needs a decision, or another repo.

### 1.9.x — Give the A/B flow a boot stack

Cross-repo, and the order matters: nothing past the first item can land until it is decided.

- [ ] **Decide what reads the marker.** argonaut, gnoboot or the loader, as an ADR. **L**
- [ ] **`BootOrder`.** Nothing updates it, so a slot stays selected past its one `BootNext` only if the reader sees to it.
      The ADR above answers this. **S**
- [ ] **Emit `agnos.slot=` from the boot entries,** and create the `AGNOS-A` / `AGNOS-B` entries `update_switch_slot`
      looks up by label. This lands in the boot stack, not here. **M**
- [ ] **Prove a reboot.** With the kernel's `boot_id` in the state file, a rollback could finish on a host whose
      `efibootmgr` fails. It refuses there today, which is safe to wait out. A new state-file field: walk the write-order
      table and add rows to `test_powercut`. **M**
- [ ] **Read the slot back after `dd`.** `update_apply` trusts `dd`'s exit status, and a slot that reads wrong after the write
      would still go on to a switch. **M**
- [ ] **Run it for real, once.** Real `bootctl`, `efibootmgr`, a block device, a booted systemd-boot and a real power
      cut. None of them has ever touched this code. **L**

### 1.10.x — Authenticated updates

`update_apply` compares a sha256 against an unsigned manifest, so it catches a corrupt image and not a forged one. Nothing
here is worth doing until 1.9.x can boot the result.

- [ ] **Decide how a signature gets checked,** as an ADR. The stdlib's `sigil` leaf has `ed25519_verify` and `sha256`, down to
      the floor, but it is 1.37 MB against a 60 KB bundle. The other choices are sigil as a tool, or a verifier the caller
      supplies. **L**
- [ ] **Authenticate updates,** with the signature check that decides. **M**
- [ ] **Read a manifest's file list.** `update_check` reads only `version`, so its manifest has no files and `update_apply`
      refuses it, and the hash that gets checked is whatever `update_file_new` was given. **M**
- [ ] **Refuse an older image.** `min_version` is carried and not enforced, so an old image with a valid hash installs. **S**
- [ ] **Network manifest fetch** in `update_check`. Local paths and `file://` only today. `lib/http.cyr` exists now, so what
      blocks this is authenticity: fetching an unsigned manifest is strictly worse than refusing. Never before the signature
      check. **M**
- [ ] **Hash in process.** `update_apply` runs `sha256sum`. The ADR above decides whether the `sigil` leaf replaces it. **S**

### 1.x.x — Waiting on someone else

No date. Each moves up the moment its blocker clears.

- [ ] **Wire a real consumer.** ai-hwaccel, mabda, soorat or nein, on their side. The roadmap above assumes one arrives;
      see the V2.0 decision below if none does.
- [ ] **Bring `consumer-integration.yml` back.** Paused with `if: false` since 2026-06-19. It builds five bundle profiles, four
      of which no longer exist, and names kybernet and libro, neither of which depends on agnodrm. Reconceive it once a real
      consumer exists.
- [ ] **`state.md` release hook** (was V1.4.0). Auto-bump version, sizes and counts. The hook lives in agnosticos tooling.
      Its CI half shipped at 1.7.3.
- [ ] **`#derive(Serialize)` for cstring fields.** Re-verified at 6.7.18: it prints the heap address. `update_state` and
      `drm_verinfo` keep their hand-rolled serializers. See
      [`issues/2026-05-09-cyrius-derive-serialize-cstring.md`](issues/2026-05-09-cyrius-derive-serialize-cstring.md).
- [ ] **macOS and Windows.** Revisit when a consumer needs them.

### V2.0 backlog

Everything that breaks the API, in one list, and none of it ships in 1.x. Each item gets a `Breaking` section in the
CHANGELOG with a migration note, and the snapshot bumps at the 2.0.0 tag. Removals follow the protocol in CONTRIBUTING.

**Decide first:**

- [ ] **Where the deferred group lives.** journald, netns, bootloader, update and fuse are 5 of the 9 modules and about
      three quarters of the code, and nothing calls them. 2.0 is the moment to keep them or move them to whoever turns
      up, as 1.4.4 did for the rest: update and bootloader toward the boot stack, netns toward nein. Everything below
      that touches those modules waits on this answer.

**Remove** (each carries `#deprecated`):

- [ ] **`bootloader_is_dangerous_token`** (audit F-2, 1.5.3) — no callers but the bench suite, and it diverges from the
      validator beside it: a case-insensitive substring search where `bootloader_validate_kernel_cmdline` matches exact
      tokens, so the obvious-looking helper is the looser one. *Migration:* use `bootloader_validate_kernel_cmdline`.
- [ ] **`netns_nft_append`** — a fixed 16 KiB buffer that silently drops what does not fit. The renderer stopped using it
      at 1.7.2 (audit F-43). *Migration:* a `str_builder`.
- [ ] **`netns_truncate_veth`** — two long names with the same start come out the same. *Migration:* none needed; the
      library names veths itself.

**Change the contract:**

- [ ] **Allowlist-based kernel-cmdline validation** (audit F-1, 1.5.3). `bootloader_validate_kernel_cmdline` can only ever
      report "nothing listed matched", so an unlisted interpreter or a novel parameter still passes. An allowlist API
      (permit a declared set, reject the rest) is a breaking change of contract.
- [ ] **`update_get_current_slot` still guesses.** Its callers should be able to tell a guess from an answer.
- [ ] **Inert fields:** `enable_nat`, the netns DNS fields, `min_version`, `max_retries`, `backup_dir`. Nothing reads
      them. Implement them or remove them.
- [ ] **Lists that can be cut.** `bootloader` refuses a list it cannot complete, while the udev, DRM, FUSE and journald lists
      skip what they cannot parse and stop at the caller's capacity. They should say so.
- [ ] **Prefix the last three:** `is_syscall_err`, `result_print_err` and `wrap_syscall`, which collide with sigil's.
- [ ] **Sweep `src/util.cyr`** for consolidation that would be API-breaking, and fold it in the same major.

Obsolete, for the record: `agnosys_checked_syscall` left with `src/syscall.cyr` at 1.4.4, and the unused `label` parameter
of `dmverity_validate_hex` left with dmverity. If the latter still applies, it is on sigil's roadmap.

## P(-1) audit ✅ (done at 1.7.2, 2026-11-05)

- [x] Findings F-15 to F-60 repaired: 4 HIGH, 23 MEDIUM, 19 LOW; see [`docs/audit/2026-11-05-audit.md`](../audit/2026-11-05-audit.md).
- [x] The slot write order written down in [`docs/architecture/001-slot-write-order.md`](../architecture/001-slot-write-order.md).
- [x] `audit.sh` to 14 gates; four new fuzz harnesses; CI checks the toolchain hash and runs least-privilege.

What this left open moved to the [Forward plan](#forward-plan).

## Moving the cyrius pin to 6.7.18 ✅ (done at 1.7.1, 2026-11-05)

- [x] `./lib/` rebuilt clean (40 files, byte-identical to the 6.7.18 snapshot) and `cyrius.lock` regenerated.
- [x] `dist/` regenerated; sidecars unchanged. Floor re-measured: 6.6.7.
- [x] Audit F-2 to F-14 closed; see [`docs/audit/2026-11-05-audit.md`](../audit/2026-11-05-audit.md).

What this left open moved to the [Forward plan](#forward-plan).

## Moving the cyrius pin to 6.7.9 ✅ (done at 1.7.0, 2026-11-05)

- [x] `./lib/` rebuilt clean (40 files, byte-identical to the 6.7.9 snapshot) and `cyrius.lock` regenerated.
- [x] `dist/` regenerated; sidecars unchanged. Floor re-measured across 6.6.5 – 6.7.18: it stays 6.6.6.
- [x] The 6.7.x language rules needed no source change.

## Moving the cyrius pin to 6.6.20 ✅ (done at 1.6.3, 2026-11-05)

- [x] `./lib/` rebuilt clean (40 files, byte-identical to the 6.6.20 snapshot) and `cyrius.lock` added.
- [x] `dist/` regenerated for the 6.6.18 sidecar rule, and the floor re-measured with a sidecar-only
      probe across 6.6.5 – 6.7.18. It rose to 6.6.6; see CHANGELOG `[1.6.3]`.
- [x] Trackers re-run on the new pin: `defer` (fixed 6.6.7) and aarch64 (fixed 6.6.9) closed;
      `#derive(Serialize)` on cstrings stays open.

Left open by the bump:

- [x] **Audit F-1 (MEDIUM): temp files follow a planted symlink.** Fixed at 1.7.0 with `agnodrm_tmp_create`.
- [x] **Remove the four committed qemu core dumps.** Done at 1.7.3. See
      [`issues/archive/2026-10-07-committed-qemu-core-dumps.md`](issues/archive/2026-10-07-committed-qemu-core-dumps.md).
- [x] **Make `map_get_miss` seed-independent.** Done at 1.7.2, which pins the hash seed in `bench_all.bcyr`.
- [x] **`defer` can return once the consumer floor reaches 6.6.7.** The floor passed it at 1.7.2, and CLAUDE.md lets new
      code use either. Nothing needs it, so the existing explicit releases stay.

## Moving the cyrius pin to 6.6.5 ✅ (done at 1.6.1, 2026-09-22 — pin went straight to 6.6.6)

⛔ Before bumping the pin to 6.6.5: cross-reference the two deferral notes
that turn the CI *Lint* step (`.github/workflows/ci.yml:117`) and the lint
stage of `scripts/audit.sh` red. 6.6.5's cyrlint folds case, so a capital
"For now" now counts.

This section lists only what 6.6.5 itself changes.

- [x] ⛔ Put a tracking pointer (CHANGELOG / issue / roadmap / `docs/` path) on
      a line the phrase itself touches, or mark it `#skip-lint`.
  - `src/bootloader.cyr:262` (now :267) — "For now, return 0 entries on failure".
    Pointer added; the deferral had no tracked entry, so **V1.6.x** below
    now records it.
  - `src/update.cyr:458` — "For now, manifest validation checks structural
    integrity only". Same-line `roadmap.md V1.5.x` pointer added.

  See the cyrius CHANGELOG [6.6.5] entry "cyrlint read every rule ONE
  PHYSICAL LINE at a time". Re-checked with 6.6.6's cyrlint over all four
  source globs: these two were the only matches.
- [x] At the bump, re-run `cyrius deps` — the aarch64 syscall peer moved
      SYS_UNLINKAT 35 → 263, so an un-re-vendored peer's sys_unlink would run
      nanosleep. `lib/` rebuilt clean (38 files, byte-identical to the 6.6.6
      snapshot). `sys_unlink` verified under `qemu-aarch64`: it removes the
      file, then returns `-ENOENT`.
- [x] Not in the original list, surfaced at the bump: the cyrius 6.6.4 notes
      ask agnodrm to spell its decimal `O_*` literals. `src/drm.cyr` and
      `src/bootloader.cyr` passed a raw `0x10000` — `O_DIRECTORY` on x86_64,
      **`O_DIRECT` on arm64** — so aarch64 `drm_list_devices` got `EINVAL` on
      `/dev/dri`. Both sites now spell `O_DIRECTORY`, which raises the consumer
      floor to cyrius 6.6.4 (CHANGELOG 1.6.1). And 6.6.5's aarch64 routing of
      raw syscall 44 (x86 `sendto`) makes `journald_send` actually send on
      arm64 — it ran `fstatfs` through 6.6.4.

## Resolved — P1 (AGNOS ABI) ✅ (1.5.0, 2026-07-11)

- **[P1] Raw Linux-shaped `sys_open` ungated on agnos** — `src/drm.cyr`
  (`drm_open`). Filed 2026-07-08, fixed 1.5.0. `sys_open(path, 0x80002, 0)`
  (`O_RDWR | O_CLOEXEC`) used the Linux 3-arg shape, but agnos `sys_open` is
  `(name, namelen, flags)` — so on agnos it passed `namelen = 0x80002` (garbage)
  and `flags = 0`, not an `O_RDWR` open of the DRM node. The call was
  **unconditional**, unlike its already-gated siblings `drm_get_driver_version` /
  `drm_get_capability`. Same conversion family as the cyrius `file_open` / sakshi
  `_sk_open` `O_RDWR` bug. **Resolution:** gated `drm_open` "not supported" on
  agnos (the gate-not-reimplement path), matching the rest of the DRM surface —
  agnos display routes through bhumi's sovereign scanout, so there is no DRM node
  to open.
- **Two stragglers found in the same 1.5.0 full-module audit** (identical class,
  missed by the 1.4.6 agnos-readiness sweep): `update_load_state`
  (`sys_open(path, 0, 0)` on the `/var/lib/agnos` A/B state file, reachable via
  `update_mark_boot_successful`) and `update_check` (`sys_open(path, 0, 0)` on
  the local update-manifest). Both gated the same way; the delegating callers
  propagate `not_supported` through the now-gated primitives. The other seven
  modules (bootloader / fuse / netns / journald / udev / error / util) audited
  clean. `--agnos` + Linux builds green. See CHANGELOG `[1.5.0]`.

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
- [x] Local audit runner — `scripts/audit.sh` (12 gates as of 1.5.2, mirrors CI)

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

#### V1.1.2 — `ct_eq_bytes` deferral (issue filed) ✅ SHIPPED 2026-05-06

The slot's premise — `ct_eq` as a cyrius compiler builtin or
`lib/ct.cyr` helper — turned out incomplete on cyrius 5.9.14:
`ct_eq` was not a builtin; `lib/ct.cyr` shipped only `ct_select`;
`secret var` rejected scalar declarations (didn't fit
cstring-pointer pin storage). The existing
`src/certpin.cyr:120 fn certpin_ct_streq` was correct as-is
(canonical XOR-accumulate, no data-dependent branches).

Filed [`docs/development/issues/archive/2026-05-06-cyrius-ct-eq-bytes-stdlib.md`](../issues/archive/2026-05-06-cyrius-ct-eq-bytes-stdlib.md)
proposing `ct_eq_bytes(a, b, n)` for `lib/ct.cyr`. Slot shipped
as a deferral — issue + verification + roadmap defer note.

**Rationale:** the compiler-backed primitive is the canonical path post-5.8.x (sigil's PQC code uses it). Our hand-rolled version works but isn't the supported pattern.

#### V1.1.3 — `ct_eq_bytes` reopen ✅ SHIPPED 2026-05-06

cyrius 5.9.18 added `ct_eq_bytes(a, b, n)` to `lib/ct.cyr`
(canonical XOR-accumulate; doc-comment credits the agnosys
filing). agnosys-side migration:

- [x] `cyrius.cyml [deps].stdlib` += `"ct"` (auto-prepend).
- [x] `src/certpin.cyr fn certpin_ct_streq` body shrunk from a
  16-line hand-roll to a 5-line cstring wrapper that delegates
  the byte loop into `ct_eq_bytes(a, b, alen)`. Length-mismatch
  early-return preserved (pin length is non-secret in agnosys —
  44-char base64 SHA-256, fixed by spec).
- [x] Bench parity verified: `ct_streq_equal` 125→129ns,
  `ct_streq_diff` 135→140ns (within run-to-run noise).

`secret var` annotation deferred indefinitely — pin storage in
certpin flows through cstring pointers across struct boundaries,
which doesn't fit cyrius's array-only `secret var` contract.
Revisit if/when `secret var` gains a pointer-form or a separate
`secret_str` annotation.

#### V1.1.4 — `ct_eq_bytes_lens` one-liner + `sys_stat` x86 fix ✅ SHIPPED 2026-05-06

cyrius 5.9.20 closed two upstream gaps in one bump:

- [x] `lib/ct.cyr` added `ct_eq_bytes_lens(a, a_len, b, b_len)`
  (dual-length variant; sigil-paired consolidation). agnosys's
  `certpin_ct_streq` body further shrunk to a one-liner full
  delegation: `return ct_eq_bytes_lens(a, strlen(a), b, strlen(b));`.
- [x] `lib/syscalls_x86_64_linux.cyr:309` added `fn sys_stat`
  (peer with the existing aarch64 entry at line 346) — closed
  the long-open
  [`docs/development/issues/archive/2026-05-01-sys-stat-x86-portability.md`](../issues/archive/2026-05-01-sys-stat-x86-portability.md)
  filed by sigil 3.0 against agnosys 1.0.4. No agnosys-side
  shim needed.

#### V1.1.5 — Exhaustive `match` coverage adoption ✅ SHIPPED 2026-05-06

agnosys's first `match` block — `src/error.cyr fn syserr_print`
converted from a 7-elif + else chain to a `match kind { ... }`
over all 8 `SysErrorKind` variants, no `_ =>` opt-out. Future
`SysErrorKind` additions trigger a build-time warning until
handled.

- [x] `scripts/audit.sh` gate 4 now greps the build log for
  `non-exhaustive` and fails the gate. Verified by regression
  test (deliberately removed an arm; gate fired with the
  expected message).
- [x] Other 14 enum-to-string fns
  (`update_phase_str`, `pam_service_name`, `tpm_bank_str`, etc.)
  kept as if/elif chains — their catch-all defaults are correct
  for wire-format / debug serializers where missing-variant
  should degrade gracefully rather than fall through silently.

#### V1.1.6 — Match-coverage corrigendum + cyrius 5.9.25 pin ✅ SHIPPED 2026-05-07

The match-coverage check on cyrius 5.9.20–5.9.21 was
fn-name-dependent (hash-bucket dispatch in coverage bookkeeping;
a roughly 50/50 mix of warning-fires vs warning-skips across fn
names). agnosys 1.1.5's CHANGELOG attributed the inconsistency
to DCE-gating; that diagnosis was wrong. Filed
[`docs/development/issues/archive/2026-05-06-cyrius-match-coverage-fn-name-dependent.md`](../issues/archive/2026-05-06-cyrius-match-coverage-fn-name-dependent.md);
fix landed in cyrius 5.9.25.

- [x] cyrius pin 5.9.20 → 5.9.25.
- [x] CHANGELOG corrigendum to 1.1.5: real cause was hash-table
  indexing, not DCE-gating. The 1.1.5 audit gate is still correct
  as a CI hook; on 5.9.25 its coverage is now reliable across
  every fn name.
- [x] Side-observation also fixed: `cyrius --version` no longer
  emits the trailing `\xb3` byte.

(`syserr_print` happened to be in a "lucky" hash bucket on
5.9.20–5.9.21, so the V1.1.5 gate was correct in practice for
agnosys's one match block — just hash-bucket-dependent for any
future second match. 5.9.25 makes the gate reliable for new
matches landing in V1.1.7+.)

#### V1.1.7 — Tagged-union `Result` adoption ✅ SHIPPED 2026-05-07 (verification slot)

The slot anticipated migrating agnosys's `Result`/`Option`
construction from `lib/tagged.cyr`'s hand-rolled `tagged_new`/
`tag`/`is_tag` primitives to cyrius's first-class
`enum Result<T, E> { Ok(v); Err(e); }` form. Verification
showed the migration was already complete via stdlib evolution:

- [x] cyrius v5.8.23 migrated `lib/tagged.cyr`'s `Option` to a
  first-class sum type. v5.8.28 carved `Result<T, E>` out into
  `lib/result.cyr` as a typed first-class sum type
  (transitively included by lib/tagged.cyr).
- [x] agnosys's call sites use only the high-level API (`Ok(...)`,
  `Err(...)`, `is_ok(res)`, `is_err_result(res)`, `payload(res)`).
  Zero direct `tagged_new(...)`, `tag(...)`, or `is_tag(...)`
  calls in src/* (verified across all 24 source files).
- [x] When agnosys writes `return Ok(value);`, cyrius resolves
  `Ok` to the derive-emitted constructor in lib/result.cyr —
  same heap layout as the pre-v5.8.21 hand-rolled
  `tagged_new(0, value)`, transparently.

Pattern-payload destructuring (`match res { Ok(v) => use(v) }`)
is NOT yet shipped in cyrius (per vidya `tagged_unions_v58x`:
"That's a future slot"). When it lands, agnosys's
`if (is_err_result(res) == 1) { return res; } var v = payload(res);`
chains become candidates for the cleaner `match` form. Until
then the if/payload chain stays as the canonical idiom.

**Rationale:** the lib/tagged.cyr API still works but is the pre-5.8.21 hand-rolled pattern. First-class sum types compile to byte-identical layout for arity-1, and exhaustive-match (V1.1.5) becomes load-bearing once Result is a real enum.

#### V1.1.8 — Multi-width struct fields for kernel binary protocols ✅ SHIPPED 2026-05-07

Four kernel-ABI structs migrated to typed `struct` decls +
pointer-to-struct dot syntax:

- [x] `sockaddr_nl` (12 B; u16/u16/u32/u32) in audit.cyr
- [x] `nlmsghdr` (16 B; u32/u16/u16/u32/u32) in audit.cyr —
  both write side (`audit_build_nlmsg`) and read side
  (`audit_recv_raw`'s parser)
- [x] `audit_kstatus` (32 B; 8× u32) in audit.cyr — read side
  in `audit_get_status` and write side in `audit_set_enabled`
- [x] `bpf_insn` (8 B; u16/u8/u8/u32) in security.cyr

14 explicit width-store calls eliminated; 3 width-load reads
also converted. cyrius's width-correct codegen emits the right
`store16`/`store32`/`load16`/`load32` instructions automatically;
the kernel-correct tight-packed byte layout is enforced by the
typed field declarations.

Stack-local kernel-ABI writes (LandlockRulesetAttr,
LandlockPathBeneathAttr, sock_fprog at security.cyr lines 106
and 195) **deferred** — per vidya `multi_width_types`, stack
locals use 8-byte slots regardless of declared width, so
`var attr: T;` doesn't preserve kernel ABI on the stack. The
existing `var buf[N]; store32(&buf+N, ...);` pattern stays
correct for those sites.

**Discovery worth recording (in CHANGELOG `[1.1.8]`):**
1. `#derive(accessors)` lays typed fields out at i64 slots, NOT
   FIELDOFF tight-packed offsets. Suitable for internal-layout
   structs; NOT for kernel-ABI structs.
2. Pointer-to-struct dot syntax (`var s: T = ptr; s.f = v;`)
   honors width-aware tight-packed offsets — verified by
   byte-dumping. This is V1.1.8's migration vehicle.

**Rationale:** cyrius 5.8.x ships width-correct codegen — `var x: i32 = …` does the right `mov dword [addr], eax`. Today's hand-rolled mixed-width store/load pattern is correct but loses the type system's ability to catch a `store64` where a `store32` was meant.

#### V1.1.9 — V1.1.8 revert (aarch64 sub-8-byte struct field load gap) ✅ SHIPPED 2026-05-07

V1.1.8 shipped clean on x86_64 but broke aarch64 cross-build
(`error:1610: sub-8-byte struct field load is x86-only for
v5.6.0; aarch64 + cx pending`). Reverted source-side back to
the explicit `store{8,16,32}` pattern. Filed
[`docs/development/issues/archive/2026-05-07-cyrius-aarch64-sub-8-byte-struct-load.md`](../issues/archive/2026-05-07-cyrius-aarch64-sub-8-byte-struct-load.md)
and added a permanent `cyrius build --aarch64` gate to
`scripts/audit.sh` step 4 so the regression class is caught
in local audit, not just CI.

#### V1.1.10 — V1.1.8 reopen (cyrius 5.9.27 pin) ✅ SHIPPED 2026-05-07

cyrius 5.9.27 implemented the aarch64 backend's `EFLLOAD_W`
codegen for sub-32-bit struct field loads. agnosys reopened
V1.1.8 by restoring the typed kernel-ABI struct decls + dot
syntax and bumping the cyrius pin `5.9.25` → `5.9.27`. Both
arches clean; aarch64 cross-build gate confirms.

#### V1.1.11 — Slice migration for syscall + parser buffers ✅ SHIPPED 2026-05-07

Survey of the 35 `var buf[N]` sites in src/* showed most aren't
real slice candidates: ~10 tiny fmt buffers (no indexed access),
~6 kernel-ABI stack structs (different pattern), ~7 one-shot
syscall arg buffers (no indexed access), ~12 large parser
buffers using `memeq`/`memcpy` with explicit `pos < outlen`
walks (length-bounded by construction; slice subscript would
re-validate already-validated bounds).

- [x] One representative site migrated as the canonical pattern:
  `src/ima.cyr fn ima_get_status`'s newline-counting loop over
  the 4 KB rbuf converted from `load8(&rbuf + ri)` with explicit
  `ri < n` to `slice_set(&s, &rbuf, n)` + `s[ri]` with
  `ri < s.len`. Bounds-checked indexing replaces the manual
  bound and protects against future drift.
- [x] `cyrius.cyml [deps].stdlib += "slice"`; explicit
  `include "lib/slice.cyr"` added to entry-point sources and
  to `src/ima.cyr` (required for `cyrius check` standalone-mode
  syntax resolution of slice subscript helpers).
- [x] Both arches clean (cyrius 5.9.27 has slice support on
  aarch64).

Future scalar-subscript parser loops should adopt the slice
form from the start; the existing `memeq`/`memcpy`-based parsers
stay as-is since their bounds are already explicit.

**Rationale:** bounds-checked indexing on the agnosys parsers (audit netlink, fuse mount entries, EFI var bytes, IMA measurement records) closes the off-by-one class without a runtime cost we can't already amortize.

#### V1.1.12 — `#derive(Serialize)` ✅ SHIPPED 2026-05-09

The slot's premise — `#derive(Serialize)` auto-generates a
working `<struct>_to_json(ptr, sb)` per vidya
`derive_str_fields` — initially deferred 2026-05-07 due to
an apparent SIGILL on aarch64. Root cause discovered
2026-05-08 (cyrius team's `pwd && ls -la lib/` diagnostic):
agnosys's vendored `./lib/fnptr.cyr` and `./lib/json.cyr`
stubs (5.7.6-era) were shadowing v5.10.x stdlib's full
versions; PP_DERIVE Serialize codegen referenced helpers
absent from the stubs. cyrius's PP_DERIVE was correct on
both arches the entire time.

agnosys 1.1.12 ships:

- **2 derived serializers** via stacked `#derive`
  (cyrius 5.10.14+): `audit_status_to_json`,
  `ima_status_to_json` — both all-numeric structs, both
  arches verified on real Pi.
- **5 hand-rolled `_to_json` shims** for cstring-bearing
  diagnostic structs (`mac_profile`, `dmverity_status`,
  `update_state`, `certpin_info`, `drm_verinfo`). Pattern:
  per-module `_<mod>_emit_cstr_or_null` helper handles
  null-or-quoted cstring emission, mixed with
  `str_builder_add_int` for numeric fields.

Hand-rolls unwind cleanly when cyrius adds cstring
`#derive(Serialize)` support — the future migration is
mechanical (delete the shim + helper, add
`#derive(Serialize)` directive line, regenerate snapshot).

Three issues filed and resolved during the arc:
- `archive/2026-05-07-cyrius-derive-serialize-incomplete`
  — agnosys-side `./lib/` shadow, not cyrius.
- `archive/2026-05-08-cyrius-derive-multi-stacking` —
  fixed cyrius 5.10.14.
- `archive/2026-05-09-cyrius-api-surface-putc-brace-desync`
  — fixed cyrius 5.10.16.

cyrius pin arc: 5.9.27 → 5.10.16. Min consumer cyrius is
now 5.10.16 (multi-derive + scanner fixes baked in).

**Rationale:** consumer ergonomics. Today every consumer that wants to log agnosys state writes its own formatter. `#derive(Serialize)` ships the canonical one with the module.

### V1.2 — Ecosystem

Theme: consumer-facing wiring and platform discipline. Independent of the 1.1.x
language-feature surface — these are durable infrastructure improvements.

#### V1.2.0 — Multi-profile `cyrius distlib` ✅ SHIPPED 2026-05-09

- [x] Add `[lib.security]` (security + mac + audit + pam) → `dist/agnosys-security.cyr` (76 KB)
- [x] Add `[lib.storage]` (luks + dmverity + fuse) → `dist/agnosys-storage.cyr` (49 KB)
- [x] Add `[lib.trust]` (tpm + ima + secureboot + certpin) → `dist/agnosys-trust.cyr` (70 KB)
- [x] Add `[lib.system]` (journald + bootloader + udev + drm + netns + update) → `dist/agnosys-system.cyr` (111 KB)
- [x] Add `[lib.core]` (error + syscall + logging + arch peers) → `dist/agnosys-core.cyr` (23 KB). The "kernel-safe subset for AGNOS-kernel direct consumption (no alloc, no syscall, pure enums/types)" is a future refinement on top of this V1.2.0 deliverable — current `[lib.core]` ships the listed modules as-is; trimming alloc/syscall paths to a pure-enum form is a follow-up slot if/when AGNOS-kernel direct consumption lands.
- [x] CI dist-staleness gate extended to all five profiles + the full bundle (6 total).
- [x] Release archive ships every profile bundle alongside the full `dist/agnosys.cyr`.

**Rationale:** kavach pulls 324 KB today for what it actually uses (~50 KB security surface). Profile bundles cut consumer binary size and clarify the agnosys → consumer wiring. Headline 1.2 cycle because it changes the consumer-facing distribution shape — gets its own minor cycle.

#### V1.2.1 — `#ifplat` cosmetic migration (was 8.3)

Closed on review at 1.7.3. The arch-gated `src/syscall_*_linux.cyr` files left in the 1.4.4 decomposition, and `src/` has
no `CYRIUS_ARCH_*` or `#ifplat` gate left, so there is nothing to migrate. The modules this slot called Linux-only moved
too. The platform matrix and the macOS / Windows watch moved to the [Forward plan](#forward-plan).

#### V1.2.2 — Capability map per public fn ✅ SHIPPED 2026-05-09 (in 1.2.1)

- [x] `docs/development/capability-map.md` — auto-generated, per-module granularity (638 lines). Per-fn rows would need a real cyrius AST walker for transitive call resolution — deferred to a future slot if downstream demand surfaces.
- [x] `scripts/gen-capability-map.sh` — parses each module's source, extracts direct syscalls + sys_* wrappers + exec paths + filesystem paths. `--check` mode wired into audit.sh as gate 3/11 (fails CI on drift).
- [x] Per-profile rollup added: `dist/agnosys-<profile>.cyr` bundles map cleanly to module sets, so kavach (security profile) etc. derive their seccomp/Landlock allowlist by aggregating the modules in their profile.

**Rationale:** `docs/SECURITY-NOTES.md` covers per-module concerns at prose level. A machine-checkable surface gives kavach/daimon a programmatic basis for seccomp policy generation.

#### V1.2.3 — Consumer integration CI (was 8.4)

- [x] Nightly GitHub Actions job per consumer: clone, vendor agnosys main, build, run consumer's audit. Workflow at [`.github/workflows/consumer-integration.yml`](../../.github/workflows/consumer-integration.yml) (separate file, NOT part of the primary build/test pipeline).
- [x] Failures open an issue tagged `consumer-break` (linked to consumer + agnosys commit). Dedup by title prefix — re-fires comment on the existing issue rather than duplicating.
- [x] Initial matrix: kavach + sigil (highest module surface per the spec). 13 consumers in scope per [`state.md`](state.md); expand the matrix once the initial pair runs cleanly for a few cycles.

**Rationale:** v1.0 deferred this to "tracked on consumer crates" — i.e., manual. Automated drift detection means an agnosys patch that breaks sigil's TPM caller fails before that consumer notices. Notification channel is GitHub Issues (the `consumer-break`-tagged issue the workflow auto-files); no Slack / Discord wiring — repo Issues is the canonical inbox.

**Mechanics:** Nightly @ 06:00 UTC + workflow_dispatch. Workflow reads agnosys's cyrius pin from `cyrius.cyml`, force-sets each consumer's pin to match (tests "consumer + agnosys-main + a synced cyrius toolchain"), copies all 6 dist bundles into the consumer's `lib/`, runs the consumer's declared audit command. Doesn't share concurrency with `ci.yml`.

#### V1.2.4 — `#deprecated` adoption channel

- [x] Adopt cyrius's `#deprecated("reason / migration")` attribute for any post-1.0 API drift. Since 1.7.3 every fn due for removal carries it.
- [x] Document the soft-removal protocol in CONTRIBUTING.md: deprecate → one-minor bake → remove with `Breaking` in CHANGELOG. Done at 1.7.3.

**Rationale:** today every public-fn rename is either a hard break (snapshot bump) or a frozen API call. `#deprecated` adds a third channel — warning at every call site, snapshot still passes, consumers see the warning in their CI before the actual removal.

### V1.3+ — Cross-repo / meta-tooling

#### V1.3.0 — ✅ SHIPPED 2026-06-01 — correctness + refactor/optimization minor

Re-scoped from the original "state.md post-hook" plan (that cross-repo concern
moved to V1.4.0 below). 1.3.0 shipped: cyrius pin 6.0.14 → 6.0.24; 4 buffer/exec
defects fixed (F-11 HIGH heap overflow, F-12/F-13 MEDIUM, F-14 LOW netns exec);
`src/util.cyr` cross-module dedup (+5 `agnosys_*`, non-breaking); benchmarked
hot-path wins (`starts_with` −68%/−77%, `mac_default_profile` −26%); Tier-3
hygiene. See CHANGELOG `[1.3.0]` and `docs/audit/2026-06-01-audit.md`.

#### V1.3.1 — ✅ SHIPPED 2026-06-01 — `src/util.cyr` consolidation closeout

- [x] Folded the dm-name allowlist (`dmverity_is_name_char`, `luks_is_name_char`) into a shared `agnosys_is_name_char` — both kept as thin wrappers (done opportunistically per the "or alongside other util.cyr work" path; 2 instances).
- [x] `agnosys_read_fd_to_str` replaces 3 byte-identical pam drain loops (`pam_read_service_config`, `pam_list_users`, `pam_get_user_info`) — a clean 3-instance dedup deferred from the 1.3.0 audit. The shared helper allocs `cap + 1`, closing a **latent 1-byte overflow** the per-module copies carried (F-11 class). Regression test `readfd_cap`.

+2 public fns (additive, non-breaking; 735 → 737). See CHANGELOG `[1.3.1]`.

#### V1.4.0 — `state.md` release post-hook (was 8.6)

- [x] state.md created at 1.0.1
- Release post-hook auto-bumps state.md (version, binary size, test counts): moved to the [Forward plan](#forward-plan).
- [x] CI gate that fails the release if state.md `Last refresh` doesn't match the tag. Done at 1.7.3, in `release.yml`.

**Rationale:** template's "release post-hook bumps state.md. If the hook doesn't, fix the hook — don't hand-maintain state." Lands when agnosticos meta-tooling supports it (cross-repo concern — hook lives in agnosticos toolchain, not this repo).

#### V1.4.x — allocator lock-cost elimination (opened 2026-06-10 at 1.4.1)

The cyrius v6.0.64 stdlib allocator wraps every `alloc()` in a process-wide CAS
spinlock + ACQUIRE/RELEASE fences (a real CLONE_VM/threads correctness fix). For
single-threaded agnosys this is pure overhead — 1.4.1 measured `ok_create` +321%,
`from_errno` +210%, `mac_default_profile` +74% vs 1.3.2 (alloc-bound paths only;
zero-alloc `syserr_pack` hot path unchanged). Confined to cold/diagnostic heap
routes today, but worth removing. Options, in preference order:

Closed at 1.8.0. Since cyrius 6.3.17, `_alloc_lock_acquire` is a no-op until a thread starts, so the cost measured here had
already gone. Results are register pairs and `from_errno` packs, so the two worst rows no longer allocate at all: `ok_create`
reads 2 ns and `from_errno_eperm` 9 ns, against 59 and 65 ns at 1.4.1.

#### V1.5.x — `update` module deferred capabilities (documented 2026-08-24 at 1.5.3)

Two capabilities in `src/update.cyr` are deliberately unimplemented. Both were carried as bare in-code notes until the
1.5.3 P(-1) sweep, and are recorded here so the code can cite a tracked entry (cyrlint requires every deferral to
cross-reference a CHANGELOG / roadmap / issue entry). Both have moved to the [Forward plan](#forward-plan), under 1.10.x.

- **Manifest digest verification.** Partly done at 1.7.2: `update_apply` checks the image against the manifest's sha256,
  through `sha256sum`. `update_verify_manifest` still checks structure only, and neither is an authenticity check.
- **Network manifest fetch** (`update_check`). Local paths and `file://` URLs only. The note here used to say this waited
  on an HTTP client, and the stdlib has `lib/http.cyr` now. It waits on authenticity instead.

#### V1.6.x — `bootloader` deferred capability (documented 2026-09-22 at 1.6.1)

One more bare in-code deferral, surfaced when cyrius 6.6.5's cyrlint began
folding case — a capital "For now" had never matched before. Recorded here so
the code can cite a tracked entry, the same way V1.5.x records `update`'s.

- [x] **Loader-entries fallback** (`bootloader_list_boot_entries`) — **done at
  1.6.2.** Entries used to come from `/usr/bin/bootctl list` only; when bootctl
  was missing, failed, or printed nothing, the function returned `Ok(0)`, so a
  failed `bootctl` read as a successful "no entries". Now:
  - The fallback reads Boot Loader Specification Type #1 entries from the first
    readable directory among `/boot/loader/entries`, `/efi/loader/entries` and
    `/boot/efi/loader/entries`, through the new public
    `bootloader_list_loader_entries(dir, …)` and stdlib helpers only.
  - When bootctl yields nothing and no such directory is readable, it returns
    `Err(not_supported)`.
  - The same work found and fixed the bootctl path's own bug: it opened a new entry on
    `id:`, so every entry got the next entry's title.
  - Both paths now report the same id shape (`<name>.conf`).
  - The agnos build still returns `Ok(0)` by design (gnoboot, no systemd-boot
    entries). See CHANGELOG `[1.6.2]`.

#### V1.6.x — harness follow-ups from the 6.6.6 bump (opened 2026-09-22 at 1.6.1)

Found while explaining the 1.6.1 bench delta and reading the 6.6.6 build logs.
None affects the library; each makes a gate or a measurement more trustworthy.

- [x] **Move `bench_all.bcyr` onto `bench_batch_start` / `bench_batch_stop`.** — done at 1.6.2; rows report real min/max again.
  Its `batch_record` writes the stdlib bench struct at fixed offsets. Since
  6.6.5 that struct is 64 B and its min/max fields hold picoseconds, so every
  row's `min=` / `max=` repeats the mean. The recorded average is unaffected.
- [x] **Make the string benches alignment-independent.** — done at 1.6.2 (no pin change that release); every bench input is an 8-aligned copy. `strlen_16ch` reads
  11 or 21 ns depending only on where the linker lands `"hello_world_test"`,
  because stdlib `strlen` walks bytes to 8-alignment first. Copy bench inputs
  into 8-aligned buffers so a toolchain bump stops moving these rows by up to
  2×. It is best landed in a release with no pin change, so the step in the
  history is attributable.
- [x] **`fuzz/fuse_parse.fcyr` omits `src/util.cyr`.** — done at 1.6.2, and every test / fuzz / bench build log is now gated like the target builds. Its build prints
  `warning: undefined function` for `agnodrm_run_checked` /
  `agnodrm_cstr_starts_with` and three dropped-tag warnings that follow from
  them. The same five warnings appear on 6.6.2, and the library build is clean.
  Neither the CI fuzz step nor `audit.sh` gate 11 reads fuzz build logs; the
  x86_64 / aarch64 / agnos gates' `undefined function` promotion does not
  extend to them.

#### Toolchain rule verification — `break` in `var`-declaring while loops (opened 2026-08-24 at 1.5.3)

CLAUDE.md § Rules forbids `break` inside a `while` loop that declares `var`s
("use flag + `continue`"). The 1.5.3 P(-1) sweep ran a brace-matching analyser
over all four source globs and found **10 such loops** (4 in `bootloader`, 3 in
`fuse`, 2 in `journald`, 1 in `udev` — all of them external-input parsers).

Tested empirically against cyrius 6.5.35: the forbidden shape and the
prescribed flag+continue shape produce **identical results**. The rule did not
reproduce.

- [x] **Resolved 2026-08-24 — rule retired.** Re-tested far past the original
  single case: a 10-shape harness (simple break, the nested inner-loop shape,
  vars declared *after* the break, loop vars read after a break exit, two
  sequential breaking loops) gives identical results in both forms on
  **x86_64 and aarch64** (the latter under `qemu-aarch64` — the arch that
  carried the historical sub-8-byte struct-load codegen bug). A `defer`
  registered before the loop still runs on the break path, which was the
  plausible original motive. The real code was checked too: the full
  111-assertion suite and all 3 fuzz harnesses pass under `qemu-aarch64`,
  exercising all 10 sites. Origin research found the rule entered as general
  house guidance in the 1.0.1 CLAUDE.md restructure (`562a014`) with no
  reproducer recorded in any audit, issue, or ADR.

  The rule is removed from CLAUDE.md § Rules; the Cyrius Conventions section
  records the verified behaviour in its place so it is not re-added from
  folklore. The 10 sites stay as they are. See CHANGELOG `[Unreleased]`.

### V2.0 — Breaking API cleanup

Moved to the [V2.0 backlog](#v20-backlog) in the Forward plan.

## V1.0+ Verification

- [x] **1.1.0** shipped 2026-05-06 — V1.1.0 (`#derive(accessors)`) complete; closeout patch (1.0.13) clean; 16 of 16 struct-bearing modules migrated. See CHANGELOG `[1.1.0]` for the consumer banner and `[1.0.13]` for the cumulative baseline.
- [x] Subsequent V1.1.x slots shipped as patches against 1.1, through V1.1.12.
- [x] **1.2.0** shipped 2026-05-09 with V1.2.0 (multi-profile distlib).
- [x] V1.2.x slots shipped or closed; see each slot above.
- [x] **1.3.0** shipped 2026-06-01 — correctness + refactor/optimization minor (re-scoped from the post-hook plan; pin 6.0.24, 4 buffer/exec fixes, `src/util.cyr` dedup, bench wins). See CHANGELOG `[1.3.0]`.
- [x] **1.3.1** shipped 2026-06-01 — `src/util.cyr` consolidation closeout (name_char + the shared pam read-fd helper, closing a latent overflow). Non-breaking; see CHANGELOG `[1.3.1]`.
- [x] V1.4.0's hook moved to the [Forward plan](#forward-plan).

## Consumer Map (durable)

Volatile per-consumer status lives in [`state.md`](state.md). This is who each module is meant for. Nothing is wired yet:
see the [Forward plan](#forward-plan). The table before 1.7.3 listed the modules that left at 1.4.4, and their consumers
are in the decomposition plan.

| Intended consumer | Modules |
|----------|---------------|
| ai-hwaccel, mabda | udev, drm |
| yukti | udev |
| soorat | drm |
| nein | netns |
| argonaut | journald, bootloader |
| ark | fuse, update |

## Moving the cyrius pin to 6.6.6 ✅ (done at 1.6.1, 2026-09-22)

Pin at the time of this pre-check: `cyrius = "6.6.2"`. Nothing needed to change first.

agnodrm truncates in three places, all with the flag word written as a raw hex literal:
`src/netns.cyr:603`, `src/update.cyr:72` and `src/update.cyr:136`, each
`sys_open(path, 0x241, 0x1A4)` — `O_WRONLY|O_CREAT|O_TRUNC`, mode 0644. Before 6.6.6 a PE
build's `O_TRUNC` did not truncate, leaving the old tail of a rewritten file in place; the
`update.cyr` pair writes staged update files and `netns.cyr` writes a network-namespace
config, so a short rewrite would have produced a trailing-garbage config. **agnodrm is not
exposed**: no PE target (`CYRIUS_TARGET_AGNOS` is the only `CYRIUS_TARGET_*` in `src/`), CI is
`ubuntu-latest` only, and `release.yml` ships x86_64 + aarch64 with no `windows-*` job. The
repo is Linux/AGNOS-eccentric by design — bootloader, update, netns, fuse, journald — so this
stays a note rather than a fix.

Everything else checked and empty:

- No `O_APPEND` anywhere outside the vendored `lib/`.
- None of item 3's new compile errors have sites: no `async fn`, no `operator` fn, no
  `ret2`/`rethi`, no SIMD intrinsics, and no struct- or vector-typed parameter or `var`
  declaration in `src/`. The 15 structs (`fuse_mount`, `drm_verinfo`, `netns_config`,
  `netns_handle`, `netns_fw_rule`, `netns_fw_policy`, `journald_entry`, `journald_filter`,
  `udev_devinfo`, `update_state`, `update_config`, `update_manifest`, `update_file`,
  `bootloader_entry`, `bootloader_config`) are accessor-style over heap offsets, never passed
  or assigned by value — so item 5's by-value-struct-param deep copy is a no-op here too.
- No top-level bare `{` blocks (item 4), no duplicated global declarations (item 6), no
  `regression_*` call sites (item 8), no own `vec_*` function colliding with the 14 names
  `lib/vec.cyr` exports (item 9), no `file_exists` / `file_read_all` call sites at all.
- Arity and `: cstring` argument scans over the repo's own sources: clean, no mismatches.

After bumping, verify the full `.tcyr` suite per-file and one `agnodrm update` staging cycle —
write a manifest, rewrite it shorter, and confirm the file ends where it should.

**Done at 1.6.1.** The `.tcyr` suite passes per file with DCE, on x86_64 and under
`qemu-aarch64`. The staging cycle is a 32-assertion scratch harness run on both arches:

- `update_atomic_write` and `update_atomic_copy` each rewrite a file shorter over a planted,
  longer, stale `.tmp`; the file ends at the new length.
- An `update_save_state` cycle shrinks the state file, which still ends at `}\n`.
- Mutation check: with `O_TRUNC` dropped, the harness fails exactly the two length checks.

The PE fix was Windows-only, so on Linux this confirms behaviour rather than a fix.

Two things this pre-check did not cover, both found in a full read of the 6.6.6 notes:

- Block-scoped `var`s now apply to any top-level `if` / `while` / `for` body, not just bare `{`
  blocks. The five in the fuzz harnesses' top-level loops are never read after their block, so
  there is nothing to change.
- `lib/process.cyr` now gives every child `PR_SET_PDEATHSIG(SIGKILL)`, and adds an opt-in
  `proc_set_timeout_ms`. That is a behaviour change for agnodrm's `dd` / `bootctl` / `udevadm` /
  `ip` helpers, recorded in CHANGELOG 1.6.1.
