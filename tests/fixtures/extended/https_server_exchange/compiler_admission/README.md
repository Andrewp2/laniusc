# Match-to-Option receiving-context admission

The current HTTPS Exchange fixture failed before native execution at this
unannotated binding:

```lani
let failed = match(error.cause) {
    ext::https_server::Cause::Tls(value) -> core::option::Some(value),
    _ -> core::option::None()
};
```

The actual source diagnostic is `LNC0006` / `AssignMismatch`, detail `2097152`,
at the `None()` arm: expected generic parameter 0, found unknown type. Receipt:
`target/stdlib-work/https-server-exchange-verified-steps-vec-api-retry.log`
(4.28 s; no native cases). The fixture now declares
`core::option::Option<ext::openssl_tls::Error>` explicitly; three sibling
HTTP Failure bindings receive the equivalent concrete Option annotation.
No behavioral assertion or compiler source changed.

`untyped_match_option.lani` preserves the field-match/record-payload/Some/None
shape with no HTTP, TLS or native dependency. `typed_match_option.lani` adds
only `Option<Diagnostic>` to that receiving local. Both main functions assert
the payload and fallback behavior.

The root confirmed this reduced distinction on Linux x86_64 with the current
GPU compiler. The untyped form rejects with `LNC0006` at 8:97, at the `None()`
arm. The explicitly typed control compiles and its generated native executable
exits 0 after both assertions.

| Source | Compiler result | Native result | Receipt under `target/stdlib-work/` |
| --- | --- | --- | --- |
| `untyped_match_option.lani` | `LNC0006` at 8:97 | No executable | `server-untyped-match-option-admission.log` |
| `typed_match_option.lani` | Success | Exit 0; both assertions | `server-typed-match-option-admission.log`, `server-typed-match-option-native.log` |

The pair differs only in the receiving local's declared `Option<Diagnostic>`
type. It establishes this source-context limitation and an executable spelling
for these two branches. It does not establish all match/Option inference, an
underlying common cause with other dependencies, or a compiler repair. No
compiler source changed.

The existing `https_batch/compiler_admission/nested_io.lani` dependency tests a
nested payload-pattern classifier rather than this receiving Option binding.
The library context-inference guide records other typed receiving-local forms,
but does not establish a common compiler cause for this case.
