# Direct generic trait implementation methods: Stage A

Thirteen distinct selected checks pass on the Stage A build: four native
execution tests, four native rejection tests, four strict-interface tests, and
one host interface-contract test. `verification.json` indexes each exact command,
binary hash, log, and source/shader manifest. All five recorded groups, including
the unsuccessful strict initialization run, share the same manifests. This is a
checkpoint of that build, not a claim about later compiler changes.

## Established behavior

- Direct local and imported trait implementation methods inherit the impl's
  type and constant environment, including arrays at different lengths/layouts.
- An imported impl can use a prerequisite implementation supplied by its caller.
- Compound method results preserve complete values and independent copies.
- Inherent methods keep own, enclosing, and shadowed parameter bounds distinct.
- Missing prerequisites, unbound impl trait operands, invalid source-module
  visibility, and unsupported required-member contracts reject explicitly.
- Strict checking consumes the exact method and enclosing impl contract without
  relying on a pending native program gate. The host contract check validates
  inherited headers and exact required-method/native-target correspondence.

Native successes compile with the physical GPU, emit x86_64 Linux ELF, execute
it, and check its result. Native rejection cases check diagnostics before an ELF
can return. Strict successes export checked interfaces; they are not native
execution evidence. The host check does not execute the GPU.

## Strict initialization and cache provenance

The ordinary `type_checker_modules-2fa27f7cc330361d` invocation timed out after
85.306 seconds during compiler/pipeline initialization, with zero GPU-lock wait.
Its log records about 34.137 seconds creating the parser pipeline and 19.043
seconds creating the application-field expansion pipeline. The timeout is not
an assertion failure and remains an unresolved startup limitation.

A hardlink of that same module-test binary was invoked under the native test's
basename, `compiler_generic_types_execution-443177ec3361c248`. The alias record
reports `same_inode: true`; both strict invocations record SHA-256
`c49c400779c8beb6958084e5afe358c23857804cdbe1e13dff0cd0e3ebdf6412`.
The real native-test binary has a different SHA-256 and runs different tests.

File-open traces show the original strict invocation opening NVIDIA cache leaf
`f91b0f5cd21ff9fc`, while the alias and real native invocation open leaf
`f0db64b5cafd429e` in the same parent directory. Both strict paths read the same
wgpu cache entry. The aliased single strict case passed in 2.812 seconds; the
four-case strict group passed in 2.568 seconds. The single case repeats one of
the four and is not counted twice. These observations establish correctness
under the recorded cache condition; they do not establish acceptable cold
startup or compiler throughput. `cache-provenance/` preserves original records
and relevant verbatim trace rows; the index records full original-trace hashes
and the excerpt rule. The eight-second non-aliased trace was a bounded observation,
not a complete assertion run.

## Remaining work

Calls such as `fn via<T>(value: T) where T: Read { value.read(); }` still require
proof-directed required-member routing. Trait methods' own generic headers and
own `where` clauses remain explicit unsupported cases. Inherited impl parameters
and prerequisites do not remove those boundaries. Native widths/constants and
durable publication have separate unfinished work. This checkpoint does not
refresh the complete stdlib API audit, large-workload/cross-compiler performance,
or user-program GPU execution.

The original test functions remain in `tests/compiler_generic_types_execution.rs`,
`tests/type_checker_modules.rs`, and the compiler's
`semantic_interface::implementation_evidence::tests` module. Exact filters are in
the records. Absolute paths identify this machine's runs, not required project
layout. No tests were rerun to assemble this evidence package.
