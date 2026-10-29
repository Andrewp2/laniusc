# Imported nested error-match admission

The original form-model producer (`97d842c6`) failed before native execution
at its inner `match(format)` while extracting a `u64` Capacity payload from
`ext::form_owned::Error::Format(ext::form::Error)`. The compiler reported
`LNC0047`: a nested type application could not be instantiated from its checked
environment. Root's receipt is `target/stdlib-work/form-model.log`:
**0 passed / 1 failed in 4.62 seconds**, with a separate **1.83-second Rust
build**. The relevant diagnostic is retained in `initial.stderr.txt`; only
its absolute workspace path is shortened.

This is a compiler-admission observation in test reporting code. It does not
show a runtime failure in form parsing, serialization or owned storage. The
diagnostic does not establish the compiler root cause or that all nested
matches are unsupported.

- `original.lani` reduces the reporting expression to one function using the
  same two imported nominal error types and nested wildcard matches.
- `helper_control.lani` moves only the inner match behind an explicitly typed
  `ext::form::Error -> u64` helper. The runtime assertions are identical and
  cover zero, a value above 32 bits, maximum u64 and non-Capacity variants.
- Both are valid programs and should compile and exit 0. These files are not
  negative tests requiring the compiler to keep rejecting valid source.
- `restore_original.patch` reconstructs the complete initially failing model
  from the factored producer. Host-side reconstruction was checked against
  exact SHA-256
  `97d842c66e72b3eba6df03b741b7a3d4769b7ee45d2bd286a11a97432bebbffe`.
  This retains the complete observed source composition alongside its
  successful reduction. Apply the patch to a disposable copy, not the active
  accepted-model path.

## Observed reduction and control

- `original.lani`, SHA-256
  `36c7bb08a673ffbac54e9f561d92180aa590da9c2b04307468dd6e57516175a3`,
  failed compilation with exit 1 and `LNC0047` at **7:77**, the inner
  `match(format)`. Receipt: `target/stdlib-work/form-nested-original.log`.
- `helper_control.lani`, SHA-256
  `57cea5fa1a73b6fca1307daafcee3d4493b287a64e474dc1f405b2f9bc374645`,
  compiled with exit 0 and empty compiler output. Receipt:
  `target/stdlib-work/form-nested-helper-build.log`.
- The generated `target/stdlib-work/form-nested-helper` then ran with exit 0,
  empty stdout and empty stderr, executing all six assertions. Receipt:
  `target/stdlib-work/form-nested-helper-runtime.log`.

The CLI admission arguments, from the repository root, were:

```text
laniusc --stdlib-root stdlib --source-root extended --emit x86_64 tests/fixtures/extended_form_model/compiler_dependency/original.lani -o target/stdlib-work/form-nested-original
laniusc --stdlib-root stdlib --source-root extended --emit x86_64 tests/fixtures/extended_form_model/compiler_dependency/helper_control.lani -o target/stdlib-work/form-nested-helper
target/stdlib-work/form-nested-helper
```

Root ran each command serially under `target/stdlib-work/library-gpu.lock`
and a 100-second outer deadline. These results concern Linux x86_64 CPU output
from the GPU compiler. No device or other-host result is implied.

The corrected complete producer, SHA-256
`beb7b40094ccd1fcb8b1579e6597a00aa6c3e4dc8acb47d7a52c93d8de2cd117`,
uses the same helper factorization and passed **1/1 in 9.02 seconds** with a
separate **0.22-second Rust build**. Its 607-case corpus, oracle, complete
expected bytes and Rust driver were unchanged. Receipt:
`target/stdlib-work/form-model-revised.log`; full scope is in the
[model README](../README.md).

The older [nested Result-error match](../../stdlib_foundation/repro_nested_error_match.lani)
records a different source shape and `LNC0005` diagnostic. It does not establish
this imported nested enum case, so this focused reproduction pair is retained.
No compiler, IR, ABI, extractor or proof source is changed here.
