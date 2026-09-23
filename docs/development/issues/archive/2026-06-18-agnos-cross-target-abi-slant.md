# agnosys is Linux-slanted — 31 cross-target ABI/mechanism gaps for agnos

**Status:** RESOLVED (archived 2026-09-22 at agnodrm 1.6.2). Of the 31 cited 1.4.3 sites: 18 moved out at 1.4.4, 12 are gated off agnos (1.4.6 / 1.5.0), and 1 makes no syscall. 1.6.2 removed the last ungated Linux raw syscalls and added a build gate that compiles every module's agnos arms. See the resolution at the end.

**Filed:** 2026-06-18
**Severity:** agnosys is the system-interface layer and is meant to run on
`CYRIUS_TARGET_AGNOS`, but large parts assume a Linux host — they misbehave or
fault on agnos.
**Found by:** ecosystem cross-target audit (whirl HTTPS-on-agnos QEMU bring-up
surfaced the class; this is the agnosys slice). Sister issues filed in `patra`
and `cyrius` (fs/tls). Vendored as `cyrius/lib/agnosys.cyr` v1.4.3 — fix here, then
`cyrius distlib` re-vendors.

## Framing
agnosys is **agnos-destined**; it bootstrapped on a Linux kernel host, so much of
it is Linux-slanted by history. agnos is the **destination**, not a second target.
Today agnosys is effectively half a Linux security daemon (Landlock, seccomp, IMA,
TPM, SecureBoot, dm-verity, LUKS, PAM, journald, DRM) inside what is supposed to be
*the* agnos system layer. `cyrius`'s `process`/`args`/`io` show the right pattern
(whole POSIX block under `#ifndef CYRIUS_TARGET_AGNOS`, delegate / bridge the ABI) —
apply it here.

## ABI facts
agnos `sys_*` differ from Linux: `sys_open`=(name,namelen,flags) vs (path,flags,mode);
`sys_stat`=(path,pathlen,statbuf) vs (path,buf); `sys_unlink`/`rmdir`=(path,pathlen)
vs (path). Raw `syscall(N)` Linux numbers (`SYS_GETDENTS64`=217, `SYS_IOCTL`,
`SYS_SOCKET`) are wrong/absent on agnos.

## A. Generic FS I/O — make portable (agnos MUST run these)
Plain file ops with the Linux ABI; just need the per-target signature (prefer a
length-carrying wrapper, see the cyrius sister issue's structural fix):
- `sys_open` atomic-write tmp: **8315**, **8861** (`0x241`=O_WRONLY|O_CREAT|O_TRUNC).
- `sys_stat`: **10128**.

## B. Linux-only host mechanisms — route to agnos-native or stub (design call)
agnos has its OWN security/trust model (**sigil / aegis / shakti / kavach / phylax**)
and its own boot/firmware story — these Linux subsystems should, on agnos, map to
the native primitive **or** return a clean "unsupported-on-agnos", never run Linux
ABI. Guard each with `#ifdef CYRIUS_TARGET_AGNOS` (native/stub) / `#ifndef` (Linux):

| subsystem | lines | Linux dependency |
|---|---|---|
| log-from-env | 692 | `/proc/self/environ` |
| Landlock | 1053 | Linux LSM syscall |
| MAC (SELinux/AppArmor) | 1388, 1413, 1447 | `/sys/kernel/security/lsm` |
| PAM | 3031, 3238 | `/etc/passwd`, `/etc/pam.d` |
| journald | 3452, 3502 | `/run/systemd/journal/socket` + `SYS_SOCKET` |
| LUKS | 4149, 4234, 4300 | dm-crypt keyfiles |
| dm-verity | 4892 | `/sys/module/dm_verity` |
| IMA | 5180, 5325, 5415 | `/sys/kernel/security/ima` |
| TPM | 5847 | `/dev/tpm*` |
| SecureBoot/EFI vars | 6462, 6508, 6988 | `/sys/firmware/efi` |
| DRM/GPU | 7599, 7609, 7631, 7647, 7671, 7700, 7726 | `getdents64` + `DRM_IOCTL_*` |
| boot/update slot | 9287 | `/proc/cmdline` |

**Triage per subsystem:** (a) agnos-native equivalent exists → route under `#ifdef`
to the agnos primitive; (b) no agnos analog yet → `#ifndef CYRIUS_TARGET_AGNOS`
guard + agnos stub returning unsupported, so the build is correct now and the agnos
path is a tracked TODO. Mapping the MAC/IMA/TPM/SecureBoot intent onto sigil/aegis
is the substantive design work; the FS + DRM ones are mechanical.

## Verify
`agnos/scripts/whirl-smoke.sh` boots agnos in QEMU (virtio-net + SLIRP) and
exercises the FS + TLS paths end-to-end — the harness that caught this class.

## Resolution (1.6.2, 2026-09-22)

**Bundle.** The cited line numbers are `dist/agnosys.cyr` at commit `d3339e6` (1.4.3, 2026-06-15,
10,198 lines). Spot-checked: 692 `log_init_from_env`, 1053 `security_apply_landlock`,
3502 `journald_send`, 7647 `drm_open`, 8861 `update_atomic_write` and 10128
`fuse_validate_mountpoint` all resolve there. The cyrius copy this issue asked to re-vendor,
`lib/agnosys.cyr`, was deleted at cyrius v6.2.37.

| Subsystem | 1.4.3 line: fn | At 1.6.2 |
|---|---|---|
| log-from-env | 692 `log_init_from_env` | Moved out with logging (sakshi) at 1.4.4 |
| Landlock | 1053 `security_apply_landlock` | Moved out to **kavach** |
| MAC | 1388, 1413, 1447 `mac_*` | Moved out to **kavach** |
| PAM | 3031, 3238 `pam_*` | Moved out to **aegis** |
| journald | 3452 `journald_make_sockaddr` | Stays; makes no syscall (fills a heap `sockaddr_un`) |
| journald | 3502 `journald_send` | Gated at 1.4.6: `Err(not_supported)` on agnos |
| LUKS / dm-verity / IMA / TPM / SecureBoot | 4149, 4234, 4300, 4892, 5180, 5325, 5415, 5847, 6462, 6508, 6988 | Moved out to **sigil** |
| DRM | 7599, 7609, 7631 `drm_list_devices` | Gated at 1.4.6: `Ok(0)` on agnos |
| DRM | 7647 `drm_open` | Gated at 1.5.0: `Err(not_supported)` on agnos |
| DRM | 7671, 7700, 7726 `drm_get_driver_version` / `drm_get_capability` | Gated at 1.4.6 |
| netns (§A) | 8315 `netns_apply_nftables_ruleset` | Gated at 1.4.6 |
| update (§A) | 8861 `update_atomic_write` | Gated at 1.4.6 |
| update | 9287 `update_get_current_slot` | Gated at 1.4.6 |
| fuse (§A) | 10128 `fuse_validate_mountpoint` | Gated at 1.4.6 |

**Section A ("agnos MUST run these") is not met literally, and no longer should be.** All three
sites have returned `Err(not_supported)` on agnos since 1.4.6. Each is one step of a Linux-only job:
an nftables load inside an `ip netns`, the A/B slot state file, and a FUSE mountpoint check. All
three sit in the deferred Linux-eccentric group, and no known consumer (stiva, aethersafha) calls
them. The portable primitive the section asked for exists in cyrius `lib/io.cyr`: `file_open` (with
O_* → AO_* flag mapping), `xstat` / `xunlink` / `xgetdents`, `file_rename`, `xfsync`,
`file_write_atomic` and `file_replace_atomic`. The matching cyrius issue,
`2026-06-18-stdlib-native-agnos-abi-fs`, is marked resolved at v6.2.33. The issue's framing, with
agnosys as *the* agnos system layer, ended with the 1.4.4 decomposition.

**Current tree (1.6.2):**
- **Gated.** Every path-taking `sys_open` / `sys_stat` / `sys_unlink`, every `sys_getdents64` /
  `sys_ioctl` / `sys_socket` / `sys_sendto`, every `/usr/bin` / `/usr/sbin` exec, and every
  `/proc` / `/sys` / `/dev` / `/run` / `/boot` / `/var` path in `src/` sits under
  `#ifndef CYRIUS_TARGET_AGNOS`. No raw `syscall(` is left in `src/`.
- **Portable.** What runs on every target goes through per-target stdlib helpers:
  `agnodrm_fsync` → `xfsync`, `agnodrm_rename` → `file_rename`, and the new loader-entries reader →
  `file_open` / `dir_list` / `xstat` / `file_read_all`.
- **Fixed in 1.6.2:** on 1.6.1, `agnodrm_fsync` / `agnodrm_rename` issued the inlined x86 numbers
  74 and 82, which on agnos are `shm_free` and `gpu_dispatch`.
- **Build gate closed in 1.6.2.** The `--agnos` gate used to build only `src/main.cyr`, which reaches
  the four core modules. cyrius reports an undefined function only inside a reachable fn, so the
  agnos arms of journald / netns / bootloader / update / fuse were never checked. Gate 5, CI and
  release now also build `scripts/gen-api-probe.sh`'s probe for agnos. The probe calls all 316
  public fns. A deliberately undefined call in `journald_send`'s agnos arm passes the old build
  and fails the probe build.
- **Not tested on a running agnos system;** `whirl-smoke.sh` was not run.
