# Compiler Conventions

This chapter records cross-cutting conventions for compiler code and compiler
docs. It complements `authoring-guide.md`: the authoring guide says what to
change for common features, while this page says how compiler changes should be
shaped.

## Ownership Before Locality

Put a fact where it is owned, not where it is easiest to patch.

| If the fact is about | It usually belongs in |
| --- | --- |
| source bytes, token boundaries, token file ids | lexer |
| syntax shape, tree topology, HIR rows, source spans | parser |
| modules, names, type refs, calls, methods, predicates, visibility | type checker |
| target layout, target status, target bytes | backend |
| jobs, artifacts, pages, shards, claims, resumes | source-pack planning/store |
| resource binding, dispatch, readback, timing, tracing | GPU infrastructure |
| command shape, output selection, no-run metadata | CLI |

Do not move semantic policy earlier just because an earlier phase has a nearby
buffer. Do not reconstruct syntax later when the parser should publish a HIR
record. Broad edits are fine when the contract crosses phases, but the phase
boundary should be named before code moves.

## Public Surface

Public and crate-public items need Rustdoc because they show up in the API view:

```bash
cargo doc -p laniusc-compiler --no-deps --document-private-items
```

Use [API docs and Rustdoc](api-docs.md) for the full item-level documentation
contract, coverage heuristic, and evidence policy.

Good Rustdoc for compiler internals names:

- the owner of the data or operation
- the lifetime or phase boundary it assumes
- whether the item is user-facing, maintainer-facing, or generated-reference
  inventory
- the status/diagnostic behavior when the operation can fail

Avoid Rustdoc that only restates the signature. If an item is visible only
because a neighboring module needs it, say what boundary that visibility serves.

## No Unneeded Compatibility

Do not add aliases, shims, old path support, deprecated entry points, or fallback
parsing unless another actual human besides the current user needs that
compatibility.

In-repo callers, generated code, tests, sibling crates, and future imagined
consumers are code to update; they are not compatibility requirements. When no
real human depends on the old surface, keeping it is a net negative:

- it leaves extra names and branches alive
- it creates more tests and docs to maintain
- it falsely tells future readers the old surface mattered
- it hides the reasonable current shape behind historical clutter

When compatibility is justified, document the human-facing reason, migration
path, and removal condition. Keep the layer small and test the promised
compatibility behavior directly.

## Status And Diagnostics

GPU status words are transport records. User-facing diagnostics are host-mapped
compiler outputs.

Conventions:

- status payloads should carry a token, HIR node, source-file id, or retained
  row that can recover a source span
- raw row ids, capacity counters, and scratch indexes should not leak into
  user-facing messages
- parser/type-check/backend status layouts belong in generated reference output
  when they change
- source-pack diagnostics must preserve original file identity, not packed
  storage layout
- fixed-bound exhaustion should point at the source construct whose shape hit
  the bound, or the bound should be removed with a data-parallel formulation

If the compiler cannot map a status to an indicative source location, the phase
boundary is incomplete. Prefer preserving better source evidence over adding a
generic host-side message.

## Buffer And Lifetime Conventions

Use `LaniusBuffer<T>` at ownership boundaries where logical count, byte size, or
element type matters. Borrow raw `wgpu::Buffer` at low-level wgpu call sites,
bind-group creation, or externally owned buffer boundaries.

Resident state conventions:

- resident buffers may be reused only while the cache key still proves they are
  compatible
- bind-group-affecting buffer identities belong in resident fingerprints
- buffers needed after a phase releases its cache must be cloned into explicit
  retained wrappers
- scratch reuse must document why the old value is dead at that boundary
- new retained backend data should cross through parser or type-check metadata
  wrappers, not by reaching into resident state from backend code

A raw buffer handle still existing is not evidence that its old compiler meaning
is still alive.

## Shader And Reflection Conventions

Shader source follows phase ownership:

- put entrypoints under the phase that owns the data they mutate
- use shared helper modules through explicit Slang imports
- add compute entrypoints only for shaders that should build artifacts
- bind resources by reflected names, not positional guesses
- size dispatch from owner capacity, active counts, or indirect dispatch args
- prefer scan, sort/radix, compact, scatter, range query, and segmented forms
  over source-shape-dependent loops

Reflection removes hand-written binding indices. It does not remove contracts:
the shader key, parameter names, Rust resource map, and retained buffer lifetime
must still change together.

## Source-Pack Persistence Conventions

Persisted source-pack records are contracts. Treat them more like file formats
than temporary structs.

Conventions:

- every persisted record family needs an owning preparation or execution stage
- versioned records should fail closed or default intentionally at validation
  boundaries
- `#[serde(default)]` allows reading old or partial stores; new writers should
  still populate the field
- target-specific paths should go through store/path helpers
- worker code should use lookup helpers instead of interpreting compact pages
  by hand
- resume cursors and progress pages must avoid duplicate writes and duplicate
  execution

Do not silently accept corrupt, mismatched, or incomplete persisted state just
because a worker can continue.

## Generated Facts

Generated output owns volatile facts:

| Fact | Owner |
| --- | --- |
| public compiler entry points | `docs/compiler/generated/reference.md` |
| stable diagnostic code registry rows | `docs/compiler/generated/reference.md` |
| shader load sites and Slang imports | `docs/compiler/generated/reference.md` |
| type-check pass loaders and record sites | `docs/compiler/generated/reference.md` |
| Rustdoc-visible coverage | `docs/compiler/generated/reference.md` |
| buffer carrier structs and large structs | `docs/compiler/generated/reference.md` |
| source/shader/test coupling | `tools/repo_map.py` output |

Hand-written docs should explain why these facts matter, not copy long tables.
If a hand-written doc needs an exact current list, link to generated reference
or describe how to regenerate it.

Do not edit generated output by hand.

## Test And Evidence Conventions

Tests are behavior contracts, not source inspections.

Good tests name:

- the public or phase boundary they protect
- the state space that matters
- the realistic bug they catch
- the smallest source, graph, page, row, or persisted store that proves it

Avoid tests that assert private pass names, helper spellings, shader filenames,
macro structure, or product-source text. Those facts belong in generated
reference output or Rustdoc.

Use broad generated, benchmark, Pareas, VRAM, or acceptance lanes only when the
claim requires that evidence. A no-run plan, shader-loop audit, or generated
reference check is not performance evidence.

## Documentation Conventions

Compiler docs should answer ownership and evidence questions:

1. Which phase owns this?
2. Which records or buffers carry it?
3. Which Rust or shader pass produces it?
4. Which status or diagnostic path reports failures?
5. Which source location should users see?
6. Which test, generated check, or benchmark artifact proves the doc is current?

Use these layers deliberately:

- hand-written guide chapters for ownership, invariants, and workflow
- generated reference for current lists
- Rustdoc for item-level signatures and local API contracts
- tests for executable behavior
- measurement artifacts for performance claims

Do not leave prose that sounds certain when the evidence is missing. If the doc
cannot answer a question yet, say what evidence or subsystem chapter is still
needed.

## Naming And File Placement

Names should make ownership obvious:

- phase-owned files should live under the phase directory, not under a caller
  that happens to invoke them
- bind-group and buffer carrier names should describe the relation or lifetime
  they carry
- status constants should name the semantic failure class, not the incidental
  shader line that found it
- generated files should say which command produced them
- public CLI/API names should describe the current behavior directly instead of
  preserving old terminology

Do not add "compatibility" aliases for old names unless the compatibility gate
is satisfied.

## Review Checklist

Before treating a compiler change as ready, check:

1. The owning phase is named.
2. Later phases receive data through explicit records or retained wrappers.
3. Status payloads are source-mappable.
4. Shader resource names, Rust bind resources, and retained buffer lifetimes
   agree.
5. Persisted source-pack records validate and resume intentionally.
6. No unneeded compatibility layer remains.
7. Generated reference or repo map is refreshed when volatile facts moved.
8. Rustdoc covers visible compiler items that changed.
9. The test evidence is focused on behavior, not source text.
10. Performance wording is backed by local measurement artifacts or kept out of
    the claim.
