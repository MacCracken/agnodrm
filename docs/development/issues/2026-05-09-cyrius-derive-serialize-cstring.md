# cyrius `#derive(Serialize)` doesn't handle cstring-pointer fields

**Status:** OPEN (passive — tracked internally, not refiled upstream: a cstring field type is a feature, not a cyrius bug). Re-verified against cyrius 6.6.6 at agnodrm 1.6.2 (2026-09-22): still unsupported; see the section at the end.
**Filed:** 2026-05-09
**Reporter:** agnosys 1.1.12 / 1.2.0 (during V1.1.12 `#derive(Serialize)` migration; surfaced when 5 of agnosys's 7 diagnostic-status structs needed hand-rolled `_to_json` shims because their fields hold cstring pointers, not `Str` fat pointers).
**cyrius version observed:** 5.10.6 → 5.10.19 (consistent across the V1.1.12 → 1.2.0 cycle).
**Severity:** LOW — workaround is mechanical and unwinds cleanly when fix lands. Don't refile.

## Summary

Cyrius's `#derive(Serialize)` directive emits a working `<struct>_to_json(ptr, sb)` body for:

- Untyped scalar fields → bare integer
- `: i64` / `: i32` / `: i16` / `: i8` typed fields → bare integer
- `: Str` typed fields → JSON-quoted string with RFC 8259 §7 escaping (cyrius 5.10.8+)

It does **not** handle bare cstring-pointer fields (`name;` where the field stores a `char *` from e.g. `str_from(...)` or a string literal). Such fields are emitted as raw integers (the heap-pointer value) — useless for diagnostic JSON dumps.

## Why this matters for agnosys

Five of agnosys's diagnostic structs hold cstring fields:

| Struct | Cstring fields |
|---|---|
| `mac_profile` | `agent_type`, `selinux_ctx`, `apparmor_name` |
| `dmverity_status` | `name`, `root_hash` |
| `update_state` | `version` |
| `certpin_info` | `subject`, `issuer`, `serial`, `sha256_fp`, `spki_sha256` |
| `drm_verinfo` | `name`, `date`, `desc` |

Adding `: Str` annotations would change struct layout (8 B → 16 B per field) and break the V1.1.0 accessor API. Adding `: cstr` (or whatever the chosen syntax is) would not — but that path doesn't ship in cyrius today.

## Workaround (1.1.12 ship)

agnosys hand-rolls `<struct>_to_json` for these 5 structs using a per-module `_<mod>_emit_cstr_or_null` helper:

```cyr
fn mac_profile_to_json(p, sb) {
    str_builder_add_cstr(sb, "{\"agent_type\":");
    _mac_emit_cstr_or_null(sb, mac_profile_agent_type(p));
    # ...
    str_builder_add_cstr(sb, "}");
    return 0;
}

fn _mac_emit_cstr_or_null(sb, c) {
    if (c == 0) {
        str_builder_add_cstr(sb, "null");
    } else {
        str_builder_add_json_str(sb, str_from(c));
    }
    return 0;
}
```

Pattern matches the eventual codegen shape so unwinding is mechanical when upstream lands.

## Mitigation when fixed

1. Delete the 5 `_<mod>_emit_cstr_or_null` helpers.
2. Delete the 5 hand-rolled `<struct>_to_json` fns.
3. Add `: cstr` (or whatever the syntax is) to each cstring field in the 5 structs.
4. Regenerate dist bundles + api-surface snapshot (the from_json companions land additively).

Net: ~50 lines deleted, ~15 lines of struct annotations added.

## Why this isn't filed upstream as a fresh issue

- Cyrius's `#derive(Serialize)` shipped working for `Str` and primitive-int paths in v5.10.6 → 5.10.16 — extending the type set is upstream's call to schedule, not an agnosys-side bug.
- Agnosys's hand-rolls cover the use case today; no urgency.
- Re-filing would be noise: cyrius team is aware of which type paths their directive supports.

When cyrius announces cstring support in a release note, agnosys reopens this slot.

## Related

- agnosys CHANGELOG `[1.1.12]` — V1.1.12 ship narrative
- agnosys CHANGELOG `[1.2.0]` — references the hand-rolls in the consumer-side rollup
- archived: [`2026-05-07-cyrius-derive-serialize-incomplete.md`](archive/2026-05-07-cyrius-derive-serialize-incomplete.md) — earlier arc that *did* result in upstream fixes (resolved 2026-05-08)

## Re-verified against cyrius 6.6.6 (agnodrm 1.6.2, 2026-09-22)

**Still unsupported.** `PP_DERIVE_SERIALIZE_BODY` (cyrius `src/frontend/lex_pp.cyr`) handles
`Vec<…>`, `f64`, `Str`, `i8`–`i64` and untyped fields. Any other type name, `cstring` / `cstr`
included, is treated as a nested derive struct. The derive then emits
`<Type>_to_json(ptr + off, sb)` (passing the field's *address*) and a `<Type>_from_json` decoder, and
the build fails:

```
warning: undefined function 'cstring_to_json'
...
error: refusing to emit binary with 1 reachable undefined function(s)
```

Two claims above are now stale:
- **Scope.** Only two structs remain in agnodrm: `update_state` (`version`, `pending`) and
  `drm_verinfo` (`name`, `date`, `desc`). `mac_profile`, `dmverity_status` and `certpin_info` left in
  the 1.4.4 decomposition.
- **Layout.** An unknown field type keeps its 8-byte slot and the same accessors, and `Str` fields
  have been 8-byte slots since 5.10.7, so the "8 B → 16 B" concern no longer applies. `Str` is still
  not usable here: a cstring stored in a `Str` field serializes as `""`, and a null pointer crashes
  the serializer.

New blockers found, for whenever the directive grows a cstring branch:
1. Every `#derive(Serialize)` also emits `_from_json`, which calls `bayan_json_get` /
   `bayan_json_parse`. agnodrm does not vendor bayan, so *any* Serialize derive, even on an
   all-integer struct, trips the undefined-function build gate on x86_64 and agnos. A migration
   needs either bayan in `[deps] stdlib` or an upstream serialize-only mode.
2. `cyrius api-surface` still models a derived `_to_json` at arity 1. Codegen has used
   `(ptr, sb)` since 5.9.31, so a migration reads as a breaking removal of
   `drm_verinfo_to_json/2` / `update_state_to_json/2`. The scanner also never lists `_from_json_str`.

**A hook route was evaluated and rejected.** Defining a consumer-side
`cstring_to_json(field_addr, sb)` makes the derived output byte-identical to the hand-rolls: 289/289
`drm_verinfo` cases and 34/34 `update_state` cases, including null, empty, quotes, backslashes, every
control byte, UTF-8 and a 70,000-byte string, on x86_64 and aarch64. It was rejected because it
needs an unprefixed global hook, drags in bayan, and adds lossy public decoders: cstring fields
decode to 0, and `{"name":"a}b"}` breaks `_from_json_str`.

No stdlib shortcut exists at 6.6.6: there is no cstr variant of `str_builder_add_json_str`, and
cyrius's folded `lib/sigil.cyr` hand-rolls the same way via `agnosys_json_emit_cstr_or_null`. The
hand-rolls stay.

The review did find a real bug in one of them. `update_state_to_json` emitted `pending`, a cstring,
through `str_builder_add_int`, so a pending update serialized as the heap address of its version
string. Fixed in 1.6.2: it now goes through `agnodrm_json_emit_cstr_or_null`, so the unset case
reads `null` instead of `0`.
