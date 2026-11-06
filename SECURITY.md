# Security Policy

## Scope

Agnodrm is the AGNOS device / DRM model: udev enumeration and DRM/KMS device-node access on a small error and util layer, plus a deferred Linux group (journald, netns, bootloader, update, fuse). Most public functions wrap a device or kernel interface, run a host tool with an explicit argv, or parse what one reports. The trust, sandboxing, syscall and logging code of the former agnosys moved to sigil, kavach, aegis, cyrius and sakshi at 1.4.4, and is out of scope here.

## Attack Surface

| Area | Risk | Mitigation |
|------|------|------------|
| Subprocess calls | Command injection | An explicit argv and an empty env, with no shell anywhere. The library's own calls use absolute paths; `netns_run_ip`, `agnodrm_run_capture` and `agnodrm_run_checked` are public and run the argv they are given |
| udev parsing | Hostile text from `udevadm` | A repeated `P:` or a `..` path is refused. A device can still hide its own block or forge one through a value holding a blank line, so a listing is not proof a device exists. A rule validator denies `RUN`, `PROGRAM` and friends |
| DRM ioctls | A non-DRM node, an interrupted ioctl | A node must be a character device that answers the version ioctl; bounded retry on `EINTR` |
| journald | Field forgery by newline, a `--grep` that never ends | The protocol's binary form for any value with a newline; a caller's extra fields cannot restate a reserved key, which is silently dropped; a 60 s idle deadline on queries |
| netns | Rule loss or injection in nftables | Strict field validators; a ruleset is rendered whole or not at all, into an exclusive temp file. `netns_apply_nftables_ruleset` applies any string it is handed, so render through the policy API |
| Boot entries | Dangerous cmdline tokens, an entry that hides its cmdline | A denylist validator, which is a hygiene check and not a boundary. `bootloader_entry_boot_kind` says what an entry names to boot, and only for `linux` is `options` known to be the whole command line. Entry files are read as well as `bootctl`, since the two disagree about what is an entry |
| A/B update | A corrupt image, a power cut mid-update | sha256 against the manifest while `verify` is on, the default; a fixed write order, walked at every write against a model of the boot, never on real firmware. **The manifest is not signed, so a forged image passes.** Nothing refuses an older image, and the slot is not read back after `dd` |
| Temp files | A planted symlink redirecting a write | Exclusive creation through `agnodrm_tmp_create`, with `O_CLOEXEC` on Linux |
| FUSE | A mount helper taken from the argument | `fuse_type` must be absolute, and is the caller's to trust. Mount refuses a leading `-` on the device or mountpoint, and unmount passes `--`. `extra_opts` is not validated, and sshfs's `-o ssh_command=` runs a program |

## Supported Versions

| Version | Supported |
|---------|-----------|
| 1.x, latest minor | Yes |
| < 1.0 | No |

## Known Limits

- **Only `journald_query` has a deadline.** A hung `udevadm`, `bootctl`, `ip` or `dd` blocks its caller forever.
- **`update_check` reads only `version`.** A manifest's file list is not parsed, so the hash `update_apply` checks is whatever
  `update_file_new` was given.

## Reporting a Vulnerability

Please report security issues to **security@agnos.dev**.

- Acknowledgement within 48 hours
- 90-day coordinated disclosure
- Do not open public issues for vulnerabilities

## Design Principles

- **Device access at the boundary.** Every module wraps a specific device or kernel interface, and policy lives in consumers. The exceptions are fixed: the firewall renderer always accepts `established,related` and loopback, and the update flow has a fixed staging directory.
- **Memory.** Results stay in a bump heap for the life of the process, and small fixed buffers do too, so a long-lived poller grows. Large working buffers are scratch that goes back on Linux. Nothing large sits in static data.
- **Packed errors on hot paths** (`drm_syserr_pack`, zero allocation), heap errors on cold paths (`drm_syserr_new`, carries a diagnostic string).
- **External sizes are capped or read whole.** A capture that does not fit is retried larger or refused, and is not cut short and treated as complete.
- **Parsers reject before they dereference.** A bootloader list that cannot be complete is an `Err`, since an entry a caller cannot see is one it cannot validate. The udev, DRM, FUSE and journald lists skip what they cannot parse and stop at the caller's capacity, so a count equal to it may mean more.
- **Module-prefixed functions** to keep the global namespace apart as consumers mix modules. `is_syscall_err`, `result_print_err` and `wrap_syscall` are the exceptions, and they do collide with sigil's.
- **Fuzz harnesses in `fuzz/`** stress the main parsers with malformed input, on both arches, in CI. Five parsers have none yet: see the roadmap.
- **A green suite is not proof.** Repairs to a parser or state machine are mutation-tested and put in front of an independent review.

## Per-Module Security Notes

See [docs/SECURITY-NOTES.md](docs/SECURITY-NOTES.md) for detailed per-module considerations (privileges required, irreversible operations, TOCTOU hazards, sharp edges).
