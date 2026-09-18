# Native pointers and the proof boundary

Lanius uses native process addresses at runtime. Abstract block identities
belong in proofs, not in a runtime address-translation table. The x86 allocator
already returns native addresses; this decision does not add another allocator
or change its emitted code.

## Confirmed raw-view alias mismatch — September 16

The current Core semantics and native backend disagree on repeated views of
the same allocation. `mapRawI32Slice` always copies the block into a fresh
backing cell; the native constructor retains the original pointer. Ordinary
Core assignment updates only the selected cell. This is an observable mismatch,
not merely a missing proof of correspondence.

The new `raw_alias`, `raw_alias_reverse`, and `raw_alias_twice` cases in
`tests/x86/slices.lani` expose all three directions. With the initial buffer
`[999, 10, 20, 30, 888]`, `raw_alias(data, 0)` writes 29 through the raw view
and returns `data[0]`. Core returns 999 and retains the original buffer;
debugging the emitted native executable at its return observes 29 and
`[29, 10, 20, 30, 888]`.

The source-authenticated Core/native suite currently **fails nine cases**:
three in-bounds indices in each new function. Its other 54 results and 41
bounds traps agree (13.08 seconds). These regressions must remain failures
until the semantics and backend agree; the test does not accept disagreement.
Logs are `raw-alias-all-cases.log` and `raw-alias-observation.log` under
`target/verified-compiler`.

The proposed correction is to reuse an existing registered backing place for
an already-mapped raw address, retaining protection and size checks. This would
change the authoritative Core semantics and the always-fresh-cell theorem
contracts, including typing, renaming, registry, and raw-constructor proofs.
It has **not** been implemented; the user has been asked to choose shared
storage versus preserving Core's current snapshot behavior in the backend.
Existing snapshot and bounded-store theorems do not close this discrepancy.

## Implemented boundary

`X86.Storage.Locations.pointer` explicitly maps represented Core pointers to
native addresses. The map is partial and has no numeric-identity fallback.
Null maps to null, and only null maps to null. `usize` remains an ordinary
integer; relocating a pointer must not relocate an integer with the same value.
These are proof parameters, not generated runtime data.

`X86.Storage.Heap.Correspondence` relates mapped live blocks to aligned,
nonwrapping, disjoint native ranges and their bytes. It derives injectivity
of represented pointers and preserves within-block offsets and actual Core
byte/i32 reads. Zero-size allocations reserve a distinct identity but grant
no byte access. Unmapped blocks need not have native storage: this is a partial
correspondence, not a claim that every Core heap is executable on x86.

The allocation theorem consumes the actual Core `Heap.allocate` result and
an explicit native-allocation effect, then extends the correspondence while
preserving old mappings. Native placement may move downward as well as upward.
The effect records the entire fresh reservation, including alignment/page
padding, and frames memory outside it. Caller words need their own separation
premise; preserving a pointer map is not the same as preserving stack memory.
The native allocator still has to be proved to establish this effect.

The byte-store theorem executes the actual Core `Heap.storeByte` operation
and preserves the full correspondence under the matching native byte update.
It retains allocation size, alignment, liveness, ownership, frontier, and budget.
This memory effect is not yet a proof of an emitted store-byte instruction.

`Correspondence.store_bytes` now derives successful Core bulk writes within
one represented allocation and preserves the full heap correspondence, pointer
map, allocation frontier, and resource budget. Empty writes may end at the
allocation boundary without requiring a one-past pointer mapping. The proof
reuses the single-byte theorem through one list induction.

`writeBytes_i32` equates Core's four little-endian bytes with `Machine.write32`
for every integer, including negative and wrapping values. `store_i32_step`
then derives a decoded MOV32 step from the backend's loaded disp32 encoding
and preserves the correspondence with the actual Core `Heap.storeBytes`
result. Register/address preparation and code loading are explicit inputs;
the step does not assume successful Core storage or native execution. It uses
the same `Machine.memoryBytes` encoding already proved for the Lanius emitter.
This closes the bounded word-store memory boundary, not recursive assignment
lowering, view synchronization, or the native allocator. The machine model's
mapping/protection assumptions still apply; preserving later code requires
code/data separation.

### Allocation, raw slices, and indexed reads

`Storage.Slice.Allocate.construct` now derives a protected raw i32 slice from
actual Core allocation and the native allocation effect above. It derives the
exact block size/alignment, successful borrowing, byte loading, i32 decoding,
fresh backing cell, view registration, and complete heap correspondence.
`Storage.Heap.Array` proves packed native storage for the entire decoded array;
callers do not supply per-element native reads. Empty allocations follow the
same construction but grant no element access. Borrowed blocks reject actual
Core deallocation and reallocation.

`Lower.Slice.Raw.Descriptor.initializes` connects this constructed view to two
decoded MOV64 stores. The stores create the native pointer-and-length
descriptor and preserve separated heap bytes and following code.
`Lower.Slice.Raw.read_initialized` composes those stores with the existing
decoded bounds check, address calculation, and signed i32 load. It derives the
descriptor words, backing representation, and Core constructor execution.
`Lower.Slice.Raw.reject_initialized` instead establishes the Core bounds trap
and native UD2, without loading an element, including the empty-slice case.
Register operands and the saved descriptor slot remain prepared inputs, with
explicit separation for that slot, heap storage, and code.

This two-store window is not the actual raw-slice compiler branch: that branch
evaluates and sign-checks the length between its stores. The source-linked
work below addresses that separate sequence; native allocator execution remains
open. The Core helper expression also
does not establish source-literal transport; a compiler caller must prove the
length fits signed i32. Repeated raw mapping may create two logical cells for
one address. The snapshot construction theorem does not prove future alias
coherence. Fresh allocation proves separation from valid old views and avoids
that duplicate-address case.

The active source-linked case is `i32SliceFromRawParts` applied to a represented
pointer local and a canonical signed-i32 literal length. The actual source
branch now authenticates, and its entry, recursive operand rules, allocation,
pointer capture, signed guard emission, length save, and descriptor LEA have
checked execution proofs. `Lower.Expression.Raw.compiles` now composes the
actual emitter and wrapper, deriving both recursive calls and retaining exact
45-byte output and the final workspace. It accepts negative literal lengths
too: compilation succeeds and emits the runtime guard.
`allocate(work, 2)` returns `oldTop + 1`; the two descriptor slots are
`oldTop + 1` and `oldTop`, and a slice result must retain `TOP = oldTop + 2`.
The proofs reuse the existing allocation, slot, memory, and guarded-emission
contracts. Plain LEA/address emission, 64-bit pointer-local loading, and
aggregate-result TOP preservation are now checked. Non-null pointer literals
cannot replace the pointer-local obligation: transport deliberately rejects them.

`Lower.Expression.Raw.Native.constructs` connects the actual native
TEST32/JGE/UD2/MOV32/store/LEA suffix to Core's raw constructor. It derives the
constructor result from exact live-block size, alignment, mapped storage, and
well-formedness; successful construction is not a hypothesis. Its negative
counterpart needs no valid backing allocation and reaches UD2 without a
descriptor write. These suffix theorems take the already-saved pointer and
evaluated length as inputs. `Lower.Expression.Raw.Preservation.compiles` now
discharges that boundary: it connects actual source compilation to the full
native sequence and the actual Core local-pointer/literal expression. The native
prefix derives the pointer load, capture, and literal value. Success takes eight
instructions; a negative length reaches UD2 after five, with the pointer
captured but no length store. Both TEST auxiliary-flag outcomes are covered.

The full-expression theorem preserves the caller, mapped heap, and every live
local slot below `oldTop`. Both private descriptor words must be separate from
code and mapped heap storage. The positive domain requires the exact live block
size and alignment above; the negative path needs no backing-block metadata.
These are explicit storage domains, not checks performed by descriptor writes.
General recursive operands, alias synchronization, and native allocation remain
open.

September 12 checks: the connected preservation leaf passed in 1.34 seconds;
the backend proof/standard-axiom audit passed in 14.45 seconds, including affected
dependency rebuilds. The actual 22-source regression run passed in 45.04 seconds:
17 compiler cases, 19 address-emission cases, and 13 source-shape rejections.
These are focused development checks, not an end-user extraction benchmark.

`X86.Storage.Pointer` connects Core pointer equality and inequality to native
CMP64 flags, including a decoded instruction step. The enclosing compiler
emission and boolean-result materialization remain separate proof obligations.

The Core-to-x86 transport accepts only null pointer literals. Other pointers
must enter through represented values, allocation, or views; a Core allocation
identity cannot be serialized as a native address literal. Lanius source
already permits only null pointer literals. Pointer parameters and numerical
`usize` literals keep their existing domains. The raw transport reader is an
untrusted bootstrap input, not a source-correctness certificate.

## What this does not establish

The deterministic Core interpreter has not yet been migrated to an
allocator-choice semantics. Its small, increasing addresses are still
observable in some operations. The new storage relation is not a theorem
that arbitrary programs can ignore those differences:

- Wrapping pointer arithmetic is not generally preserved by block relocation.
- A one-past pointer can equal the next abstract allocation's base. Native
  allocations need not be adjacent. The bounded relation does not certify
  one-past pointer equality.
- Core byte reads can cross adjacent abstract blocks. A host buffer operation
  needs a proved range within one live represented allocation.
- The proved Core borrowing transition does not yet establish native lifetime,
  free, or address-reuse correctness. Numeric membership in a live range does
  not by itself establish pointer provenance.
- The fresh raw-i32 descriptor construction does not cover every slice/string
  descriptor or later alias synchronization. A pointer map alone does not prove
  view synchronization or ownership.
- Native allocator, syscall, and ELF execution still need preservation proofs.

For general address-observing programs, allocation choice must enter the
existing shared heap-placement operation used by direct allocations, host
allocations, array views, and string pointers. The deterministic allocator
can then remain one interpreter policy. That migration must update the
frontier-dependent proofs and address-observation contract together; it must
not silently turn memory errors into undefined behavior.

No runtime translation shim or new trust assumption implements this decision.

## Verification

`X86.Tests.Pointers`, also imported by the standard backend proof gate,
checks relocated words, null and integer distinctions, translated reads,
framed stores, invalid maps, and the connected transport rejection paths.
Two actual Core allocations use descending native addresses; the second
has zero size. Their native effects also change reservation padding, so the
test does not assume only the logical payload can change. The focused gate
passed in 4.14 seconds and audits the new proofs for nonstandard axioms.
The connected `X86.Tests.Proofs` gate, including its affected downstream
compilation proofs, passed in 10.75 seconds (247 build jobs).

These are kernel checks of the representation and memory-effect theorems,
not execution tests or a proof of the Linux allocator wrapper.

The new `X86.Tests.RawSlice` gate passed in 2.24 seconds. It connects actual
Core allocation, byte storage, and raw mapping to ten decoded native steps:
descriptor initialization followed by the bounds/address/load sequence. The
result is independently checked as `-2147483648`. Cases also cover empty
allocation, invalid length/size/alignment, borrowed free/reallocation rejection,
descriptor overlap that corrupts backing, and a read after an effectful index
changes its element. The duplicate-view case checks snapshots only.
All new production and named test theorems pass the standard-axiom audit.

The standard backend gate now imports these tests. Its affected incremental
build passed in 2.04 seconds (258 build jobs, shared dependencies already
built). This is not a fresh whole-extractor check or a claim that the full
compiler now verifies in two seconds. Logs: `raw-slice-tests-build.log` and
`raw-slice-connected-build.log` under `target/verified-compiler/`.
