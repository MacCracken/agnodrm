# cyrius `api-surface` — tooling follow-ups (all items resolved)

**Status:** RESOLVED — all three items closed across
cyrius 5.9.9 → 5.9.12 → 5.9.13. Verified by agnosys 1.0.12;
`scripts/check-api-surface.sh` reduced to a four-line wrapper
around `cyrius api-surface --scope=project --snapshot=...`.
**Filed:** 2026-05-06
**Resolved:** 2026-05-06
**Reporter:** agnosys 1.0.11 (during V1.1.0 closeout, evaluating
`cyrius api-surface` as a replacement for our local
`scripts/check-api-surface.sh`)
**agnosys version observed:** 1.0.11
**cyrius version active at filing:** 5.9.7
**cyrius version with full fix:** 5.9.13

## Status timeline

| Item | Status |
|---|---|
| Derive-emitted accessors invisible to `cyrius api-surface` | **RESOLVED in cyrius 5.9.9** — verified by re-running the original reproducer (`/tmp/cyrius-api-surface-derive-blind/`); all four of `widget_x/1`, `widget_set_x/2`, `widget_y/1`, `widget_set_y/2` now appear in the snapshot. On agnosys's 20-module source tree, the cyrius output for agnosys-prefixed entries is byte-identical to our shell-script's 721-entry snapshot. |
| Scanner walks stdlib by default; no project-scope flag | **RESOLVED in cyrius 5.9.12** — `cyrius api-surface --update --scope=project` now writes a project-only snapshot. Verified byte-identical to our shell-script's 721-entry output: `diff <(sort docs/api-surface.snapshot) <(sort docs/development/api-surface-1.0.snapshot)` is empty. |
| `--snapshot=PATH` flag silently ignored | **RESOLVED in cyrius 5.9.13** — verified: `cyrius api-surface --update --snapshot=/tmp/agnosys-test.snap` writes to the requested path, default `docs/api-surface.snapshot` is not touched. Combined invocation `cyrius api-surface --update --scope=project --snapshot=docs/development/api-surface-1.0.snapshot` produces a 721-entry snapshot byte-identical to the previous shell-script output. |

Net for agnosys: with two of three items now resolved, the only
gate to replacing `scripts/check-api-surface.sh` with a one-liner
`cyrius api-surface --scope=project` is the snapshot-path question.
Either `--snapshot=PATH` lands upstream and the script becomes
a one-liner wrapper, OR agnosys moves its snapshot to the
hardcoded `docs/api-surface.snapshot` path (a doc-tree rename
that drops the `-1.0` freeze marker from the filename but
matches cyrius's default convention).

**Local reproducer:** [`/tmp/cyrius-api-surface-derive-blind/`](/tmp/cyrius-api-surface-derive-blind/)
— self-contained. Contains:

```
README.md            ← full diagnostic + repro recipe (covers all 3 items)
minimal_repro.cyr    ← 16-line struct + derive + 2 callers
cyrius.cyml          ← stub manifest so `cyrius api-surface` runs
src/widget.cyr       ← copy of the source (api-surface walks src/*.cyr)
```

## Item 1 — derive-emitted accessors invisible (RESOLVED 5.9.9)

### Original symptom (5.9.7)

`cyrius api-surface` walked `^fn name(...)` declarations only.
Public functions emitted by `#derive(accessors)` were not
recorded in the generated snapshot, even though they were real,
callable, public surface.

### 5.9.9 verification

```sh
cd /tmp/cyrius-api-surface-derive-blind
rm -f docs/api-surface.snapshot widget
cyrius api-surface --update     # snapshot updated: 47 public fns
grep widget docs/api-surface.snapshot
```

Now produces (5.9.9):

```
widget::main/0
widget::widget_new/2
widget::widget_set_x/2
widget::widget_set_y/2
widget::widget_x/1
widget::widget_y/1
```

The four derive-emitted accessor entries are now present. ✅

### agnosys-side verification

```sh
cd /home/macro/Repos/agnosys
rm -f docs/api-surface.snapshot
cyrius api-surface --update     # snapshot updated: 1113 public fns
diff <(grep -E "^(audit|bootloader|certpin|dmverity|drm|error|fuse|ima|journald|logging|luks|mac|netns|pam|secureboot|security|syscall|syscall_aarch64_linux|syscall_arch|syscall_x86_64_linux|tpm|udev|update)::" docs/api-surface.snapshot | sort) \
     <(grep -E "^(audit|bootloader|certpin|dmverity|drm|error|fuse|ima|journald|logging|luks|mac|netns|pam|secureboot|security|syscall|syscall_aarch64_linux|syscall_arch|syscall_x86_64_linux|tpm|udev|update)::" docs/development/api-surface-1.0.snapshot | sort)
```

Diff is empty. The cyrius scanner agrees with our shell-script's
walker on every agnosys-prefixed entry, including all 386
derive-emitted accessor pairs. ✅

## Item 2 — `--snapshot=PATH` flag silently ignored (Open)

### Documented contract

vidya `content/cyrius/language/tooling.cyml`, `cyrius_cli` entry:

```
== `cyrius api-surface` FLAGS ==
  --update           Regenerate `docs/api-surface.snapshot` from
                     current source. No flag → diff against
                     committed snapshot, exit 1 on drift.
  --snapshot=PATH    Diff against an alternate snapshot file.
```

### Observed (5.9.12)

```sh
cd /home/macro/Repos/agnosys
rm -f docs/api-surface.snapshot /tmp/agnosys-test.snap
cyrius api-surface --update --snapshot=/tmp/agnosys-test.snap
# → snapshot updated: 1113 public fns written to docs/api-surface.snapshot
ls /tmp/agnosys-test.snap docs/api-surface.snapshot
# → ls: cannot access '/tmp/agnosys-test.snap': No such file or directory
# → docs/api-surface.snapshot
```

The flag is parsed (no "unknown option" error) but the value is
discarded. The command still writes to the hardcoded
`docs/api-surface.snapshot` regardless of `--snapshot=PATH`.

(Note: the "snapshot missing" / flag-ordering oddity observed
under 5.9.9 — where `--snapshot=X --update` errored with
"snapshot missing" — is no longer reproducible on 5.9.12. The
parser accepts both flag orderings; only the path-redirection
behavior remains unimplemented.)

### Why this matters for agnosys

agnosys's snapshot lives at
`docs/development/api-surface-1.0.snapshot` (the 1.0 freeze
location, established before `cyrius api-surface` existed). With
`--snapshot=PATH` honored, our shell script could be replaced by
`cyrius api-surface --snapshot=docs/development/api-surface-1.0.snapshot`
plus a stdlib filter. Without it, every invocation pollutes
`docs/` with a regenerated `api-surface.snapshot` file the script
has to clean up after.

## Item 3 — scanner walks stdlib; no project-scope flag (RESOLVED 5.9.12)

cyrius 5.9.12 ships `--scope=project` honored by the snapshot
writer. Verification on agnosys's full source:

```sh
cd /home/macro/Repos/agnosys
rm -f docs/api-surface.snapshot
cyrius api-surface --update --scope=project
# → snapshot updated: 721 public fns written to docs/api-surface.snapshot

head -3 docs/api-surface.snapshot
# → audit::audit_add_rule/2
# → audit::audit_agnos_log/3
# → audit::audit_build_nlmsg/3

diff <(sort docs/api-surface.snapshot) \
     <(sort docs/development/api-surface-1.0.snapshot)
# (empty — byte-identical to our shell-script's snapshot)
```

The flag does what the issue asked for: stdlib entries
(`alloc::`, `string::`, `vec::`, `fmt::`, `assert::`, `tagged::`,
`fnptr::`, `hashmap::`, `process::`, `fs::`, `io::`, `str::`,
`syscalls::`) are excluded; only the project-side surface is
emitted. The snapshot now reflects the project's public API
exactly, with no stdlib-churn risk.

Both flag orderings (`--update --scope=project` and
`--scope=project --update`) work on 5.9.12.

## Suggested upstream investigation

### Item 2 (`--snapshot=PATH`)

1. Confirm whether the flag is parsed but discarded, or just
   never wired into the snapshot path resolver. The fact that
   `cyrius api-surface --snapshot=X --update` doesn't error on
   the unknown flag suggests the parser accepts it but the
   handler doesn't read it.
2. Once honored, the same `PATH` value should drive both
   `--update` (write target) and the bare-diff mode (read target).

### Item 3 (project-scope flag) — DONE

(Resolved in 5.9.12, see Item 3 section above.)

The reference notes from when this was open:

1. The scanner already knows which files are project-side
   (`src/*.cyr`) vs. stdlib (`lib/*.cyr` resolved through
   `[deps] stdlib`) — these are different file paths and ingest
   sites. A simple "skip if path matches `lib/*.cyr`" branch in
   the snapshot writer should suffice.
2. The flag could default to project-only (most consumer projects
   want this) with `--scope=all` to opt back into stdlib walking
   for the few cases where it matters (cyrius's own self-hosted
   surface check, perhaps).
3. Worth asking whether stdlib should have its own snapshot file
   shipped with the toolchain (a `lib/api-surface.snapshot`
   maintained by the cyrius project itself), so consumers can
   diff against a known-good baseline instead of recomputing on
   every CI run. Out of scope for this issue, but adjacent.

## References

- `/tmp/cyrius-api-surface-derive-blind/README.md` — full reproducer (covers all 3 items)
- agnosys `scripts/check-api-surface.sh` — workaround; header comment documents what's needed before this can be replaced with a one-liner `cyrius api-surface` wrapper
- agnosys `docs/development/api-surface-1.0.snapshot` — 721 entries (project-only)
- vidya `content/cyrius/language/tooling.cyml` —
  `cyrius_cli` entry documenting the `--snapshot=PATH` flag that
  is not yet honored
