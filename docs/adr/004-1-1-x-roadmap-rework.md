# ADR-004 — 1.1.x roadmap rework: language-feature adoption first, ecosystem second

**Status:** Accepted (2026-05-06, planning for 1.1.0)
**Context window:** cyrius 5.9.1 / agnosys 1.0.5 → 1.1.0
**Supersedes:** Phase 8 backlog ordering (8.1–8.6) from 1.0.1
**Superseded by:** —

## Context

The agnosys 1.0 freeze landed at cyrius 5.7.6 (April 2026). Between then and the
1.0.5 toolchain bump (cyrius 5.9.1, May 2026), a substantial set of language
features shipped that didn't exist when the agnosys port was written:

- `defer { }` — per-flag, exit-path-safe LIFO cleanup (5.8.x)
- First-class slices `[T]` / `slice<T>` with bounds-checked `s[i]` and `.ptr` / `.len` dot-syntax (5.8.16+)
- Tagged-union sum types `enum Result<T, E> { Ok(T), Err(E) }` (5.8.21–5.8.26)
- Exhaustive `match` coverage check with duplicate-arm dedup (5.8.22 / 5.8.25)
- `secret var` + `ct_eq` / `ct_select` / `mulh64` builtins (5.8.x)
- Multi-width types `i8/i16/i32/i64/u128` with width-correct codegen on locals AND struct fields (5.8.16 layout-flip)
- `#derive(accessors)` and `#derive(Serialize)` with single-pass JSON deserializer (5.8.x)
- `#ifplat PLAT` / `#endplat` sugar over `#ifdef CYRIUS_ARCH_*` (5.8.x)
- Compound assignment, expression-position comparisons, native multi-return, saturating/checked overflow ops (`+|`, `+?`)
- Attributes — `#must_use`, `@unsafe`, `#deprecated`
- `#regalloc` per-fn opt-in (default-on at 5.6.24)

Agnosys today carries ~635 raw `store64`/`load64` offset-arithmetic sites,
35 `var buf[N]` declarations, 10 modules pulling `lib/tagged.cyr`, and a
hand-rolled `certpin_ct_streq` — all patterns that have direct, compiler-backed
replacements in 5.9.x. The 1.0.1 roadmap's Phase 8 (8.1–8.6) was authored
against the 5.7.x feature surface and predates most of these.

cyrius 5.9.x is the maintenance line — bug fixes, improvements, and potential
optimizations only. New features land slowly. Agnosys 1.1.x can plan against
the 5.9.1 surface as a stable target without expecting per-patch toolchain
chase.

## Decision

**Restructure Phase 8 into a 1.1.x / 1.2.x / 1.3+ track:**

- **1.1.x — language-feature adoption.** 1.1.0 headline is `#derive(accessors)`
  migration (the existing 8.1, mechanical-but-invasive across every struct).
  1.1.1–1.1.7 layer the new 5.8/5.9.x features in priority order: `defer`,
  `secret var`, exhaustive match, tagged-union Result, multi-width struct
  fields, slice migration, `#derive(Serialize)`. Each slot ships as a patch
  against 1.1; 1.1.0 ships as the closeout of the accessor migration.
- **1.2.x — ecosystem.** 1.2.0 headline is multi-profile `cyrius distlib`
  (the existing 8.2). 1.2.1–1.2.4 absorb the existing 8.3 (`#ifplat`),
  8.5 (capability map), 8.4 (consumer integration CI), plus a new slot
  for `#deprecated` adoption.
- **1.3+ — cross-repo.** 8.6 (state.md release post-hook) lands when the
  agnosticos meta-tooling supports it; not blocking on agnosys itself.

**Min-cyrius pin policy:** 1.1.x stays at 5.9.x for the duration unless a
specific bug fix or optimization in a later 5.9.y release matters. No routine
per-patch pin chase.

## Alternatives considered

**Alt A — keep 8.1–8.6 as-is, ignore the new feature surface.** Rejected:
the existing roadmap is correct but stale; shipping `#derive(accessors)`
without also taking `defer` / tagged unions / `secret var` would mean a
second mechanical refactor pass within 1.x. Better to bundle the feature
adoption into one minor cycle.

**Alt B — multi-profile distlib (8.2) as the 1.1.0 headline.** Rejected
in this round; the consumer-facing win is real but the language-adoption
work is *internal* refactoring that interacts with every other 1.1.x slot
(accessor migration changes the struct shape that defer/slice/Serialize
all touch). Doing the internals first means 1.2.0's profile bundles ship
against the polished surface, not the half-migrated one. User confirmed
the language-first ordering on 2026-05-06.

**Alt C — interleave 1.1.x and 1.2.x slots.** Rejected: clean theme
boundaries make the closeout pass legible. A minor cycle with one
coherent narrative ("language adoption" or "ecosystem") is easier to
review, document, and bench-diff than a mixed cycle.

## Consequences

**Positive:**
- 1.1 has a single coherent theme (language-feature adoption) — easy to
  describe in CHANGELOG, easy for consumers to understand the upgrade.
- Each 1.1.x patch is a small bite (per CLAUDE.md "Task Sizing": large
  effort = small bites). No 1.1.x slot is large enough on its own to risk
  a 3-attempt rabbit hole.
- API surface stays additive across all of 1.1.x (accessors are added,
  Serialize fns are added; nothing is removed). The 1.0 snapshot file
  gains entries; existing entries don't drift.
- The audit-derived security fixes from 1.0.1 are not on this critical
  path — every 1.1.x slot is correctness-equivalent to 1.0.x by
  construction (refactor without behavior change).

**Negative:**
- 1.1.x has 8 patch releases planned (1.1.0 through 1.1.7). That's a lot
  of release cycles in a single minor. Each ships under the closeout
  discipline (CLAUDE.md), so the overhead is real. Mitigation: most
  slots are mechanical and bench-parity-gated; closeout reduces to "did
  bench drift?" + "did API surface drift?" for those.
- Consumer-facing improvements (multi-profile distlib, capability map)
  wait for 1.2.x. kavach will continue pulling 324 KB through all of
  1.1.x even though it only uses ~50 KB. Acceptable since consumers
  aren't blocked, just inefficient.
- 1.1.4 (tagged-union migration in error.cyr) touches the most-imported
  module in agnosys. If the byte-layout assumption (arity-1 sum types
  produce byte-identical output to lib/tagged.cyr) breaks for any reason,
  every consumer pulls a different Result shape. Mitigation: bench parity
  + API surface check + per-consumer build verification before tagging.

## Detection / regression guard

- **Bench history.** Each 1.1.x slot must produce a clean
  `scripts/bench-history.sh` snapshot — any regression > 5% in the
  30-bench suite blocks the patch.
- **API surface.** `scripts/check-api-surface.sh` runs in CI; additive
  changes use `--update`, removals or arity changes are blocked at the
  CHANGELOG `Breaking` gate.
- **Min-cyrius pin.** `cyrius.cyml [package].cyrius` is the single source
  of truth; any 1.1.x slot that *requires* a specific 5.9.y bug fix
  documents it in CHANGELOG `Changed`.

## References

- `docs/development/roadmap.md` — V1.1 / V1.2 / V1.3 sections (this rework)
- `docs/development/state.md` — current binary size, test counts, bench baseline
- `docs/audit/2026-04-26-audit.md` — prior P(-1) findings (all closed in 1.0.1, not in scope here)
- vidya `content/cyrius/language/features.cyml` — canonical reference for the cyrius features used as input
- CHANGELOG `[1.0.5]` — toolchain bump to 5.9.1 that opened this surface
- CLAUDE.md "Task Sizing" — large-effort items as small bites
