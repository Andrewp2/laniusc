# Imported option constructor collision

The minimal pair reproduces a constructor name-resolution failure. The imported
`None()` entry is rejected with `LNC0006`; the module-qualified entry compiles
and executes with status 0. This does not establish that generic `Option` is
broken. The production URL modules use the qualified constructor workaround.

The full URL TLS module imported `core::option::None` as an item and also imported
`ext::openssl_tls`, which declares `Need { None, Read, Write }`. An unqualified
`None()` in a typed option record field failed with `LNC0006`; explicit payload
type arguments still failed. A subsequent explicit typed local reported
`LNC0027` (explicit callable generic count did not match its header). Fully
qualified `core::option::None()` and `core::option::Some(...)` got the module
through type checking. The importing fetch application needed the same option
qualification and then compiled successfully. These observations suggest a name
resolution boundary; they do not establish that option inference itself failed.

The original full source is retained at
`target/stdlib-work/url-tls-inferred-none-original.lani`. Initial diagnostics are
in `target/stdlib-work/fetch-url-compile-first.log` and
`target/stdlib-work/fetch-url-explicit-none-retry.log`; the full application's
successful compile is recorded in
`target/stdlib-work/fetch-url-app-qualified-option-retry.log`.

This pair imports both the option module and its `Option`/`None` items, plus a tiny
peer module with the same `Need { None, Read, Write }` shape. There is no explicit
import of `Need` or its variants. The expected contract is that the item import
selects the option constructor when the local initializer expects `Option<i32>`.

- `unqualified.lani` initializes the typed option with the imported `None()`.
- `qualified.lani` changes only that call to `core::option::None()` (apart from
  its introductory comment).
- `fixture/peer.lani` is their identical imported dependency.

Both valid entries should compile and return status 0, checking an absent
option and an independently qualified `Need::Read`. Compile each with the
repository `stdlib` as `--stdlib-root` and this directory as `--source-root`.
Neither entry imports HTTP, TLS, native libraries, or the production URL facades.

## Observed result

- `unqualified.lani` (`78f56450`) fails at line 9, `None()`, with `LNC0006`.
  Receipt: `target/stdlib-work/url-none-item-import-compile-first.log`.
- `qualified.lani` (`615ada13`) compiles without diagnostics and returns 0.
  Receipts: `target/stdlib-work/url-none-module-qualified-compile-first.log`
  and `target/stdlib-work/url-none-module-qualified-native.trace`.
- The common peer module is `bb234524`. The qualified control's full syscall
  trace contains only `execve` and `exit(0)`; the reduction needs no allocator,
  network, TLS or native-library boundary.

No compiler change is included here. This pair is a dependency report, not a
negative acceptance test that requires valid code to remain rejected.

An earlier record-name candidate in this directory did not isolate a defect: its
unqualified local `Failure` constructor compiled successfully. It has been
replaced rather than retained as a compiler dependency.
