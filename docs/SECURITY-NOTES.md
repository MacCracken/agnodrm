# Module Security Notes

Per-module security considerations for **agnodrm**. Each module wraps kernel
interfaces with different trust boundaries and privilege requirements.

Covers the 9 modules that survived the agnosys → agnodrm decomposition
(2026-06-19): the device-model core (`error`, `util`, `udev`, `drm`) and the
deferred Linux-eccentric group (`journald`, `netns`, `bootloader`, `update`,
`fuse`).

> **Moved out at 1.4.4.** Notes for `syscall`, `logging`, `security`
> (landlock/seccomp), `mac`, `audit`, `pam`, `luks`, `dmverity`, `ima`,
> `tpm`, `certpin`, and `secureboot` were removed from this file at 1.5.3 —
> those modules live in **cyrius**, **sakshi**, **kavach**, **aegis**, and
> **sigil** now, and stale copies here were a hazard: a reader could take a
> privilege or trust-boundary claim as current when the code has not been in
> this repo since 1.4.4. See each owning repo for its own notes.

## error

- Pure integer error types. No heap allocation on packed error path.
- `drm_syserr_pack(kind, errno)` encodes `kind << 16 | errno`, zero-alloc. `errno` is masked to its 16 bits, because the packed and heap forms are told apart by value: unmasked, a stray return of -0x100000 read as a heap pointer and crashed (1.7.2).
- `drm_syserr_new(kind, errno, message)` heap-allocates for diagnostics, cold path only.
- `drm_err_from_syscall_ret()` maps known errnos to typed variants. A bare agnos `-1` reads as `EPERM`.
- `result_print_err` returns nonzero for every `Err`. Through 1.7.1 an `Err` with errno 0, which is every `drm_err_unknown`, returned 0, so a caller using it as an exit code reported success.

## util

- Shared `agnodrm_*` helpers: JSON emit, hex/name-char classification,
  cstr-prefix test, `run_capture`/`run_checked` exec wrappers, read-fd,
  fsync/rename.
- **`agnodrm_run_capture` / `agnodrm_run_checked` take an explicit argv
  vector** and exec it directly — no shell, no PATH lookup. Element 0 must be
  an **absolute** binary path; `execve(2)` does not search PATH.
- **`agnodrm_read_fd_to_str(fd, cap)` allocates `cap + 1`** so the NUL
  terminator cannot write past the end on a full read. The per-module copies
  it replaced allocated exactly `cap` — a latent 1-byte overflow (1.3.1).
  The same class recurred in `fuse` and was fixed at 1.5.3 (F-5).
- **Scratch buffers do not come from `alloc()`.** It never frees, and neither does `arena_free`, so a buffer a call drops would stay in the heap for good. `_agnodrm_scratch_new` maps memory that `_agnodrm_scratch_free` gives back, and nothing may keep a pointer into it past the free (1.7.2, audit F-40). The strings a call returns are heap copies, and grow with what the caller asks for, not with how often.
- `_agnodrm_read_all` and `_agnodrm_write_all` retry `EINTR`, report a failed read as a negative errno rather than a short file, and turn a write that makes no progress into `-EIO`.
- `agnodrm_run_capture` returns `Err` when the end of the child was never observed, which includes a parent running with `SIGCHLD` ignored. That is deliberate: a tool whose exit nobody saw cannot be reported as having succeeded.

## udev

- Shells out to `udevadm` for device enumeration.
- **`E:` values are device-supplied text.** A USB product string, a `HID_NAME` or a WWN can hold a newline and forge a line of `udevadm` output: upstream fixed that class in `scsi_id` (GHSA-m8q3-73v4-wvg7, CVE-2026-40225) and consumers keep hitting it (CVE-2026-50292 in libinput, CVE-2026-16313 in sg3_utils). So the parser never lets a line override one before it: the first `P:` stands and a second fails the block, the first `N:` stands, and `U:`/`T:`/`V:` outrank the `E:` properties. A device node that climbs out of `/dev` is refused (1.7.2, audit F-36). A forged line can still start a block of its own after a blank line, and a property value is still whatever the device said, so treat both as untrusted.
- `udev_list_devices` parses the whole database or fails. A capture that fills its buffer runs again with a larger one, up to 64 MiB (1.7.2, audit F-37). A count equal to `max_devices` may mean there are more.
- `udev_get_device_info` takes a `/sys/...` or `/devices/...` path with no `..` component, and refuses the rest before `udevadm` runs.
- **`udev_validate_rule` is a denylist.** It refuses keys that run a program, write a sysctl or start a unit (`RUN`, `PROGRAM`, `SYSCTL`, `IMPORT{program}`, `IMPORT{builtin}`, `ENV{SYSTEMD_WANTS}`, `ENV{SYSTEMD_USER_WANTS}`), with any attribute or operator after the name. Through 1.7.1 `RUN{program}`, the spelling real rules use, passed. `ATTR{...}` writes are not refused, so `Ok(0)` is not a statement that a rule is safe.

## drm

- `DRM_IOCTL_VERSION` and `DRM_IOCTL_GET_CAP` go through `sys_ioctl`, with the retry on `EINTR` and `EAGAIN` that libdrm's `drmIoctl` does, bounded at 64 tries.
- `DRM_IOCTL_VERSION` is `0xC0406400`, `struct drm_version` being 64 bytes. Through 1.7.1 it encoded 72. `drm_ioctl` takes the caller's size, so real kernels answered, but qemu-user and an ioctl-number allowlist refused it (1.7.2, audit F-35).
- **`drm_open` opens only DRM devices.** It requires a character device that answers `DRM_IOCTL_VERSION`, and closes anything else, so a regular file, `/dev/ptmx` or `/dev/kvm` cannot come back as an `Ok` fd (1.7.2, audit F-38). `O_NOCTTY` keeps a tty opened by mistake from becoming the controlling terminal.
- **Opening a card node takes DRM master when none is held.** A caller that only queries should open a render node: both ioctls here are `DRM_RENDER_ALLOW`.
- **Privilege: read and write on the node.** `card*` is usually `video`, `renderD*` usually `render`.
- `drm_verinfo_date` is `"0"` on current kernels, which no longer carry a driver date.
- Buffer sizes from kernel capped to prevent malicious responses from causing OOM.
- Two-pass ioctl pattern (get sizes, then get data).
- **F-3/F-4 (LOW, 1.5.3), defence-in-depth:** the `/dev/dri` getdents64 walk
  now validates `d_reclen` (a zero value spun forever; an oversized one walked
  past the read window) and scans `d_name` with an explicit bound instead of
  `strlen`. `DRM_IOCTL_VERSION` string lengths are clamped low as well as
  high — they are `__kernel_size_t`, so a value >= 2^63 read back as a
  negative i64 and slipped past the `> 4096` cap.

## netns

- Namespace work runs `/usr/sbin/ip` via argv (`exec_vec`, no shell); no raw syscalls in this module since 1.6.2.
- **Privilege: CAP_SYS_ADMIN** required for namespace operations.
- `/run/agnos` is created 0755, the mode kybernet gives it, and `netns_apply_nftables_ruleset` refuses it if anyone else can write there, by mode or by owning it.
- Inner `ip` and `nft` are absolute. `exec_vec` passes an empty environment, so `ip netns exec` looks a bare name up on the libc default path alone, which misses `/usr/sbin` on an unmerged system.
- `netns_validate_config` holds the name to letters, digits, `-` and `_`, not starting with `-`, and requires both addresses to be dotted-quad IPv4, with no leading zeros: `ip` and `nft` read `010.0.0.1` as octal, 8.0.0.1, a rule on the wrong host (1.7.2, audit F-42). `ip` reads `%d` in an interface name as a template, which left a link no cleanup could name.
- A veth end is `veth-<name>-h`, or `veth-<8 hex of a hash>-h` when that would pass 15 bytes. Truncating cut the suffix off, so every name of 9 or more bytes gave both ends one name and `ip link add` refused it (1.7.2, audit F-22).
- `netns_generate_agent_ips` picks one of 16384 /30 subnets by a hash of the name. It keeps no registry, so a caller running many agents must check for a clash.
- `enable_nat` and the DNS fields are stored and acted on by nothing.
- Per-process, exclusively created nftables temp file instead of a fixed path (avoids races and planted links). It is closed before `nft -f` reads it, so whoever could write to `/run/agnos` could swap the ruleset in that window.
- **`netns_render_nftables_ruleset` renders every rule as written, or nothing.** One rule is one line, so a port and an address match together: through 1.7.1 they became two independent rules, and "ssh from the bastion" opened 22 to everyone and every port to the bastion (audit F-18). A rule that cannot be expressed fails the whole policy, and the renderer returns 0; `netns_fw_policy_validate` says why. A silently dropped rule is a hole under a default accept.
- **Policy data stays data.** `remote_addr` must parse as an IPv4 or IPv6 address with an optional prefix, neither with a leading zero, and a comment must be printable ASCII with no quote or backslash, at most 128 bytes (audit F-19). Through 1.7.1 either could close its context and add rules.
- **A render replaces the table.** The ruleset declares `table inet kavach` and deletes it before defining it, in one `nft -f` transaction, so a re-apply cannot keep an old accept (audit F-24). Verified against real `nft` in a private namespace.
- The renderer has no size limit. `netns_nft_append`, the 16 KiB bounded helper it used, is deprecated.
- **nftables ruleset is pass-through.** `netns_apply_nftables_ruleset` writes the caller-supplied ruleset to an exclusive temp, `/run/agnos/nft.tmp.<pid>.<ctr>` (1.7.0; see `update`), and runs `ip netns exec <ns> nft -f <that file>` via argv (`exec_vec`, no shell). Since 1.6.2 a short or failed write of that file fails the call (a truncated ruleset would silently drop rules), and the temp file is removed after every run — through 1.6.1 its cleanup was a `defer` that never ran (see *All modules* below). agnosys does **not** parse or sanitize the ruleset content; the kernel nft surface is exposed to whatever the caller provides, and an `include` line in a ruleset echoes the included file's contents in `nft`'s error text. Consumers (nein) must trust their ruleset source. Recent kernel CVEs in this surface include CVE-2026-31407 (conntrack netlink validation) and CVE-2026-23231 (UAF in `nft_chain`); agnosys is on the data path, not the vulnerability sink.
- **F-7 (LOW, 1.5.3): `netns_validate_config` now rejects `prefix_len < 1`**,
  not just `== 0` — a negative value previously passed validation and
  overflowed a 4-byte format scratch.

## fuse

- Mounts through a helper binary and unmounts through `fusermount3`, or `fusermount` where that is the only name. No raw `/dev/fuse` fd handling lives in this module.
- **`fuse_mount` hands its arguments to a helper that reads options.** `fuse_type` must be an absolute path: `execve` does no PATH lookup, so a relative one runs from the working directory. A `device` or `mountpoint` starting with `-` is refused, because sshfs's `-o ssh_command=` runs a program (1.7.2, audit F-23). `extra_opts` is options by definition, and the caller's to trust.
- `fuse_mount` calls `fuse_validate_mountpoint`, which rejects the root directory by identity, so `//`, `/.` and `/tmp/..` are caught as well as `/`.
- Unmount passes `--` before the mountpoint.
- **`fuse_only` means FUSE mounts:** `fuse`, `fuseblk` and `fuse.<subtype>`. `fusectl`, the control filesystem, read as one through 1.7.1.
- `/proc/mounts` is read to EOF in a buffer that grows to 16 MiB, past which the call fails rather than parse part of a table (1.7.1, audit F-7).

## update

- `update_atomic_write` / `update_atomic_copy`: write an exclusive temp beside the target (`<path>.tmp.<pid>.<ctr>`), fsync, rename over `<path>`, then fsync the directory, so the rename is on disk before whatever the caller does next (1.7.2, audit F-33). A filesystem with no directory fsync (`EINVAL`) has nothing more to offer. An existing target keeps its permission bits and the temp is born with them, so a 0600 file's new bytes are never readable by more than the old ones were; a new copy takes the source's mode (audit F-32). Ownership and set-id bits are not carried across.
- **Temp files are created exclusively (audit F-1, fixed 1.7.0).** Through 1.6.3 these fns and `netns_apply_nftables_ruleset` opened a predictable temp path with `O_CREAT|O_TRUNC`, so a symlink planted there redirected the write and the rename installed the link over the destination. `agnodrm_tmp_create` now uses `file_create_exclusive`, which refuses a name that exists as anything, including a dangling link. A taken name moves to the next counter; after 64 the call fails with `EEXIST` and writes nothing. Exclusivity is the guard, not the name: the counter starts from `getrandom` only so that a restart with the same pid does not walk the same names, and the worst a planted name can do is refuse the write. A crash can leave a temp behind, and it is never reused or cleaned up. The suffix takes up to about 23 bytes, so a target file name over about 232 bytes fails with `ENAMETOOLONG`. None of this makes an untrusted directory safe: anyone who can write there can still replace `<path>` itself. See [`audit/2026-11-05-audit.md`](audit/2026-11-05-audit.md).
- **Slot state, 1.7.2 (audit F-15, F-16, F-17, F-25, F-26).** The write order is the design: see [`architecture/001-slot-write-order.md`](architecture/001-slot-write-order.md). `rollback_available` means a switch left a good slot behind: `update_apply` clears it and `update_switch_slot` sets it, so "written but never switched to" stays distinct from "on trial". `update_apply` proves the next boot stays on the running slot, then clears and saves the record, then runs `dd`, and refuses outright while an image is on trial on the running slot, because the target would be the one good slot left. Moving forward writes the state, the marker, then the firmware; moving back writes the marker, the firmware, then the state. `update_switch_slot` refuses a slot with nothing known to boot on it. `update_mark_boot_attempt` counts boots of an image on trial, which is what `update_needs_rollback` reads. `update_mark_boot_successful` needs `agnos.slot=` to name the trial's slot, then promotes the pending version and records the one it replaced.
- **On an EFI host with a failing `efibootmgr`, a rollback and an update refuse until it works.** `BootNext` outranks the marker, and a stale one would boot the slot being left or overwritten. No EFI, or no `efibootmgr`, means none this library could have set.
- **What `update_apply` verifies, and what it does not (audit F-29).** It runs `update_verify_manifest`, requires one whole raw image, and with `verify` on, the default, compares the image to the manifest's sha256 through `/usr/bin/sha256sum`, failing if that tool is missing. That catches a corrupt image. It does not catch a forged one: **the manifest is not signed**, so anything able to write the manifest and the staging directory chooses what is installed. `min_version`, `max_retries` and `backup_dir` are carried and not enforced.
- **The state file is read strictly (audit F-30, F-31, F-53).** A token-walking reader refuses anything but one whole object with `current_slot` 1 or 2 and fields of the right type, so text inside a string is never read as a key. `update_save_state` refuses a value JSON would have to escape. Only a missing state file counts as fresh: one that cannot be read or parsed still holds the rollback record, so `update_switch_slot` and `update_apply` refuse rather than overwrite it.
- **`update_apply` trusts only `agnos.slot=` on the kernel cmdline (1.7.1).** The state file records where the next boot goes, so it is wrong between a switch and the reboot and after a firmware fallback, and a wrong answer overwrites the running root. With no token, or an unreadable one, the call refuses. Tokens split as the kernel splits them, and two that disagree are an `Err`. `update_get_current_slot` keeps its fallbacks as a guess for display. A host needs `agnos.slot=` in its boot entries to take updates.
- Since 1.6.2, `update_atomic_copy` fails when the fsync fails, as `update_atomic_write` always did. Before, it renamed an unflushed file over the target.
- `update_state_to_json` emitted the `pending` cstring as an integer through 1.6.1, so a pending update exposed a heap address in the JSON. Since 1.6.2 it is a quoted string, or `null`.

## journald

- Unix datagram socket to /run/systemd/journal/socket.
- Journal protocol: `KEY=VALUE\n` for single-line, binary length prefix for multi-line (real since 1.7.1: until then a value's newline ended its field, and the rest parsed as forged fields, audit F-9). `journald_send_fields` skips a field name the journal would not accept.
- `journald_send_fields` skips field names the journal would not accept, which covers newlines and `=` (injection prevention).
- No authentication — any process can write to the journal socket.
- The bytes of a message reach the journal as given, ESC included, so a reader that writes them to a terminal must filter them (CVE-2026-40228 was journald's own `ForwardToWall` doing that).
- A message too big for one datagram, about 212 KB, goes as a sealed memfd with the same bytes, as `sd_journal_sendv` does, and nothing is cut. journald takes it or drops it without telling the sender, so `Ok` means sent, not stored. It first asks for `MFD_NOEXEC_SEAL`, needed under `vm.memfd_noexec=2`, and falls back on a kernel before 6.3 that refuses it; neither branch can be forced on a modern default host, so neither has been run.
- `journald_send_fields` refuses extras that restate `MESSAGE`, `PRIORITY` or `SYSLOG_IDENTIFIER` (audit F-46).
- **`journald_query` uses argv-based exec — no shell.** Every filter value lands in its own `argv[i]` entry. `--unit`, `--since`, `--until`, `--priority` and `--grep` take a required argument, so the next word is the value whatever it looks like. **`--boot` takes an optional one, so it is passed as one word, `--boot=<value>`.** Through 1.7.1 it was two, and a value that did not parse as a boot id stayed on the command line, where `--vacuum-time=1s` is an option and `_UID=0` a match (audit F-20). Fuzz coverage at `fuzz/journald_filter.fcyr`.
- `journald_query` reads the whole output or fails, growing its buffer to 32 MiB (audit F-21). It passes `--all`, since journalctl otherwise prints fields over 4096 bytes as null. The reader decodes escapes, byte arrays and repeated fields, so one ESC byte cannot hide a line behind an empty message (audit F-47). : a hostile `--grep` pattern runs for as long as PCRE2 takes.
- `journald_query` gives journalctl a deadline: 60 s printing nothing, or the process's own deadline if that is tighter, and the call is `ETIMEDOUT`, even if journalctl would have finished a moment later. The stdlib then gives it as long again before killing it, so the caller waits up to twice the deadline. It measures silence, not total time, and restarts for each larger buffer, so a pattern that keeps matching slowly fills the 32 MiB bound instead. A slow query on a very large journal can hit it.

## bootloader

- Reads /boot/loader/entries/*.conf and /boot/grub/grub.cfg.
- **Loader-entries reader (1.6.2) treats entry files as untrusted.**
  - It reads what systemd-boot reads (1.7.2, audit F-27, F-28): lines end at CR as well as LF, a file
    stops at a NUL byte, the `.conf` suffix matches in any case, and `/boot`, `/efi` and `/boot/efi`
    are merged, an id seen twice listed once. Reading less hid entries the machine still boots.
  - **A list that cannot be complete is an `Err`.** A file over 64 KiB or more entries than
    `max_entries` fails the call, since neither may be left out. The bootloader reads any size.
  - Only names that stat as regular files are opened, and names are filtered first: `*.conf` only,
    no hidden names, no `/` or control bytes, at most 255 bytes.
  - `efi`, `uki`, `uki-url` and `extra` are read. `bootloader_entry_boot_kind` applies systemd-boot's rule, that an entry names exactly one way to boot. Only for `BOOT_ENTRY_LINUX` is `options` known to be the whole command line. A UKI takes `options` in place of its own line unless Secure Boot is on and it has one, and then its own line applies, which nothing here can read.
  - `extra` hands a UKI credentials and system extensions. systemd-boot adds nothing from it to a command line, and it holds paths, so validating it proves nothing. What does add to a UKI's line is `/loader/addons` and `<uki>.efi.extra.d`, which the file path does not read.
  - Values lose one matching pair of quotes, as systemd-boot takes them off, so a quote cannot hide an option. `initrd`, `options` and `extra` join on one space, so a path holding a space cannot be told from two.
  - `auto-*.conf` is listed, though systemd-boot skips it, which errs toward showing it.
  - Remaining gap (LOW): the stat and the open are separate calls, so a FIFO swapped in between them
    can block the read. Doing that needs write access to the entries directory, i.e. root on `$BOOT`.
- **`bootloader_list_boot_entries` reads the entry files as well as `bootctl`.** bootctl leaves out what systemd-boot boots: a name it calls invalid, or a line it cannot parse. Every file it did not report is added, and a bootctl entry with no boot key takes its file's. On a host where neither `/boot`, `/efi` nor `/boot/efi` holds the entries, bootctl's word stands.
- **`bootctl list` output is parsed as display text.**
  - It is not a clean channel. A blank line in a UKI's `.uname` section splits a block, and a newline in an addon's command line
    prints at column 0, where it can read as a label. So `bootloader_list_boot_entries` asks for `--json=short` first, where both
    are one escaped character, and reads text only from a bootctl too old to know the flag.
  - The JSON's `cmdline` wins over `options`, since it holds what addons add, and an entry with an escaped NUL is refused, since
    past one a C string would hide the rest. `isDefault` is believed there, and never from the text. Paths come from `extras`.
    `addons` holds objects for the addons among them, and is `null` on a host with none, which is why it took a built tree to
    see the shape. Any change here should start from real output of such a tree.
  - A file's boot keys win over bootctl's. bootctl drops a path it will not take and prints the rest, so after `linux /ok` and
    `linux /x/../evil` it shows `/ok`, and systemd-boot takes the last. It also joins `options` lines, which hides what a quote
    pair would have shown. `options` and `extra` hold what both say, because only bootctl knows what an addon adds, so an
    option can read twice over. That errs toward a validator seeing more than boots.
  - A Type #2 line keeps its quotes, since nothing takes them off a UKI's line, and is mangled as sd-stub does: control characters
    become spaces, and both ends are trimmed. Quoting a word there hides nothing from the kernel, so the validator reads it as is.
  - Every `.efi` under `/EFI/Linux` on the three roots is accounted for, read as systemd-boot reads it, since bootctl refuses a
    name holding a space and can fail outright. One it did not report comes back with no `options`. Each entry answers for one
    file, so the same name on the other partition still shows, and a counted UKI or a profile can show under two names.
  - From this path `BOOT_ENTRY_NONE` says only that bootctl showed no boot key. Automatic entries and "Reported by Boot Loader" entries look like that, and can boot.
  - Titles keep bootctl's marks, and linux / initrd keep its `<root>//` prefix and
    "(No such file or directory)" notes.
  - `is_default` is never inferred from those marks: an entry's own title can imitate them.
  - Continued `options` / `initrd` lines are joined, so no kernel parameter is dropped before a
    caller checks the options with `bootloader_validate_kernel_cmdline`. Through 1.6.1 every
    continuation line was dropped.
  - Output that fills the 64 KiB capture buffer is refused rather than parsed truncated.
- **Privilege: read access to /boot.**
- Kernel cmdline validation uses single-pass tokenizer with hashmap danger lookup.
- **`bootloader_validate_kernel_cmdline` is a DENYLIST, not an authorisation
  boundary.** `Ok(0)` means "no listed parameter matched" — it does **not**
  mean the cmdline is safe. Every space-separated word is checked, inside quotes too:
  the kernel holds a quoted value together, but an initramfs may not, so
  `foo="x rd.break y"` is refused. Each word is read as the kernel reads a parameter,
  with quotes stripped, `-` and `_` folded in the name, in either case, then matched
  exactly, by an "off" value (`0`, `off`, `n`, `no`, `false`) of a known switch, by
  name alone for `rdinit=`, `rd.break=` and `systemd.run=`, or for `init=` by the file
  name of a shell in any directory (1.7.2, audit F-51). The SysV single-user tokens
  `S` and `1` match only standing alone, so a dm-verity table's `1` passes. An
  unlisted interpreter or a novel kernel parameter passes. Allowlist-based validation
  is roadmap V2.0.
- **`bootloader_is_dangerous_token` does not match what the validator does.**
  It is a case-insensitive *substring* search; the validator matches *exact
  tokens*. It has no production callers and is retained only because the 1.0
  API surface is frozen. Prefer `bootloader_validate_kernel_cmdline`. Removal
  is roadmap V2.0 (F-2, 1.5.3).

## All modules

- **`defer` and Results.** cyrius 6.6.0–6.6.6 skipped a `defer` block when the fn returned a value-form Result. Through 1.6.1 agnodrm leaked one fd or socket per call in eight fns (`journald_send` leaked a socket per log line, a slow path to `EMFILE`) and left the nft temp file behind in a ninth. Since 1.6.2 every release is explicit. `defer` is fixed at 6.6.7, the consumer floor since 1.7.1. `tests/tcyr/test_integration.tcyr` `test_fd_hygiene` counts `/proc/self/fd` around repeated calls. Tracker (closed): `docs/development/issues/archive/2026-09-22-cyrius-defer-skipped-on-result-return.md`.
- **No raw syscalls or flag literals** (1.6.2). Every syscall goes through a stdlib per-target
  helper and every open flag / stat offset is a per-target name. Raw values caused 1.6.1's aarch64
  `O_DIRECT`-for-`O_DIRECTORY` bug and 1.6.2's aarch64 `st_uid`-for-`st_mode` bug in
  `fuse_validate_mountpoint`, which rejected every directory.
