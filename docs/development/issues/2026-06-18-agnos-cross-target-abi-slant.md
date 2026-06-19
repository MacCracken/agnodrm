# agnosys is Linux-slanted — 31 cross-target ABI/mechanism gaps for agnos

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
