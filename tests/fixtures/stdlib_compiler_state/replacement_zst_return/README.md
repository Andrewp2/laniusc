# Zero-sized return call boundary

Status: confirmed compiler/runtime dependency on native Linux x86_64 programs
emitted by the GPU compiler. No compiler, runtime or ABI implementation is
changed by these fixtures. The exact responsible compiler pass is not isolated.

Both sources contain only a caller-defined two-u64 `Progress`, inhabited empty
`Unit`, one function and main. They import nothing and use no enum, Result,
iterator, allocation or library replacement implementation.

- `repro.lani`: `(Progress,Unit,Unit)->Unit` must preserve Progress `(2,1)` at
  the callee, then exit zero. Compilation succeeds; native execution traps
  with SIGILL (`-4`), with no output.
- `scalar_control.lani`: the same record, arguments and callee assertion with a
  u64 return instead; main also checks the returned value 21. Compilation and
  native execution both succeed, with no output.

No public zero-sized payload is padded or replaced by a scalar. The return
type is changed only in the separately named control.

## Exact receipts

| Source | SHA256 | Compile log in `target/stdlib-work/` | Native log in the same directory |
| --- | --- | --- | --- |
| `repro.lani` | `172045f0ebd7618d94eaa8de855f75b56e9c927400f30bcadf730a8cc358172c` | `replacement-unit-return-call-repro-first.log` | `replacement-unit-return-call-repro-native-first.log` |
| `scalar_control.lani` | `ed1799f12cc878903be6748b9fc4e7935fc0c82c7c9ce32262daa65dd723bf6c` | `replacement-unit-scalar-return-control-first.log` | `replacement-unit-scalar-return-control-native-first.log` |

The repro ELF SHA256 is
`ef9a23d4ed77cdc8ce28329d2944274ccb1946c7530a5111c1248523f348e5f7`.
The passing control ELF SHA256 is
`b2d7bec9389c52d0f928db7421551842f9c1bc4ce82cdebe10dc67ca429b229f`.
The reported compiler CLI SHA256 prefix for these commands was `e8ad0014`.
Sources were moved here without byte changes after those receipts.

## Library context and classification

This was discovered in an unnecessary fixture function
`unit_old(ReplacementProgress,Unit,Unit)->Unit`. Earlier controls established
that direct public `ReplacementFailure<Unit,Unit,Unit>` construction and
main-local projection preserved `(2,1)` and `(5,3)`. Public Result enclosure,
generic constructor/Result return, and an equivalent caller-defined tuple enum
also executed correctly. Corruption appeared when passing the projected record
through that Unit-returning fixture function. Those controls' logs are
`replacement-unit-failure-{direct,result,local}-{first,native-first}.log` under
`target/stdlib-work/`.

This is not evidence of generic failure-enum storage or replacement-helper
failure. The accepted semantic shape fixture directly projects/asserts failure
progress and extracts the Unit item in its caller. It retains actual Unit item
and both error types, exact progress, callback counts, array writes, retry and
resumption. The public replacement API's Unit behavior passed its native gate;
see [semantic receipts](../../stdlib_foundation/replacement_sinks/README.md).

Root owns serialized compiler/native execution, each command below two minutes.
The fixture author performed only source/static work. The full library goal
remains open; this dependency is reported separately from accepted APIs.
