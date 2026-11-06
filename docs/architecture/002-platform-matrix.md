# 002 — What each module does on each target

agnodrm targets Linux on x86_64 and aarch64, and agnos. macOS and Windows are not supported.

Linux on the two arches is one code path. `src/` has no arch gate: the stdlib's per-target `sys_*` helpers and `O_*` /
`STAT_*` names carry the differences, which is why raw syscall numbers are forbidden here. agnos is the target with real
branches, under `#ifdef CYRIUS_TARGET_AGNOS`.

| Module | Linux, x86_64 and aarch64 | agnos |
|---|---|---|
| error | Full | Full |
| util | Full | Full. Scratch memory comes from `alloc`, so it is never given back, and `agnodrm_fsync` syncs the whole filesystem |
| udev | Full | `udev_list_devices` is `Ok(0)`, no devices. `udev_get_device_info` is `not_supported`. Parsers and `udev_validate_rule` work |
| drm | Full | `drm_list_devices` is `Ok(0)`, no cards. Open, version and capability are `not_supported`: display goes through bhumi |
| journald | Full | `journald_send` and `journald_query` are `not_supported`: agnos logs through sakshi. Filters and parsers work |
| netns | Full | Create, destroy, `netns_run_ip` and `netns_apply_nftables_ruleset` are `not_supported`. Validators and the ruleset renderer work |
| bootloader | Full | `bootloader_detect` is `BOOT_UNKNOWN` and `bootloader_list_boot_entries` is `Ok(0)`: agnos boots through gnoboot. Parsers and validators work, and `bootloader_list_loader_entries` has no arm: it reads the directory it is given |
| update | Full | Everything that touches a file or a slot is `not_supported`: atomic write and copy, load and save, check, apply, switch, rollback. Version compare and manifest structure checks work |
| fuse | Full | `fuse_is_available` is 0, and a mount list is empty. Mount, unmount and `fuse_validate_mountpoint` are `not_supported` |

The split between `Ok(0)` and `not_supported` is deliberate. A question with an honest answer on agnos, such as how many DRM
cards there are, gets it. A request that cannot be carried out is refused.

## What is proved on each target

- **Linux x86_64:** everything. Every gate and every test runs here.
- **Linux aarch64:** the tests and fuzz harnesses run under `qemu-aarch64` in CI and in release. qemu-user does not translate
  every ioctl, so DRM's `GET_CAP` reads `ENOTTY` there. The test accepts `ENOTTY` from that call on any host, since nothing
  detects emulation, and the block is skipped with no render node.
- **agnos:** build only. `scripts/gen-api-probe.sh` calls every public fn, so the agnos lane proves every arm compiles and
  every call resolves. No test runs on agnos, so nothing here proves an arm behaves.
