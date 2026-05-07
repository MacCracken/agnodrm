# cyrius `lib/ct.cyr` — `ct_eq_bytes` missing from stdlib

**Status:** RESOLVED in cyrius 5.9.18 — `lib/ct.cyr` now ships
`ct_eq_bytes(a, b, n)` with the exact XOR-accumulate body
proposed in this issue. The doc-comment in the upstream stdlib
even credits the agnosys filing. Verified by agnosys 1.1.3:
`certpin_ct_streq` body shrunk from a 16-line hand-roll to a
length-check + delegation into `ct_eq_bytes`; bench parity
confirmed across all 4 certpin benches.
**Filed:** 2026-05-06
**Resolved:** 2026-05-06
**Reporter:** agnosys 1.1.2 (during V1.1.2 evaluation —
`secret var` + `ct_eq` builtin in certpin)
**agnosys version observed:** 1.1.1
**cyrius version active at filing:** 5.9.14
**cyrius version with fix:** 5.9.18
**Severity at filing:** LOW — duplication, not correctness. Each
consumer hand-rolled a correct constant-time byte-equality
primitive; the duplication was the cost.

**Local reproducer:** [`/tmp/cyrius-ct-eq-stdlib/`](/tmp/cyrius-ct-eq-stdlib/)
— self-contained, ~1 KB. Contains:

```
README.md            ← full diagnostic + suggested upstream addition
minimal_repro.cyr    ← shows ct_select resolves; ct_eq_bytes warns "undefined"
```

## Summary

`lib/ct.cyr` ships exactly one helper today:

```
fn ct_select(cond, a, b)    — branchless select
```

The complementary primitive — constant-time byte-array equality —
is not in stdlib. Each downstream project that needs it
hand-rolls the same canonical XOR-accumulate:

| Project | Site | Signature |
|---|---|---|
| sigil | `lib/sigil.cyr:1316` | `fn ct_eq(a, a_len, b, b_len)` |
| sigil | `lib/sigil.cyr:1332` | `fn ct_eq_32(a, b)` (32-byte wrapper) |
| agnosys | `src/certpin.cyr:120` | `fn certpin_ct_streq(a, b)` (cstring variant) |

## Reproduction

```sh
cd /tmp/cyrius-ct-eq-stdlib
cyrius build minimal_repro.cyr minimal_repro 2>&1 | grep -E "warning:|error:"
```

Expected:

```
warning: undefined function 'ct_eq_bytes'
error: undefined function 'ct_eq_bytes' (will crash at runtime)
```

`ct_select` (the one helper that IS in `lib/ct.cyr`) resolves and
runs cleanly in the same harness, confirming the gap is specific
to the equality primitive.

## Why this matters for agnosys V1.1.2

agnosys's V1.1.2 roadmap slot was scoped as:

> Replace hand-rolled `certpin_ct_streq` (src/certpin.cyr:117)
> with cyrius's compiler-backed `ct_eq` builtin and `secret var`
> annotation on pin slots.

Verification on cyrius 5.9.14:

1. **`ct_eq` is not a compiler builtin.** `cyrius build` of a
   harness calling `ct_eq(a, b)` (or `ct_eq(a, alen, b, blen)`)
   reports "undefined function" and the binary SIGILLs at runtime.
2. **`lib/ct.cyr` does not contain a `ct_eq*` helper** — only
   `ct_select`.
3. **`secret var` requires array form.** `secret var key = 0;`
   (scalar) is rejected at compile time with
   `error: secret requires array declaration: secret var buf[N]`.
   Pin storage in certpin flows through cstring pointers across
   struct boundaries (`certpin_entry.pins_arr → vec of Str
   pointers → individual heap-allocated cstrings`), which doesn't
   fit the array-only `secret var` contract.

The agnosys-side hand-rolled `certpin_ct_streq` is correct (the
canonical XOR-accumulate; no data-dependent branches), but the
slot's premise — "swap to the upstream primitive" — has nothing
to swap to.

agnosys 1.1.2 ships as a deferral. When `ct_eq_bytes` lands in
`lib/ct.cyr`, certpin's hand-roll becomes a one-line wrapper and
the slot re-opens as a code change.

## Suggested upstream addition

Add to `lib/ct.cyr`:

```cyrius
# Branchless byte-array equality.
# Returns 1 if a[0..n] == b[0..n], 0 otherwise.
# No data-dependent branch on the comparison result.
fn ct_eq_bytes(a, b, n) {
    var acc = 0;
    var i = 0;
    while (i < n) {
        acc = acc | (load8(a + i) ^ load8(b + i));
        i = i + 1;
    }
    return acc == 0;
}
```

The XOR-accumulate is standard; both sigil and agnosys already
use this exact shape. Adding it to `lib/ct.cyr` deduplicates
the implementation across consumers and makes the audit story
clearer (one canonical CT-eq helper, used everywhere).

A cstring variant is useful but more nuanced: `strlen` itself
isn't constant-time, so `ct_eq_str(a, b)` only protects content
equality, not length. Callers with secret-length inputs must
use the explicit-length form. Both signatures probably belong
in `lib/ct.cyr` with the constraint documented.

## Suggested upstream investigation

1. Lift `ct_eq(a, a_len, b, b_len)` from `lib/sigil.cyr:1316`
   into `lib/ct.cyr`. Rename to `ct_eq_bytes` (clearer than `ct_eq`,
   which suggests scalar equality).
2. Add a cstring wrapper `ct_eq_str(a, b)` with a comment noting
   `strlen` is not CT.
3. Optional: a 32-byte fast path `ct_eq_32(a, b)` (the SHA-256
   common case — sigil already has this).
4. Update sigil's `lib/sigil.cyr` to delete its hand-roll and
   `include "lib/ct.cyr"` for the helper. Update agnosys's
   `src/certpin.cyr` similarly.

## Cross-reference

- `/tmp/cyrius-ct-eq-stdlib/README.md` — full reproducer
- agnosys `src/certpin.cyr:120` — `certpin_ct_streq`, the
  hand-rolled site this issue is about
- cyrius `lib/sigil.cyr:1316,1332` — sigil's hand-rolled
  `ct_eq` and `ct_eq_32`
- cyrius `lib/ct.cyr` — current contents (only `ct_select`)
- vidya `content/cyrius/language/features.cyml` —
  `secret_var_compound_ops` entry mentions `ct_eq` as the
  intended primitive but doesn't specify its stdlib location
