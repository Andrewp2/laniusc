# Targets And Output

This chapter is the user-facing reference for target selection and output
contracts. It answers the questions a `laniusc` user has before choosing
`--emit`, `--target`, `check`, `-o`, or source-pack descriptor output.

For command syntax, use [Laniusc Invocation](invocation.md). For the row-by-row
evidence behind target claims, use the generated
[unstable-alpha slice reference](language/generated/unstable-alpha-slice.md)
and the source inventory in [Language slice policy](LANGUAGE_SLICE.md). For
backend implementation details, use [Codegen and backends](compiler/codegen.md),
[x86 backend internals](compiler/x86-backend.md), and
[WASM backend internals](compiler/wasm-backend.md).

## Target Selector Model

`laniusc` separates three ideas:

| Selector | Meaning |
| --- | --- |
| `--emit` | Selects the output backend family. |
| `--target` | Optional validation metadata for a target triple. It must match `--emit`. |
| `check` | Runs frontend/type-check diagnostics and exits before writing target bytes. |

Accepted emit targets:

| Emit target | Matching target triple | Current status |
| --- | --- | --- |
| `x86_64` | `x86_64-unknown-linux-gnu` | Default target. Bounded executable native byte-output slice. |
| `wasm` | `wasm32-unknown-unknown` | Accepted selector. Current backend fails closed at the backend boundary. |

Examples:

```bash
laniusc src/main.lani -o main
laniusc --emit x86_64 --target x86_64-unknown-linux-gnu src/main.lani -o main
laniusc --emit wasm --target wasm32-unknown-unknown src/main.lani -o main.wasm
laniusc check src/main.lani
```

`--target` is not a second way to choose a backend. If `--emit` and `--target`
disagree, the invocation should be rejected before source loading when possible.
If `--target` is omitted, the selected or default `--emit` value decides the
backend.

## Current Target Matrix

The target matrix is intentionally small because `unstable-alpha` is a bounded
alpha surface, not a production platform-support promise.

| Target | What can be claimed today | What not to infer |
| --- | --- | --- |
| `x86_64` | The primary executable target-byte path. It has bounded evidence for selected scalar functions, branches, loops, direct calls, selected source-pack helper calls, bounded arrays/aggregates, selected method calls, and selected trap/fail-closed diagnostics. | Not a full native ABI, linker, runtime, package, trait-dispatch, broad enum/generic, or production distribution story. |
| `wasm` | The selector and diagnostic boundary are public. Scalar source is rejected with a stable backend diagnostic while the byte emitter is rebuilt. | Accepted target selector does not mean executable Wasm output is currently supported. |
| Source-pack descriptors | Descriptor JSON can describe library-interface, codegen-object, partial-link, and linked-output artifact contracts when explicitly requested. | Descriptor JSON is not target bytes and must not be treated as executable output. |

Use row ids in the generated slice reference for exact evidence. Important row
families include:

- `wasm-backend-boundary`
- `x86-*` codegen rows
- `std-path-separator-x86-execution`
- `runtime-service-contract-ids`
- `descriptor-*` and `link-*` artifact rows
- `object-link-pipeline`
- `wasm-record-pass-order`

Rows marked `bounded` describe current bounded evidence. Rows marked `planned`
describe non-claimable future work. Do not use a planned row as evidence that a
target or output form works today.

## x86_64 Output

`x86_64` is the default compile target:

```bash
laniusc src/main.lani -o main
laniusc --emit x86_64 src/main.lani -o main
```

When compile mode succeeds, the CLI writes target bytes to `-o/--out`, or to
stdout if no output path is provided. On Unix, file output for non-WASM targets
is marked executable.

The x86_64 target is bounded. It can execute some scalar and source-pack shapes,
and it should reject unsupported shapes through source-spanned diagnostics
instead of silently producing partial native code. If a language feature parses
or type-checks but does not have an x86 execution row, treat native execution as
unsupported until the generated slice inventory says otherwise.

Common unsupported or bounded areas include:

- full native ABI and object/link pipeline support
- broad recursion and package-scale linking
- runtime-bound stdlib calls
- general trait dispatch and broad method ABI shapes
- broad enum payload, generic, aggregate, and temporary materialization cases
- production distribution and install artifacts

Use [x86 backend internals](compiler/x86-backend.md) for compiler-author
details such as retained buffers, feature measurement, capacity planning, x86
status mapping, and fail-closed backend diagnostics.

## WASM Output

`wasm` is an accepted target selector:

```bash
laniusc --emit wasm --target wasm32-unknown-unknown src/main.lani -o main.wasm
```

The current backend boundary is intentionally fail-closed. It consumes the same
frontend shape as x86, records explicit WASM stages, and reports a backend
diagnostic for unsupported output shapes instead of producing partial Wasm.

The row `wasm-backend-boundary` is bounded evidence for the stable diagnostic
boundary. The row `wasm-record-pass-order` is planned work for rebuilding Wasm
byte emission as record/count/prefix-sum/scatter passes. Until that planned row
has behavior-facing evidence, do not document Wasm as an executable output
target.

Use [WASM backend internals](compiler/wasm-backend.md) for implementation
details such as WASM stage order, retained input groups, resident cache
fingerprints, output/status readback, and diagnostic mapping.

## Check Mode

`check` runs the bounded frontend/type-check diagnostic path and does not write
target bytes:

```bash
laniusc check src/main.lani
laniusc check --source-root src --stdlib-root stdlib src/app/main.lani
laniusc check --package-manifest lanius.package.json
```

Check mode is the right target-independent command for editors, hooks, and
tooling that only need diagnostics. It rejects `-o/--out` and source-pack
descriptor-output modes because those imply target bytes or artifact contracts.

`check` does not prove a program can execute on x86_64 or Wasm. It proves only
the bounded frontend/type-check surface named by the language-slice rows and
diagnostics tests.

## Output Destinations

Compile mode writes bytes to stdout unless `-o/--out` is provided:

```bash
laniusc src/main.lani > main
laniusc src/main.lani -o main
```

Output behavior:

- successful compile mode writes target bytes, not diagnostics, to stdout or
  the output file
- diagnostics render on stderr according to `--diagnostic-format`
- Unix file output for non-WASM targets is marked executable
- WASM output files are not marked executable
- output write failures should become structured diagnostics when possible
- `check` writes no target bytes

Do not pipe descriptor JSON into a place that expects executable target bytes.
Descriptor output is an artifact contract, not a binary.

## Descriptor Output

Source-pack descriptor modes produce JSON contracts for persisted artifacts.
They are gated by:

```bash
--emit-contract
```

Without that explicit flag, descriptor-producing paths should be rejected rather
than emitted as if they were target bytes.

Descriptor stages include library interface, codegen object, partial link, and
linked output. A linked-output descriptor can describe final artifact contracts,
including unresolved runtime-service requirements, without proving that a
standalone executable target byte stream exists.

Use [Artifact Descriptors And Output Contracts](compiler/artifact-descriptors.md)
for the JSON schema, stage validation, runtime-service requirements, and CLI
contract-output guard.

## Runtime And Stdlib Boundary

The source standard library can type-check APIs that are not executable runtime
services. For example, runtime-bound APIs under `std::io`, `std::fs`,
`std::env`, `std::time`, `std::process`, `std::net`, `std::gpu`, and
`std::thread` can be known to the compiler while still lacking runtime binding.

Use no-run metadata commands to inspect that boundary:

```bash
laniusc diagnostics runtime-apis
laniusc diagnostics runtime-services
laniusc diagnostics runtime-api std::io::print_i32
```

Those commands do not compile source, scan stdlib source, create a GPU device,
or prove runtime executability. Use the [standard library overview](stdlib/README.md)
and generated [stdlib reference](stdlib/generated/reference.md) for the current
source-level module and runtime-service inventory.

## Adding A Target Claim

To make a new target or output claim, update the evidence before broadening the
prose:

1. Add or update the row in `docs/language_slice_unstable_alpha.tsv`.
2. Name the exact behavior-facing test, artifact-contract test, or diagnostic
   gate that proves the row.
3. Regenerate and check the generated slice reference.
4. Update this chapter, [Laniusc Invocation](invocation.md), and backend docs
   only for the claim actually proven.
5. Keep unsupported or not-yet-executable shapes fail-closed with source labels
   when a source location can be identified.

Target support is a public contract. A selector, descriptor, metadata row, or
frontend type-checking example is useful, but it is not executable target
support unless the generated slice inventory names executable evidence for that
target.
