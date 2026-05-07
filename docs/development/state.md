# Agnosys — Live State

> Volatile snapshot. Refreshed every release. Durable rules live in [`CLAUDE.md`](../../CLAUDE.md). Historical release narrative is in [`CHANGELOG.md`](../../CHANGELOG.md). Future work is in [`roadmap.md`](roadmap.md).

**Last refresh:** 2026-05-06 (1.1.0 tag)

## Version & Toolchain

| Item | Value |
|---|---|
| `VERSION` | **1.1.0** |
| `cyrius.cyml [package].cyrius` | **5.9.14** |
| Min Cyrius (consumer) | 5.9.14 |
| Last cyrius bump | 5.9.7 → 5.9.14 (1.0.12) |

## Build Metrics

| Metric | Value | Notes |
|---|---|---|
| Binary size (DCE) | **85,592 B** | unchanged across V1.1 (pure refactor; no behavior change) |
| `dist/agnosys.cyr` size | ~330 KB / 9,886 lines | bundled distlib (full library); -68 lines vs 1.0.5 from removing hand-written accessor fns |
| Fn-table utilization | 289 / 4,096 (7%) | from `cyrius capacity --check` |
| Var-table | 302 / 8,192 | |
| Fixup-table | 724 / 262,144 | |
| String-data | 1,376 / 262,144 | |
| Code-size | 67,552 / 1,048,576 | |
| Compile time | ~460 ms | recorded at 1.0.0 closeout |

## Module Count

**20 modules implemented (100%)** — surface frozen at 1.0.

| Module | Public fns | Description |
|---|---|---|
| error | (snapshot) | SysError types, errno mapping, Result helpers |
| syscall | (snapshot) | `agnosys_*` getpid/uid/hostname/sysinfo wrappers |
| logging | (snapshot) | `log_*` level control via `AGNOSYS_LOG` |
| security | (snapshot) | Landlock, seccomp BPF, namespace creation |
| mac | (snapshot) | SELinux/AppArmor detection and context management |
| audit | (snapshot) | Kernel audit netlink socket, rule management |
| pam | (snapshot) | PAM service inspection, passwd/who parsing |
| journald | (snapshot) | Systemd journal send/query |
| luks | (snapshot) | LUKS2 encrypted volume management |
| dmverity | (snapshot) | dm-verity integrity verification |
| ima | (snapshot) | IMA measurements, policy rules |
| tpm | (snapshot) | TPM2 device, PCR reading, seal/unseal |
| certpin | (snapshot) | Certificate pin validation, SPKI computation |
| secureboot | (snapshot) | Secure Boot EFI variable reading |
| udev | (snapshot) | Device enumeration via udevadm |
| drm | (snapshot) | DRM device enumeration, ioctl version/caps |
| netns | (snapshot) | Network namespace create/destroy, veth, nftables |
| bootloader | (snapshot) | systemd-boot/GRUB detection, cmdline validation |
| update | (snapshot) | Atomic file ops, version comparison |
| fuse | (snapshot) | FUSE mount parsing, mount/unmount |

Per-module public-fn arity is tracked in [`api-surface-1.0.snapshot`](api-surface-1.0.snapshot) (machine-checkable; CI-gated via `scripts/check-api-surface.sh`). 556 public fns total.

## Test / Fuzz / Bench Coverage

| Category | Count | Where |
|---|---|---|
| Integration tests passed | **234 / 234** | `cyrius test` |
| Integration assertions | 257 | `tests/tcyr/test_integration.tcyr` (audit-regression block added 1.0.2) |
| Fuzz harnesses | 6 | `fuzz/audit_nlmsg.fcyr`, `fuzz/audit_reply.fcyr`, `fuzz/certpin_pin.fcyr`, `fuzz/journald_filter.fcyr`, `fuzz/luks_cipher.fcyr`, `fuzz/pam_config.fcyr` |
| Benchmarks | 30 (11 groups) | `tests/bcyr/bench_all.bcyr` |
| Bench file (compare) | 1 | `tests/bcyr/bench_compare.bcyr` (Cyrius vs Rust port baseline) |

## Local Audit Gates (`scripts/audit.sh`)

10 gates, all green at 1.0.5: syntax → API surface → capacity → build → smoke → tests → lint → vet → fuzz → benchmarks. Mirrors CI.

## CI Workflow Status

- `.github/workflows/ci.yml` — yukti-pattern: tarball install via cyrius.cyml-derived version, deps + verify-hashes, fmt-check, lint warn-fail, vet, dist staleness gate, DCE build, ELF magic, aarch64 best-effort cross, smoke, integration, fuzz, bench, security scan, docs check.
- `.github/workflows/release.yml` — accepts `vX.Y.Z` and `X.Y.Z`; verify-version, install toolchain, deps + verify, DCE build, aarch64 best-effort, tests, fuzz, regenerate dist, archive (source tar + bundled `.cyr` + prebuilt x86_64 + aarch64 binaries + cyrius.lock + SHA256SUMS).

## Dependencies

- **Runtime**: 0
- **Stdlib via `[deps] stdlib`**: `syscalls`, `string`, `alloc`, `fmt`, `vec`, `str`, `io` (7)
- **Git-pinned**: 0 (no `[deps.<name>]` stanzas; no `cyrius.lock` needed today)
- **Vendored stdlib refresh** (last): 2026-04-26 to cyrius 5.7.6 snapshot (`alloc.cyr`, `io.cyr`, `string.cyr`, `syscalls.cyr` — 5.5.x split into per-OS dispatch). 5.7.7 through 5.9.1 introduced no stdlib changes affecting agnosys's `[deps] stdlib = [syscalls, string, alloc, fmt, vec, str, io]` set; `cyrius deps` is a no-op against the existing vendor.

## Consumer Status

13 / 13 consumer crates unblocked at 1.0. Each consumer pulls only the modules it needs.

| Consumer | Modules | Status |
|---|---|---|
| kavach | security (landlock, seccomp) | Ready |
| aegis | mac | Ready |
| shakti | pam | Ready |
| libro | audit | Ready |
| stiva | luks, dmverity | Ready |
| sigil | tpm, ima, secureboot, certpin | Ready |
| ark | fuse, update | Ready |
| argonaut | journald, bootloader | Ready |
| daimon | security (seccomp), certpin | Ready |
| nein | netns | Ready |
| yukti | udev | Ready |
| soorat | drm | Ready |
| hoosh | certpin | Ready |

Automated consumer-integration CI is roadmap Phase 8 (item 5).

## Verification Hosts

- **Linux x86_64** — primary; `cyrius build` + `cyrius test` self-host.
- **Linux aarch64** — best-effort; CI cross-builds when `cc5_aarch64` is bundled in the toolchain release.
- **macOS / Windows** — not supported. Most modules are kernel-Linux-only by definition (audit netlink, PAM, journald, dm-verity, IMA, secureboot). See roadmap Phase 8 (item 3).

## Recent Releases

| Tag | Date | Headline |
|---|---|---|
| **1.1.0** | 2026-05-06 | First minor release after 1.0 freeze. `#derive(accessors)` migration complete across 16 struct-bearing modules (37 derive structs). Pure refactor; drop-in upgrade from 1.0.x; 160 additive public fns (no removals/drift). cyrius pin 5.9.14 |
| 1.0.13 | 2026-05-06 | V1.1.0 closeout patch — final 1.0.x slot before 1.1.0 tag. Cumulative baseline recorded: 16/16 modules migrated, 37 derive structs, 721 public fns (+160 additive), 85,592 B binary unchanged, 234 tests pass, 30 benches flat (one bench-locality drift in update_compare_versions noted) |
| 1.0.12 | 2026-05-06 | Tooling cleanup — `cyrius api-surface` adoption (5.9.14 ships `--scope=project`, `--snapshot=PATH`, and the `cyrius_api_surface` helper binary); `scripts/check-api-surface.sh` reduced from 70-line awk walker to a four-line wrapper; resolved api-surface issue archived |
| 1.0.11 | 2026-05-06 | V1.1.0 `#derive(accessors)` migration complete — pam + netns + update migrated (11 structs across 3 modules); cyrius pin 5.9.1 → 5.9.7 lifts the derive 32-struct cap; 16 of 16 struct-bearing modules done; ready for V1.1.0 closeout |
| 1.0.10 | 2026-05-06 | V1.1.0 `#derive(accessors)` slots 11–13 — ima + tpm + secureboot migrated (8 structs across 3 modules); 13 of 13 struct-bearing modules done; one batch left (pam + netns + update) |
| 1.0.9 | 2026-05-06 | V1.1.0 `#derive(accessors)` slots 8–10 — udev + journald + audit migrated (7 structs across 3 modules); 10 of ~13 struct-bearing modules done; learned: `syscall` is a reserved field name, asymmetric setter API needs wrappers |
| 1.0.8 | 2026-05-06 | V1.1.0 `#derive(accessors)` slots 5–7 — dmverity + luks + certpin migrated (6 structs across 3 modules); 7 of ~13 struct-bearing modules done; multi-line struct decl convention adopted |
| 1.0.7 | 2026-05-06 | V1.1.0 `#derive(accessors)` slots 2–4 — fuse + drm + bootloader migrated (4 structs across 3 modules); 4 of ~13 struct-bearing modules done |
| 1.0.6 | 2026-05-06 | First V1.1.0 `#derive(accessors)` slot — `src/mac.cyr` migrated (1 of ~13 struct-bearing modules); `scripts/check-api-surface.sh` extended to count derive-generated accessors |
| 1.0.5 | 2026-05-06 | Toolchain pin bump 5.7.48 → 5.9.1; no source changes, all 10 audit gates green |
| 1.0.4 | 2026-04-30 | aarch64 portability sweep — per-arch syscall peer files, raw-numeric syscall sweep across error/journald/etc.; toolchain pin 5.7.8 → 5.7.48 |
| 1.0.2 | 2026-04-26 | P(-1) sweep follow-up: audit-regression integration tests, three ADRs, SECURITY-NOTES F-4/F-5 entries, bench-history row for 1.0.1; toolchain pin 5.7.6 → 5.7.8 (skipping 5.7.7 — `cyrius check` regression, fixed in 5.7.8) |
| 1.0.1 | 2026-04-26 | Toolchain bump 5.2.0 → 5.7.6; CI ported to yukti pattern; binary size 76% reduction via `[lib]`-modules refactor; audit findings F-1..F-6 fixed |
| 1.0.0 | 2026-04-17 | API freeze. 139 renames, 20 modules ported, 556 public fns, 220 integration assertions, 30 benchmarks |
| 0.97.1 | 2026-04 (pre-1.0) | Rust source deleted, Cyrius port complete |

Full narrative in [`CHANGELOG.md`](../../CHANGELOG.md).

## In-Flight Slots

**V1.1.0 — `#derive(accessors)` migration — SHIPPED 2026-05-06**

37 derive structs across 16 modules; 721 public fns (561 at 1.0 freeze + 160 additive across V1.1). All slots and the closeout patch shipped in the 1.0.6 → 1.0.13 patch line; tagged as 1.1.0. See [CHANGELOG `[1.1.0]`](../../CHANGELOG.md) for the consumer-facing summary, [`[1.0.13]`](../../CHANGELOG.md) for the cumulative baseline, [`roadmap.md`](roadmap.md) V1.1 for the full slot list.

**V1.1.x — language-feature adoption (queued)**
- [ ] 1.1.1 — `defer { }` for resource-cleanup paths
- [ ] 1.1.2 — `secret var` + `ct_eq` builtin in certpin
- [ ] 1.1.3 — exhaustive `match` coverage adoption
- [ ] 1.1.4 — first-class tagged-union `Result` replacing lib/tagged.cyr
- [ ] 1.1.5 — multi-width struct fields for kernel binary protocols
- [ ] 1.1.6 — slice migration for syscall + parser buffers
- [ ] 1.1.7 — `#derive(Serialize)` for diagnostic JSON output

V1.2.0 (multi-profile `cyrius distlib`) follows. See [`roadmap.md`](roadmap.md) for the full plan.

## Last Security Audit

[`docs/audit/2026-04-26-audit.md`](../audit/2026-04-26-audit.md) — P(-1) hardening pass at 1.0.1.
