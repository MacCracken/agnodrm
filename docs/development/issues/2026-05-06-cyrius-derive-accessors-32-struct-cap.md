# cyrius `#derive(accessors)` silently breaks past 32 structs in a single compilation unit

**Filed:** 2026-05-06
**Reporter:** agnosys 1.0.10 V1.1.0 migration (slot 14 — pam/netns/update batch)
**agnosys version observed:** 1.0.10 + in-flight 1.0.11 patch attempt
**cyrius version active:** 5.9.3 (also reproduced under 5.9.1)
**Severity:** HIGH — silent breakage of derive-emitted public API
at a fixed cumulative-struct threshold; downstream binaries SIGILL
at runtime when the missing accessor is reached. Build still
succeeds with only a `warning:` line.

**Local reproducer:** [`/tmp/cyrius-derive-truncation/`](/tmp/cyrius-derive-truncation/)
— self-contained, ~5 KB. Contains:

```
README.md            ← full diagnostic + repro recipe
minimal_repro.cyr    ← agnosys-flavored 37-struct reproducer
threshold_probe.sh   ← sweeps N=28..36 to bracket the cap
```

The reproducer files are intended to be copied into the cyrius repo
as a regression case once the upstream fix lands.

## Summary

Once a single compilation unit contains **33 or more
`#derive(accessors)` structs**, cyrius's derive emitter
silently misbehaves on the 33rd+ struct:

- **Mode 1 — abstract-name probe (clean truncation cap).** The 33rd
  struct's accessors are simply not emitted to the fn table. Build
  warns "undefined function 'X'" for every call site referencing
  them. The cap is an exact threshold of **32 derive structs**.
- **Mode 2 — realistic mixed-length names (agnosys's flavor).**
  Derive emits accessors with **corrupted prefixes** — the first
  ~8 characters dropped from the struct name, OR the field name
  truncated to its last 2 chars. Examples observed in agnosys:

  | Expected fn | Emitted fn (in dead-code report) |
  |---|---|
  | `update_state_boot_count` | `tate_boot_count` |
  | `update_state_set_boot_count` | `tate_set_boot_count` |
  | `update_state_set_slot` | `tate_slot` (clobbered further) |
  | `fuse_mount_mountpoint` | `fuse_mount_nt` |
  | `fuse_mount_set_mountpoint` | `fuse_mount_set_nt` |

  The truncation pattern is not consistent — sometimes the struct
  prefix is mangled, sometimes the field suffix, sometimes the
  whole accessor is dropped. This suggests some kind of shared
  scratch buffer / aliasing inside the emitter rather than a clean
  length-cap.

In **both modes** the build succeeds with only `warning:` output.
cyrius stubs undefined fn references, so `cyrius build` exits 0.
The resulting binary SIGILLs (exit 132) at runtime when control
reaches the missing accessor.

## Reproduction

### Setup

```sh
cyrius --version    # cyrius 5.9.3 (also reproduces under 5.9.1)
cd /tmp/cyrius-derive-truncation
```

### 1. Bracket the threshold (synthetic, Mode 1)

```sh
./threshold_probe.sh
```

Output observed:

```
cyrius version: cyrius 5.9.3

Sweeping N from 28 to 36 (5 fields per struct):
  N=28  undefined-fn warnings: 0
  N=29  undefined-fn warnings: 0
  N=30  undefined-fn warnings: 0
  N=31  undefined-fn warnings: 0
  N=32  undefined-fn warnings: 0
  N=33  undefined-fn warnings: 1
  N=34  undefined-fn warnings: 1
  N=35  undefined-fn warnings: 2
  N=36  undefined-fn warnings: 2
```

Cap is exactly **N=32**. The 33rd derive struct's accessors fail
to emit; each subsequent struct adds more failed emissions.

### 2. Realistic-name reproducer (Mode 2)

```sh
cyrius build minimal_repro.cyr minimal_repro 2>&1 | head -25
./minimal_repro; echo "exit=$?"
```

Build output (truncated):

```
warning: undefined function 'update_state_set_slot'
warning: undefined function 'update_state_set_version'
warning: undefined function 'update_state_set_pending'
warning: undefined function 'update_state_set_rollback_available'
warning: undefined function 'update_state_set_boot_count'
warning: undefined function 'update_state_slot'
warning: undefined function 'update_manifest_set_version'
warning: undefined function 'update_manifest_version'
warning: undefined function 'update_file_set_sha256'
warning: undefined function 'update_file_sha256'
warning: undefined function 'fuse_mount_set_fstype'
warning: undefined function 'fuse_mount_fstype'
error: undefined function 'update_state_set_slot' (will crash at runtime)
...
```

Run:

```
exit=132
```

The dead-code report shows the truncated emissions:

```sh
cyrius build minimal_repro.cyr minimal_repro 2>&1 \
    | grep "dead: " \
    | grep -vE "^  dead: (sys_|str|mem|alloc|print_|fmt|vec|hashmap|map_|sb_|sb |signal|test_|epoll|inotify|timer|WEX|WIF|WT|fncall|arena|sigset|err)" \
    | head -10
```

```
  dead: tate_slot
  dead: tate_set_slot
  dead: tate_version
  dead: tate_set_version
  dead: tate_pending
  dead: tate_set_pending
  dead: tate_rollback_available
  dead: tate_set_rollback_available
  dead: tate_boot_count
  dead: tate_set_boot_count
```

The `tate_` prefix is `update_state` with the first 8 chars
(`update_s`) dropped — derive registered fns under those corrupted
names. The original call-site references look up the full names,
don't match anything, and stub out as undefined.

## Diagnostic

`CYRIUS_STATS=1 cyrius build` shows the fn-table is **not** the
constraint:

```
cyrius stats:
  fn_table:    1072 / 4096
  identifiers: 34500 / 131072
  var_table:   552 / 8192
  fixup_table: 3049 / 262144
  string_data: 16583 / 2097152
  code_size:   304016 / 1048576
```

`cyrius capacity --check` also reports clean ("ok (all caps under
85%)"). So the bug is not a capacity limit being hit — it's a
specific bug in the derive emitter.

The threshold of exactly 32 strongly suggests an internal
fixed-size table or buffer used by the derive pass:

- A `struct_count[32]` slot array would explain the 33rd-struct
  drop.
- A reused name-construction buffer that doesn't reset between
  emits would explain the prefix corruption (Mode 2).

The fact that the build still **succeeds** is itself a problem —
silently stubbing derive-emitted accessors as undefined fns
masks a genuine emitter bug. Promoting "undefined fn from derive
emit" to a hard error would catch this at build time rather than
runtime.

## Scope of impact for agnosys

- **`src/main.cyr`** (production library): **unaffected** — only
  includes 3 src files (error, syscall, security), well below the
  32-struct threshold.
- **`dist/agnosys.cyr`** (consumer bundle): **unaffected** —
  distlib concatenates source; each consumer compiles only the
  subset they need, well below the threshold.
- **`tests/tcyr/test_integration.tcyr`** (validation): **breaks**
  — pulls all 20 modules into one TU. Once cumulative derive count
  crosses 32, the test build emits undefined-fn warnings and the
  test binary SIGILLs.

agnosys 1.0.10 ships clean at 26 derive structs across 13
struct-bearing modules (the test build stays under the threshold).
The remaining 3 modules — pam (3 structs), netns (4), update (4)
— add 11 derives, pushing the test compilation to 37 structs and
triggering the bug.

## Status of agnosys V1.1.0

- 13 of 16 struct-bearing modules migrated (mac, fuse, drm,
  bootloader, dmverity, luks, certpin, udev, journald, audit, ima,
  tpm, secureboot). All shipped 1.0.6–1.0.10 cleanly.
- The 3 remaining modules (pam, netns, update) are deferred until
  upstream cyrius lifts the 32-struct cap or fixes the derive
  emitter to handle larger counts cleanly.
- This issue document, the local reproducer, and a planned cyrius
  bug filing are the durable record.
- agnosys 1.0.11 ships as the discovery patch — no source
  migrations, this issue file added, roadmap updated to defer the
  3 remaining modules to a future V1.1.x patch when cyrius has the
  fix.

## Workarounds considered

1. **Split the test driver into per-module files.** `cyrius test`
   auto-discovers `tests/tcyr/*.tcyr`. Per-module tests would each
   include only one module's src plus stdlib, keeping derive count
   well below 32. This is a viable workaround but is non-trivial
   work — moving 234 assertions across 20 module-specific test
   files, each with its own includes/setup. Tracked as a separate
   roadmap item; not blocking 1.1.0.
2. **Reduce derive count by reverting some less-valuable
   migrations.** Rejected — the migrations are the V1.1.0 deliverable.
3. **File upstream and wait.** Chosen path. Discovery patch
   (1.0.11) records the issue durably; future V1.1.x patch
   completes the remaining 3 modules once cyrius fixes the emitter.

## Suggested upstream investigation

1. The exactly-32 threshold strongly suggests a fixed-size slot
   array in the derive pass. Search for `[32]` or `MAX_DERIVE`
   constants in the derive emitter source.
2. Mode 2's prefix truncation suggests a shared scratch buffer
   used by both the struct-name and field-name emit paths is
   getting reused across emissions without proper length reset.
3. The undefined-fn warnings being merely warnings (not errors)
   when the underlying source is a derive directive is a defect
   in itself — derive-emitted fn references that fail to resolve
   are by definition compiler bugs, not user errors, and should
   fail the build.

## References

- `/tmp/cyrius-derive-truncation/README.md` — full reproducer
- `/tmp/cyrius-derive-truncation/minimal_repro.cyr` — Mode 2 case
- `/tmp/cyrius-derive-truncation/threshold_probe.sh` — Mode 1 case
- agnosys CHANGELOG `[1.0.11]` — discovery + defer narrative
- agnosys `docs/development/roadmap.md` V1.1 — deferred slots
- vidya `content/cyrius/language/features.cyml` —
  `derive_str_fields` entry documenting the `#derive(accessors)`
  contract that this bug violates
