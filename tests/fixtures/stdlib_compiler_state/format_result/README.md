# Owned Display and imported Result compiler-state evidence

The production library exposes typed runtime `core::format` and owned `alloc::format::{format, format_bytes}`. A general `Display<T>` to owned String helper is **excluded from production**. Its prototype and these observations are preserved to make the remaining compiler dependency concrete. No compiler change, primitive overload, or payload-specific production workaround is included.

The base repository HEAD was `8cb1af7b65f098ef3f394e66f1891cf01d30dc22`. The compiler executable was `target/stdlib-build/debug/laniusc`, SHA256 `662b2ffeeb8b773bcfc57942ca4abc20f1533c856e0c466d3ed2a2953e32d9af`. All observations were made on 2026-10-23 with native x86-64 output, a 100 second compiler limit, and a 10 second executable limit. Final production formatting tests passed 6/6 after the unused `core::fmt` import was removed from `core::format`.

## Current minimal failure and passing control

The final three rows of [observations.md](observations.md) were rechecked against a fresh copy of the **final production stdlib**, replacing only `alloc/format.lani` with the indicated saved prototype:

| Case | Prototype | Consumer | Observed result |
| --- | --- | --- | --- |
| `final-primitive` | `forward-control/alloc/format.lani` | `primitive-display-typed.lani` | LNC0047; no executable |
| `final-unwrap-original` | `unwrap-repro/alloc/format.lani` | `unwrap-driver.lani` | LNC0047; no executable |
| `final-unwrap-control` | `unwrap-control/alloc/format.lani` | `unwrap-driver.lani` | compiler exit 0; native exit 0; empty stdout/stderr |

`primitive-display-typed.lani` is a small primitive-only consumer. It explicitly declares `Result<String, alloc::format::Error>` before inspecting it with a direct match. The prototype uses direct `T::format`, so removing an extra `core::fmt::display` layer and avoiding outer `unwrap(display(...))` do not establish general support.

The `unwrap-repro` and `unwrap-control` modules differ at one error-propagation expression in the same generic prototype. The reproduction calls `core::result::unwrap_err(copied)` for `Result<alloc::string::String, alloc::string::Error>`. The control directly matches that Result. The same `unwrap-driver.lani` defines a user `Point` Display implementation and exercises the helper. The former fails compilation; the latter compiles and executes its assertions with native exit 0. This establishes that particular source-composition-sensitive failure and a passing control. It does **not** establish that every imported Result predicate is broken.

Both failing final cases report the same diagnostic, with the temporary copied stdlib path shown exactly in the recorded stderr files:

```text
error[LNC0047]: type-check execution failed
 --> /tmp/lanius-state-root-final-primitive/core/byte.lani:2:1
  |
2 | module core::byte;
  | ^^^^^^ generic type instantiation reached a compiler boundary
     = note: a replay argument has no complete GPU native layout; its defining nominal payloads or a retained checked width witness are required
```

**Root cause is unestablished.** The diagnostic location does not prove a defect in `core::byte`; the complete source contexts and import classification matter. The production lower-level `core::fmt::Display<T>` interface remains available, and its custom Point consumer formats through caller-backed storage before passing completed Text to typed owned formatting.

## Reproduce using standard-library classification

From the repository root, prepare a fresh temporary standard library and override the saved prototype as a **stdlib** module:

```sh
snapshot=$(mktemp -d /tmp/lanius-format-stdlib.XXXXXX)
cp -a stdlib/. "$snapshot/"
cp tests/fixtures/stdlib_compiler_state/format_result/forward-control/alloc/format.lani "$snapshot/alloc/format.lani"
timeout --kill-after=2s 100s target/stdlib-build/debug/laniusc \
  --stdlib-root "$snapshot" \
  tests/fixtures/stdlib_compiler_state/format_result/primitive-display-typed.lani \
  -o /tmp/lanius-format-primitive
# Observed: exit 1, LNC0047; no executable.
```

For the one-expression reproduction and control, repeat preparation with `unwrap-repro/alloc/format.lani` or `unwrap-control/alloc/format.lani` and use `unwrap-driver.lani` as entry. The control's emitted executable runs with no arguments and exits 0. [observations.md](observations.md) lists the exact commands, actual temporary roots, compiler exits, native results, and diagnostic text for each recorded run.

Do not substitute `--source-root` for this preparation. Early exploratory runs loaded the saved `alloc::format` through a **user** source root, and all those consumers compiled. That changes the library boundary under investigation and is insufficient evidence for a stdlib generic helper. Those misleading runs are excluded from the observed stdlib result table.

[sources.sha256](sources.sha256) hashes every preserved Lanius source; [imports.sha256](imports.sha256) hashes all final transitive stdlib imports used by the prototype, with its `alloc::format` override explicitly identified. The hashes include the uncommitted library sources at observation time; the base HEAD alone does not contain this work. The repository snapshot containing these files preserves the referenced final imports.

## Historical contexts

The earlier rows in `observations.md` predate the unused-import cleanup. Their exact runtime-format source is saved as `baseline/core/format.lani`; historical preparation additionally overwrites `core/format.lani` with that file. [historical-sources.sha256](historical-sources.sha256) records those source bytes and their saved equivalents.

`forward-repro` uses an extra `core::fmt::display` forwarding call; `forward-control` uses direct `T::format`. Primitive-only consumers failed in both historical configurations, with nested outer unwrap and with explicit Result typing/direct matching. The final primitive row repeats the direct trait call and typed Result case after cleanup.

`all-payloads-control.lani` preserves a larger historical consumer that compiled and ran with native exit 0 through the direct trait prototype: signed/unsigned integer widths, f32/f64, bool, char, Text, user Point, and a local generic forwarding wrapper. The presence of this passing larger context does not make the minimal primitive failure disappear, so it is not a production capability claim.

`context-repro.lani` and `context-control.lani` both contain a local user Display implementation. They compiled in the historical stdlib snapshot. They were invoked with `s`, which exercises the normal allocation branch and deliberately returns 1 when allocation succeeds. Their recorded native exits are **1**, with no injected allocation failure; they are neither native exit-0 controls nor proof of the Display branch's runtime behavior. They establish only the stated compilation outcomes and normal allocation convention.
