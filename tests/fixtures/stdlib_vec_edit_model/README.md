# Owned vector editing model

This fixture executes the imported `alloc::vec::Vec<T>` methods and compares a
strict little-endian binary transcript with a separate Python reference. Python
does not implement a production library API. One native child processes the
whole corpus; the child has a 75-second limit and the Rust wrapper a 90-second
limit. Root runs compiler/native commands under its 100-second outer limit.

## Contract and independent reference

The reference represents each element as a distinct identity and key. Retention
selects original identities. Deduplication partitions the original sequence into
groups headed by retained representatives: the first false comparison starts
the next group. It does not model storage slots or in-place compaction. Truncate
uses a prefix and a reversed removed suffix; clear retires the reversed list.

Each operation is checked against full ordered survivors and an exact event
tape. Events include the predicate/comparison kind, global callback ordinal,
number already destroyed, both operand identities and keys, and result. Destroy
events include the identity and key plus both counters. Stateful predicates
depend on the callback and destruction counters, so immediate destruction is
observable in subsequent decisions. A non-transitive closeness predicate on
`[0, 1, 2]` must keep `[0, 2]`; comparing with the previous original value would
incorrectly keep only `[0]`. Natural equality keeps the first representative of
each adjacent run, including distinct runs with the same key.

The two concrete element shapes are an instrumented descriptor and a compound
descriptor with a wide integer, `Option<bool>`, an integer array, and an owned
byte vector. Every nested vector has independent backing. A separate fixed
stack context stores callback/destruction events; it cannot reach the edited
vector. No callback performs allocation or I/O. Nested bytes are released by
the concrete `Destroy` implementation. Surviving elements do not borrow data
owned by removed elements. Temporary snapshots end before the next edit.

The native profile uses eight-byte record words, as specified by `core::mem`;
it does not pack `i32` record fields like standalone `i32` slice elements. The
small record has three words (`id`, `key`, reference), or 24 bytes. The compound
record has 12 words: three scalars, two for `Option<bool>`, three array elements,
three for the byte vector descriptor and one context reference, or 96 bytes.
Both exact sizes and their negative native strides are checked. Review corrected
the initial observer's C-style size assumption before any native admission.

Snapshots include the entire logical vector, complete compound fields and
nested bytes, actual capacities and complete pointer identities, view bounds
and native signed stride, empty state and instrumentation counters. The model
requires editing to preserve the exact backing and capacity; pushes may grow
according to any valid capacity policy. Live allocations must be disjoint and
nested owners keep their original descriptors. Every created identity appears
exactly once among survivors and retired identities; final cleanup retires all.
These observations do not establish physical deallocation or general memory
safety. The separate resource suite checks selected actual releases and
allocation behavior. Valid backing, independent cleanup authority and lifetimes
remain caller obligations.

## Finite corpus

Seed: `0x7eced170261118`. Twelve composed schedules run with each of two shapes,
for 24 cases and 1,920 actions. Each schedule has 80 commands, at most 24 live
elements, and no more than 80 created identities. Initial reserve requests are
0, 1, 5 and 31. The fixed witnesses cover empty/singleton edits, retain all/none,
last-retained comparisons, stateful predicates, adjacent equality, negative and
oversized truncation, reverse cleanup, clear and refill. Seeded continuation
mixes the same operations with changing keys and predicates.

Expected summary:

```text
vec-edit-model cases=24 actions=1920 created=1082 nested_owners=541 predicates=696 comparisons=350 natural_comparisons=352 destroyed=1082 events=2480 bounds=56 empty_edits=120 singleton_edits=20 refills=196 snapshot_items=4876 shapes=2 seed=0x7eced170261118
```

The input action buffer is bounded to 1,920 bytes; output is flushed from a
4,096-byte buffer. The event tape has 512 words, enough for twice the maximum
live count at eight words per event. Wire framing, ordinals, status/return
values, every event and every snapshot are checked. Truncation and trailing
bytes fail. Pointer observations use the established native x86_64 typed
pointer-slot serialization, without numeric pointer casts.

## Verification status

Host-only verifier controls passed: 25 deliberately corrupted transcripts were
rejected, and two different legal capacity policies were accepted. Mutations
include incorrect survivor/payload/event data, delayed destruction, forward
tail cleanup, comparisons against the previous original element, changed edit
backing, truncated and extended output. The uncorrupted synthetic transcript
is 707,168 bytes. This is verifier sensitivity evidence, not Lanius execution.

The first native admission stopped during fixture compilation with `LNC0021`:
the two implementations of the private test-only `Model` trait were marked
public. It reported 0 passed / 1 failed in 3.46 seconds; log:
`target/stdlib-work/vec-edit-model.log`. No native model cases executed. The
fixture correction makes those two implementations and their methods private,
matching the trait; public library trait implementations, runtime behavior,
oracle, corpus and driver are unchanged.

Corrected native admission passed: 1 test, 0 failures, 6.59 seconds, with the
complete expected summary above. Log:
`target/stdlib-work/vec-edit-model-final.log`. This executes 24 cases and 1,920
actions through the real library methods, observing 1,082 created and destroyed
identities, 541 nested owners, 2,480 events and 4,876 snapshot items. The accepted
sources are producer `00994c72d392b23bb92f6c5d8e7c4d3837e3cae9a6859599806ad4ecc218d10f`,
oracle `6ec3ddb2fa5faca9228f7b4203653e4021c35d4b97b49f62f5dffe46690d7511`, and
driver `7a978208350b949cce8f4daa018d77de3de4efcb8c70a46d94e0930da28b69af`.
The focused Rust selector is:

```text
cargo test --test stdlib_vec_edit_model_execution owned_vector_edits_match_ordered_survivors_and_exact_cleanup_events -- --exact --nocapture
```

Host controls can be repeated separately:

```text
python3 -B tests/fixtures/stdlib_vec_edit_model/oracle.py controls
```

Target scope is the repository's Linux x86_64 native profile, using GPU compiler
code generation. This fixture does not run Vec editing on a GPU device and does
not establish other architectures, arbitrary callbacks, panic recovery, zero
size types, floating equality, allocation denial or a proof of correctness.
Those are separate direct/resource gates where provided.
