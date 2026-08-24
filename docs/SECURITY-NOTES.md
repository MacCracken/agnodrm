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
- `syserr_pack(kind, errno)` encodes `kind << 16 | errno` — zero-alloc, ~6ns.
- `syserr_new(kind, errno, message)` heap-allocates for diagnostics — cold path only.
- `err_from_syscall_ret()` maps known errnos to typed variants.

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
- Inlined Linux x86_64 syscall numbers (`UTIL_` prefix) so the module passes
  a standalone `cyrius check`; no aarch64 peer is tracked.

## udev

- Shells out to `udevadm` for device enumeration.
- Device attributes read from command output are untrusted strings — consumers should validate.

## drm

- Raw `syscall()` ioctl for DRM_IOCTL_VERSION, GET_CAP, MODE_GETRESOURCES.
- **Privilege: read access to /dev/dri/card*.** Usually `video` group.
- Buffer sizes from kernel capped to prevent malicious responses from causing OOM.
- Two-pass ioctl pattern (get sizes, then get data).
- **F-3/F-4 (LOW, 1.5.3), defence-in-depth:** the `/dev/dri` getdents64 walk
  now validates `d_reclen` (a zero value spun forever; an oversized one walked
  past the read window) and scans `d_name` with an explicit bound instead of
  `strlen`. `DRM_IOCTL_VERSION` string lengths are clamped low as well as
  high — they are `__kernel_size_t`, so a value >= 2^63 read back as a
  negative i64 and slipped past the `> 4096` cap.

## netns

- Raw `syscall()` for setns/unshare.
- **Privilege: CAP_SYS_ADMIN** required for namespace operations.
- **Irreversible (unshare):** creates new namespace for calling thread.
- Per-PID nftables temp file instead of fixed path (avoids races).
- nftables buffer increased to 16KB with bounds checking.
- **nftables ruleset is pass-through.** `netns_apply_nftables_ruleset` invokes `nft -f -` with the caller-supplied ruleset string via argv (`exec_vec`, no shell). agnosys does **not** parse or sanitize the ruleset content; the kernel nft surface is exposed to whatever the caller provides. Consumers (nein) must trust their ruleset source. Recent kernel CVEs in this surface include CVE-2026-31407 (conntrack netlink validation) and CVE-2026-23231 (UAF in `nft_chain`); agnosys is on the data path, not the vulnerability sink.
- **F-6 (MEDIUM, 1.5.3): firewall-rule ports are now range-checked.**
  `netns_fw_rule_new` accepts any i64; ports outside 1..65535 were formatted
  into an 8-byte scratch buffer and overflowed it. Out-of-range ports are now
  **skipped** during nftables rendering rather than emitted (such a rule could
  never load). Callers that relied on arbitrary port values will see those
  rules silently omitted.
- **F-7 (LOW, 1.5.3): `netns_validate_config` now rejects `prefix_len < 1`**,
  not just `== 0` — a negative value previously passed validation and
  overflowed a 4-byte format scratch.

## fuse

- Raw fd operations on /dev/fuse.
- **Privilege: access to /dev/fuse** (usually `fuse` group).
- Request body is raw bytes — consumers must parse per-opcode.
- ENODEV from read indicates clean unmount.
- **F-5 (HIGH, 1.5.3): `fuse_parse_proc_mounts` wrote one byte past its heap
  buffer** when `/proc/mounts` filled it (8192 bytes ≈ 90 mount entries, which
  container and snap-heavy hosts reach routinely). Buffer is `8192 + 1` now.
  Third instance of a class already fixed twice (`update_check` F-11 at 1.3.0,
  `agnodrm_read_fd_to_str` at 1.3.1).
- **`/proc/mounts` larger than 8192 bytes is silently truncated** — the parse
  returns a partial mount list, not an error. Pre-existing; consumers needing
  completeness on very large mount tables should not rely on this.

## update

- `atomic_write()`: temp file → fsync → rename → dir sync. Crash-safe.
- `atomic_swap()` uses renameat2(RENAME_EXCHANGE) when available, three-way rename fallback.
- Temp files use PID suffix for uniqueness.
- Cross-filesystem rename will fail (checked via device ID comparison).

## journald

- Unix datagram socket to /run/systemd/journal/socket.
- Journal protocol: `KEY=VALUE\n` for single-line, binary length prefix for multi-line.
- Fields with newline characters in keys are skipped (injection prevention).
- No authentication — any process can write to the journal socket.
- **`journald_query` uses argv-based exec — no shell.** Every filter value (`unit`, `grep`, `since`, `until`, `boot`, `priority`, `lines`) lands in its own `argv[i]` entry via `lib/process.cyr::exec_capture`; journalctl reads the value verbatim, no metacharacter expansion. Consumers passing external input through filter setters are safe from command injection. Audit finding F-1 (HIGH) — fixed in 1.0.1, fuzz coverage at `fuzz/journald_filter.fcyr`.

## bootloader

- Reads /boot/loader/entries/*.conf and /boot/grub/grub.cfg.
- **Privilege: read access to /boot.**
- Kernel cmdline validation uses single-pass tokenizer with hashmap danger lookup.
- **`bootloader_validate_kernel_cmdline` is a DENYLIST, not an authorisation
  boundary.** `Ok(0)` means "no listed parameter matched" — it does **not**
  mean the cmdline is safe. Matching is exact per space-delimited token, plus
  a `rdinit=` prefix rule. An unlisted interpreter, an equivalent spelling, or
  a novel kernel parameter passes. Audit finding F-1 (MEDIUM, 1.5.3) widened
  the list from 21 to 48 entries — adding `rdinit=` (prefix; it was absent
  entirely, and grants the same escape as `init=`), six more `init=`
  interpreters, rescue/emergency targets, and the CPU-mitigation / KASLR /
  LSM downgrades. Known remaining gap: the SysV single-user tokens `S` and `1`
  are **not** matched — a bare `1` is too generic to denylist without false
  positives. Allowlist-based validation is roadmap V2.0.
- **`bootloader_is_dangerous_token` does not match what the validator does.**
  It is a case-insensitive *substring* search; the validator matches *exact
  tokens*. It has no production callers and is retained only because the 1.0
  API surface is frozen. Prefer `bootloader_validate_kernel_cmdline`. Removal
  is roadmap V2.0 (F-2, 1.5.3).

