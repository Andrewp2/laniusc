# Generic nested Option payload through `?`

Status (2026-10-27): fixed on `lang`. The type checker now gives `value?` a payload type that contains type parameters (`Option<T>`); before, the expression had no type and its payload load had width 0. Covered by `try_in_a_generic_body_unwraps_an_aggregate_payload` in `tests/language_ergonomics_execution.rs`.

These diagnostic-only pairs preserve a compiler dependency found while adopting
the language ergonomics features from `origin/lang` at `0d2e4a07`. They are not
registered as passing executable tests. No compiler or ABI change is included.

Both pairs use the actual `core::option::Option` declaration and a local generic
`flatten<T>(Option<Option<T>>) -> Option<T>`. The `-try` entry returns `value?`;
the `-match` control uses the original explicit match. Each main covers
Some(Some(value)), Some(None) and None, with identical checks within its pair.
The scalar pair uses i32; the multiword pair uses a two-field record. Even in
the scalar pair, the successful payload extracted by `?` is an aggregate
`Option<i32>`, not an i32. The semantic result is exit 0 with empty output.

| Reproduction | Explicit-match control |
| --- | --- |
| [scalar-try.lani](scalar-try.lani) | [scalar-match.lani](scalar-match.lani) |
| [multiword-try.lani](multiword-try.lani) | [multiword-match.lani](multiword-match.lani) |

## Minimal-pair receipts

All four exact sources compile to x86_64 ELF with exit 0. Both `-try`
executables receive SIGSEGV (Python subprocess return code -11, shell status
139); both `-match` controls exit 0. All four produce empty stdout and stderr.
These were serial GPU-compiler jobs at rebased HEAD `21764809` on
`origin/lang` `0d2e4a07`, with the separately tested stdlib source migrations
in the working tree. No compiler IR, ABI or runtime repair was made.

| Source | SHA-256 |
| --- | --- |
| scalar-try.lani | `03eb881a984eb1297996e0915945ad0e5a63bd19ad108689718f0ed8ff2bb506` |
| scalar-match.lani | `199e43fd17fb91b477c89a429e8519549ecdee88b912deebb20b04018a1dd5bd` |
| multiword-try.lani | `465a783e5a00ce3aa6520001e83fca9dc76f6878864a8ac51e957860965681af` |
| multiword-match.lani | `966dcdda48d48ee79d581a9edcb1f57227ef88418435ec90725830f8f29a8960` |

For each of `scalar-try`, `scalar-match`, `multiword-try` and
`multiword-match`, run the compile command separately:

```sh
timeout --kill-after=2s 100s flock target/stdlib-work/library-gpu.lock \
  target/stdlib-build/debug/laniusc --stdlib-root stdlib --emit x86_64 \
  tests/fixtures/stdlib_compiler_state/try_generic_flatten/SCENARIO.lani \
  -o target/stdlib-work/lang-flatten-SCENARIO
```

Set the resulting ELF executable and run it with a five-second deadline and
core dumps disabled. Receipt files under `target/stdlib-work/` are
`lang-flatten-SCENARIO-compile.log` and
`lang-flatten-SCENARIO-native.log`. The former are empty on successful compile;
the latter record actual process return code and both output streams. A signal
is a failed execution, not an accepted library outcome.

## Confirmed parent failure

The full existing `tests/fixtures/stdlib_foundation/core_option_result.lani`
compiled successfully against the stdlib whose only changed imported function
was `Option.flatten` returning `value?`. Its native ELF terminated with SIGSEGV
(shell status 139). The same fixture compiled against an isolated stdlib copy
with only `core/option.lani` restored from the rebased HEAD exited 0. Receipts
under `target/stdlib-work/` are:

- `lang-option-result-first-compile.log`
- `lang-option-result-native.log`
- `lang-option-result-control-compile.log`
- `lang-option-result-control-native.log`
- `lang-option-result-gdb.log`

The debugger stopped at RIP `0x491d23`, loading through RAX 0. The preceding
instruction loaded RAX from the first payload word at `-8(%rsi)`. This confirms
a runtime regression in the new expression path; successful compilation alone
does not establish correct aggregate payload execution.

Production `Option.flatten` retains its explicit match while this dependency
is unresolved. The other portable feature adoptions remain separate and need
their own executable receipts. Do not accept these repros by weakening the
payload checks or treating a signal as normal success.

## Lowering lead, not a proven fix

`shaders/codegen/lir/semantic/try_rows.slang` emits row 12 as a FIELD LOAD at
payload word 1, using the extracted value's aggregate layout. The debugger's
word load followed by a null dereference is consistent with loading an inline
aggregate's first word instead of preserving its address. Compare this path
with ordinary aggregate field/match projections before choosing a compiler
change. The minimal pairs and emitted LIR are needed to establish the exact
producer/consumer fault; this note does not claim a compiler repair.
