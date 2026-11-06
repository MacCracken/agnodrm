# 001 — The order of the A/B slot writes

A slot change touches three things that cannot be written together: the state file, the `next-slot` marker, and the
firmware's `BootNext`. A power cut can land between any two. **The order of those writes is the design**, so do not
reorder one without walking the table below. 1.7.2's first repair put the state first everywhere, passed every test,
and a review's injected power cuts found a rollback that booted the bad slot with its record gone.

## What each write means

- **`BootNext`** outranks everything and is spent by the boot that uses it. Nothing here touches `BootOrder`.
- **The marker** is what commits a move. It was written for argonaut to read, but **nothing reads it yet**: at 1.7.3 no
  repo in the workspace reads `next-slot`, emits `agnos.slot=` or creates the `AGNOS-A` / `AGNOS-B` boot entries. This
  document is the design that boot stack has to meet, not a description of one. See the roadmap's 1.9.x.
- **The state file** records what is known: the slot the next boot is meant to reach, the pending image, and whether a
  good slot is behind it.

## The rule

A write that makes a slot **reachable** comes after the record that explains it. A write that makes a good slot
**unreachable**, by erasing the record of it, comes after the next boot is shown to be there.

| Flow | Order | Why |
|---|---|---|
| `update_switch_slot`, forward | state, marker, firmware | Marker first would boot an image the state knows nothing about |
| `update_rollback`, or switching back | marker, firmware, state | State first erases the record while the bad slot still boots |
| `update_apply` | hold the boot, clear and save, `dd`, save pending | The record must be gone before the slot is, and the boot held before the record goes |

`rollback_available` means a switch left a good slot behind. It is set by a switch, never by `update_apply`, which is
how "written but never switched to" stays distinct from "on trial".

## Where a power cut leaves you

`BootNext` is taken first, then the marker. "Fallback" means the state names a slot the host is not running, which
`update_mark_boot_successful` refuses and `update_rollback` squares.

| Flow | Cut after | Next boot | State | Recovery |
|---|---|---|---|---|
| apply | the hold | running slot | unchanged, or a fallback | run it again |
| apply | clear and save | running slot | no pending, no rollback | run it again; `update_switch_slot` refuses the half-written slot |
| apply | during `dd` | running slot | no pending, no rollback | run it again |
| apply | `dd`, before the final save | running slot | no pending | run it again |
| switch | state | old slot | a fallback | `update_rollback` |
| switch | marker | new slot | on trial | none needed |
| rollback | marker | good slot, or the image if a `BootNext` is outstanding | on trial | run it again; if the image boots and confirms, the confirm brings the marker back |
| rollback | firmware | good slot | a fallback | run it again |
| rollback | state | good slot | clean | none needed |

## This table is a test

`tests/tcyr/test_powercut.tcyr` runs these flows rather than trusting the table. Each runs once whole, which is checked
against what it must leave behind, then again in a child that dies at write 1, 2, 3, and so on until one finishes. After
each cut a model of the firmware boots the host (`BootNext`, then the marker, then `BootOrder`), and the test asks what the
rule promises: the boot reached a whole image the state can explain, a confirm can only name what booted, `update_rollback`
settles the host, and running the call again finishes it or refuses without changing anything. Then it cuts those
recoveries too, at each of their writes. A cut in the `dd` window also runs with the slot half-written.

The cuts come from a counter, `_update_cut`, that every durable write passes: the state and the marker in
`_update_commit_tmp`, the firmware and the slot at their calls. So a new write in those places is cut with no change to the
test, and the count pinned for each flow fails until someone has walked it here. A write that goes anywhere else needs its
own `_update_cut`. Those calls exist only under `#define AGNODRM_POWERCUT`, and only that test sets it and defines the
function, so no shipped build or bundle holds a way to stop mid-update, and the seam adds no bytes to a binary.

## Firmware that cannot answer

`BootNext` outranks the marker, so an update must not write a slot `BootNext` may be aimed at, and a rollback must not
erase its record while `BootNext` may still aim at the bad slot. So `update_apply` and `update_rollback` refuse when
`efibootmgr` fails on an EFI host. No EFI, or no `efibootmgr`, means no `BootNext` this library could have set.

There is no exception, and two were tried. "The cmdline names the target" also holds for a switch made this boot, not
yet rebooted, with `BootNext` armed. "A boot has been counted since the switch" also holds after
`update_mark_boot_attempt` runs in the same boot, and a repeated switch re-arms `BootNext` without resetting the count.
Either way a rollback reported `Ok` with the next boot still going to the bad slot. Proving a reboot would take the
kernel's `boot_id` in the state file, and it would buy availability on a host that is already broken.

So on an EFI host with a failing `efibootmgr`, a rollback or an update refuses until the tool works. That is safe to wait
out: the marker has moved to the good slot, the record stays, and running the call again finishes it.

## What this does not cover

- A state file written by 1.7.1's `update_apply` has `rollback_available` set with nothing switched, and reads as a
  trial. Nothing in the workspace has ever run that code.
- Nothing updates `BootOrder`, so whether a slot stays selected past its one `BootNext` depends on a reader of the marker,
  which does not exist yet.
- The table assumes `fsync` means what it says on the slot's storage.
- The test holds the rule, not each line of the order. Going forward, the marker and the firmware can swap without a row
  going bad: `BootNext` only takes the host onto a trial the state already records. It is a model of the boot order, not
  a power cut, and nothing in it touches real firmware or a real block device.
