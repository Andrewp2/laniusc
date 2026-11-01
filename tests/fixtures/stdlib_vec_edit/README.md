# Owned vector editing direct gates

These fixtures execute the imported `alloc::vec::Vec` editing APIs. They do not
supply another vector implementation. The frozen contract is
[`docs/library-vec-edit-plan.md`](../../../docs/library-vec-edit-plan.md).

## Scope

- `admission.lani`: all five methods on a compound value with explicit
  destruction and comparison observations, followed by scalar natural dedup.
- `contracts.lani`: literal event sequences distinguish predicate/comparison
  calls from immediately following destruction. It covers empty/singleton
  dedup, empty/all-kept/all-rejected/alternating retain, all-equal/all-distinct
  dedup, a nontransitive relation and a stateful comparator that both expose
  last-retained semantics, natural equality operand order, negative/at-length/
  above-length truncation, reverse tail cleanup, repeated clearing, and reuse.
  Every live survivor and every unused instrumentation guard is checked. Pointer
  and capacity remain unchanged. No custom test value has a Clone implementation.
- `types.lani`: generic forwarding of all five APIs with a multiword record and
  a tagged enum carrying arrays, borrowed slice views and nested `Option<bool>`.
  It checks payload bits, original view offsets/stride/data, variant identity,
  complete source preservation, and exactly-once cleanup observations. Separate
  f32/f64 cases retain adjacent NaNs and the first signed-zero representative,
  checked by exact bits. Native negative-stride typed vector storage is observed
  for the compound record; this is a profile witness, not a byte-layout promise.
- Twelve negative fixtures separately omit Destroy from each method, omit
  PartialEq from natural dedup, or omit/mismatch each predicate's Mapper input
  and Boolean result. The driver requires the source-local capability diagnostic
  at the intended call. Positive generic controls actually execute in the first
  three groups.

The Rust driver checks Linux x86_64 ELF output and shared in-function jump
validation, executes each positive fixture under a complete syscall trace, and
requires empty stdout/stderr. Only one successful exec, exact successful
allocation/release pairs and a clean exit are admitted. Expected allocation
lifetimes are 2 for admission, 3 for contracts and 4 for types; all are explicit
setup vectors. The trace uses full-width addresses and lengths and ends with an
empty live set. No input/output, hidden allocation or other host effect is
allowed in these fixtures. Nested live owners, zero-sized counts, allocation-free
operation phases and larger workloads are covered by the separate resource and
model gates rather than duplicated here.

## Receipts

Root executed the tiny fixture through the pinned SDK compiler at production
`a5b93853` and fixture `20ea5b8b`. It exited 0 with empty stdout/stderr and exactly
two matched mmap/munmap pairs, with no other effects. Evidence is in
`target/stdlib-work/vec-edit-admission-compile-final.log`,
`vec-edit-admission.trace`, `vec-edit-admission.stdout` and
`vec-edit-admission.stderr`. This initial direct executable receipt preceded the
registered Rust gates below. An earlier admission attempt exposed a compiler
failure when a generic indexed value appeared directly in a `Pair` field
initializer (`first: slots[...]`); the accepted source first binds that value to
a typed local. The [paired reduction and control](../stdlib_vec_edit_dependency/README.md)
record the precise dependency. A separate fixture authoring error omitted the
required PartialEq `partial_ne` method; the accepted fixture implements both
PartialEq methods.

All five registered direct groups passed on the frozen sources below. Each
listed log is under `target/stdlib-work/`; elapsed times are the test-run times
reported in those logs, excluding the separate harness build.

| Log | Accepted scope | Result | Time |
| --- | --- | --- | --- |
| `vec-edit-tiny-rust.log` | Tiny all-method admission and full effect ledger | 1 passed, 0 failed | 5.73 s |
| `vec-edit-contracts.log` | Exact semantic/effect/bounds fixture and full effect ledger | 1 passed, 0 failed | 4.76 s |
| `vec-edit-types.log` | Generic compound layouts and float PartialEq fixture and full effect ledger | 1 passed, 0 failed | 5.58 s |
| `vec-edit-bounds.log` | Both capability groups, all twelve intended source-local rejections | 2 passed, 0 failed | 6.15 s |

The three positive groups compiled and executed their real fixtures, including
the exact matched allocation counts above; the two negative groups checked the
intended `LNC0008` diagnostic at each marked call. Independent direct-fixture
review also passed. No GPU execution, other operating system/ABI, formal
verification, malformed owner descriptors or callback contract violations are
claimed here.

## Frozen source

| File | SHA-256 |
| --- | --- |
| `stdlib/alloc/vec.lani` | `a5b938532093eceedc6b504375eaf4832e7f8601e8bb36c3a982d234ee047f47` |
| `tests/stdlib_vec_edit_execution.rs` | `d72ed3e67665e8fd52b88a7106732c31b9c9d9d0c582e96723e8be9046b4e7d5` |
| `admission.lani` | `20ea5b8b86e1c10e95961a327e6689d8f52863f690d8ed317392bc55d6e45d66` |
| `contracts.lani` | `1fee3f7ce396aabd8be940e17bcf5cab29f7501444b88892f1c407a96d1c589f` |
| `types.lani` | `ae48a73fc3a0055129fec3d75fd29514d6eb271964cc01698160440871f46f16` |

Keep each compiler/test invocation below 100 seconds and serialize native gates
under the repository's library compiler lock. Root owns those invocations.
