# Lanius x86 backend

The target is the actual extractor, not an arithmetic-only language. The
18-source closure uses i32 arithmetic, booleans, usize/raw pointers, strings,
pointer-and-length i32 slices, ten struct declarations, direct calls, scoped
locals, conditionals, and loops. Host services include allocation, arguments,
file reading/closing, and output. The existing Core proof is the input semantic
contract; selecting `Target.x86_64` does not implement this backend.

## Lanius binary suffix — September 17

Binary expressions and compound assignments now share `operation::from_slot`,
which emits operand preparation and the operation while threading one cursor.
For ADD/SUB/AND/OR/XOR, its source-linked success theorem retains exact output
and the native Core refinement; initial reservation failure is also proved.
The total `write` theorem now covers exact partial output and sticky failure
on valid buffers. Initial rejection still accepts even a non-slice output.
The full recursive branch is not yet proved.

The complete combined proof checks fresh in 2.79 seconds with imports built;
strict axiom audits pass. The affected dependency/test rebuild takes 12.07
seconds. Focused source tests pass 3,559 calls, including 825 suffix boundary
cases, in 4.69 seconds. No executable changed in this proof-only follow-up.
The component has 218 program-specific lines, about 31x its seven-line helper,
plus 342 lines of composition support/adapters. Shorter public proofs and
stronger failure coverage have not yet reduced the total size. The Lean size
gate therefore still prevents scaling this pattern. See `PLAN.md` for accounting,
previous native regression results, and open obligations.

The current unverified bootstrap artifacts are `from-slot-backend` and
`FromSlotBackendExtracted.lean`. Older sections record earlier checkpoints.

## Native binary operand composition — September 17

The native save/right-operand/restore/arithmetic sequence now has a shared
composition proof. It preserves the left operand across right-child memory
effects, restores operand order, and derives Core's arithmetic result. Code
separation is explicit; following instructions are retained. The suffix preserves
caller framing when the right child returns with that frame intact.
The continuation statement/proof are six/eight lines, and the complete native
module checks fresh in 1.33 seconds with imports built. All helpers count:
174 production lines and 98 test/integration lines.

The right child remains an explicit induction obligation; a literal instance
discharges it. The actual Lanius recursive branch still needs its source proof.
Tests pass 750 machine sequences and two negative mutations, and check the
proved suffix bytes against current compiler output. The source/native scalar
regression passes in 7.39 seconds. See `PLAN.md` for trust, size, and scope.

## Arithmetic dispatch preservation — September 17

The actual `backend::operation::binary` path now has one source-to-machine
proof for ADD, SUB, AND, OR, and XOR. It derives both selector calls, the exact
emitted bytes and return cursor, caller preservation, and the native Core
arithmetic result. Short capacity and invalid cursors return -1 without output
access. The public success statement/proof are five/five lines; rejection is
four/three. Dispatch uses a callee contract, not assumed execution.

The complete dispatch module checks fresh in 2.32 seconds with imports built;
its strict transitive audit takes 1.30 seconds. Source-bound arithmetic and
comparison tests pass in 3.45 seconds, including 240 direct dispatcher calls
and four rejected source-shape mutations. All new production helpers count:
122 program-specific and 94 shared lines, plus 49 test lines. This still exceeds
the approximate 5x size target; see `PLAN.md` for matching scopes and evidence.

At this checkpoint the bootstrap/extraction artifacts were `arithmetic-backend`
and `ArithmeticBackendExtracted.lean`. Neither the GPU bootstrap nor the whole
compiler is proved correct yet. Recursive operand composition and the remaining
operators still need proofs; the extractor milestone and memory-model mismatch
are unchanged. Earlier checkpoints below describe their then-current state.

## Arithmetic emitter preservation — September 17

`Encode.Arithmetic.succeeds` now proves the real `x86::encode::binary` source
call and the Core result of its emitted ADD/SUB/AND/OR/XOR32 instruction. One
contract covers all register pairs and operand bits, including overflow, dirty
upper halves, and both permitted logical auxiliary-flag values. Exact output,
caller framing, other registers, memory, and instruction advancement are retained.
The source-to-machine statement/proof are four/two lines; all added helpers
and machine support total 209 production lines, plus 83 test lines.

Symbolic register-field reasoning checks in 1.42 seconds with imports built,
versus 8.20 seconds for the same proof using register enumeration. The source
regression passes 1,050 arithmetic calls plus the existing Boolean/comparison
cases in 3.34 seconds. At that checkpoint the arithmetic operator selector and
recursive expression compilation were still open. The full compiler/runtime theorem remains
open; `PLAN.md` records scope, failed trials, accounting, and evidence.

## Faster source validation — September 17

The same full backend source/execution regression now passes in **4.81 seconds**
with shared dependencies built, versus 6.84 seconds at the preceding checkpoint
and 56.75 seconds before indexing. Source-to-Core validation takes about
**0.90 seconds** inside the driver, versus 2.89 seconds previously. Symbol
matching reads at most three bytes instead of mapping the remaining file;
spelling claims now reuse indexed token, node, and source reads. Both changes
have all-input equivalence proofs. All existing cases and 35 source mutations
still pass. See `scanner-spelling-*.log` in `target/verified-compiler`.

Run the current closure from the repository root:

```sh
LEAN_NUM_THREADS=4 timeout -k 1s 119s "$HOME/.elan/toolchains/leanprover--lean4---v4.33.1/bin/lake" -d formal run check-backend \
  target/verified-compiler/from-slot-backend target/verified-compiler/from-slot-frame-native \
  target/verified-compiler/FromSlotBackendExtracted.lean
```

This is fresh **executable validation**, not a saved kernel certificate or a
completed compiler proof. Shared rebuilds are separate; `PLAN.md` records the
phase profile, proof/code size, rejected specialization experiment, and remaining
extractor-wide build check. Older timings below describe earlier checkpoints.

## Boolean literal preservation — September 17

`Lower.Expression.Literal.Boolean.from_transport` now proves the actual
Boolean-literal source call and native behavior of its emitted window. Both
values use the existing integer literal's generalized read/guard/width/emission
proof and MOV32 machine rule. EAX contains canonical zero/one bits representing
the Core Boolean; memory, flags, other registers, the caller frame, and following
code are preserved. No recursive source or native execution is assumed.

Insufficient capacity is proved separately: the source consumes the three
words, records CODE = -1, leaves output unchanged, restores TOP, and still
returns Boolean kind 2. The original integer contract remains derivable.
The source-to-native statement/proof are five/five lines; the serialized
endpoint has a six-line statement and a one-expression proof. All added helpers
and caller changes total 51 production Lean lines, plus 13 test lines.

The Boolean proof checks fresh in 1.28 seconds with dependencies built, with
standard Lean axioms only. The actual-source regression covers 48 integer/Boolean
successes and 120 short-capacity cases, including nonzero cursors and caller
sentinels. That broader source-validation/regression run takes 58.10 seconds;
it is not a whole-compiler performance success. General recursive lowering,
runtime/ELF preservation, and the closed self-certificate remain open. See
`PLAN.md` for precise evidence and scope.

## Expression-call proof interface — September 17

The initialized-local source/native proofs now share `Expression.Context`
memory/resource invariants and an `Emits` call contract. Scalar and pointer
preservation statements are six and five lines, with one-line proofs. The
contract retains termination, exact bytes and workspace, caller framing, and
native correctness of the actual emitted window. Raw-slice callers migrated
directly; there are no old-signature adapters in production.

All five old public contracts are recovered by a separate kernel audit.
Including new infrastructure and caller changes, production Lean shrinks by
69 lines. The fresh preservation module checks in 1.27 seconds with imports
built; the connected dependency rebuild took 23.41 seconds. These are local
measurements, not full-compiler verification times. The broader proof stack
still needs substantial size reduction. See the September 17 entry in
`PLAN.md` for accounting, evidence, and remaining obligations.

The follow-up generalizes the shared wrapper to retain arbitrary proved output
facts, including exact buffer contents. Literal success, capacity failure, and
missing-local rejection now reuse it; their proof bodies shrink from 53/53/45
lines to 16/16/15 without changing their contracts. One entry-state rule replaces
ten parameter-frame proofs. This removes another 165 production lines while
the shared wrapper checks fresh in 1.43 seconds with dependencies built. The old
wrapper and local contracts still pass kernel checks with standard axioms only.
This is proof reuse, not additional compiler-case coverage or an end-to-end
verification speed claim.

The shared wrapper now consumes `Context.Call`, a total emitter contract built
on `CellSpec`, and retains exact buffer facts through `Context.Result`. Its
body/call theorem statements shrink from 27/30 lines to 10/5. The local
emitter's statement shrinks from 34 lines to five, and its wrapper proof to six.
All concrete callers migrate directly. The five original public local
contracts and the original emitter contract still follow, with no added TOP
assumption or nonstandard axioms. Including helpers and callers, this removes
45 more production lines. Fresh checks remain around 1.3–1.6 seconds with
dependencies built; the connected build and audits pass. The broader size
target and compiler-case coverage are still open. See `PLAN.md` for evidence.

## Comparison proof boundary — September 16

The machine model now proves the complete CMP64/SETcc/MOVZX result window,
not just the comparison flags. For represented pointers and an injective
address map, three decoded instructions produce Core's equality/inequality
Boolean in RAX and preserve other registers and memory. The shared rule covers
all condition codes. SETcc preserves upper register bits; MOVZX clears them,
and the decoder distinguishes a neutral REX prefix from no prefix, following
the [Intel instruction reference](https://cdrdv2-public.intel.com/782151/253667-sdm-vol-2b.pdf)
(SETcc and MOVZX).

`Encode.Direct.zeroExtend_step` consumes the existing Lanius MOVZX emitter's
proved output contract. SETcc now delegates to the same register encoder:
`Encode.Condition` proves its success, condition/register/capacity rejection,
and decoded native step. The full source body and callee are authenticated by
`Source.Condition` and the existing source checker. Shared call-frame rules
avoid repeating parameter allocation and caller restoration.

`backend::operation::boolean` now expresses its two calls directly as a nested
call. `Source.Boolean` authenticates the complete function, both callees, and
the actual RAX constant. `Encode.Boolean.write` proves exact full or partial
output, including the sticky failure when SETcc fits but MOVZX does not;
`rejects` proves failure without output access for invalid conditions/cursors
or insufficient initial capacity. `steps` connects the exact successful output
to two decoded native steps, the Boolean in RAX, and preservation of other
registers, flags, and memory. No callee execution is assumed.

The operation selector is now source-checked through a shared branch-table
proof, also used by the ABI argument-register mapper. It covers all transported
Core operations, including rejection of non-comparisons. The model also decodes
CMP32 and proves the signed i32 CMP EAX,ECX; SETcc AL; MOVZX EAX,AL window against
Core for all six comparisons, including subtraction overflow and arbitrary
upper register bits. The CMP32 emitter's exact output decodes for all register
pairs. This is distinct from the opposite-register-order CMP64 pointer window.

The comparison path of `backend::operation::binary` now composes those proofs
through the actual source call. Its contract gives exact eight-byte output or
the completed two-/five-byte prefix on partial failure; initial failure needs
no output access. Successful output carries `Condition.NativeRefines` for the
same emitted bytes, so callers retain the Core/native connection. The source
checker authenticates the full function body, constants, and callees, but the
proof returns before the unproved arithmetic tail. That tail and recursive
comparison lowering remain open. See `PLAN.md` for checking times, proof-size
accounting, and coverage. This does not establish whole-compiler preservation.

## Work order

Milestone 3's inherited native-computation trust cleanup is complete; see
`AUDIT.md`. The concrete kernel-checked self-instance remains open. Backend
engineering can proceed independently, without weakening the final assurance
claim.

The whole extractor now compiles to a runnable ELF through this Lanius backend.
Compose the implementation proof along that same program path, including its
runtime/storage obligations. Instruction helpers are prerequisites when their
callers need them, not an inventory to complete first. The separate
source-to-Core implementation and concrete milestone-3 self-certificate remain open.

The work order now follows complete compilation capabilities. Do not require
every instruction-emitter proof to be finished before working on lowering.
The parameter-return case has a complete supported-input implementation proof.
The public driver now uses the linked program compiler described below;
its larger implementation has native tests and storage proofs, not a complete
preservation theorem yet. Extend that same path with calls and the extractor's
storage and host features. Do not
create a separate special-case backend for each expression form. The following list is
the coverage required for the whole backend, not a strict sequence of gates.

1. **Instruction emission and relocation.** Implement the reusable
   x86 byte emitter in Lanius. Validate register/width/condition operands and
   buffer bounds before writes. Support the scalar, memory, and control-flow
   instructions needed by the extractor. Establish exact relative-target
   arithmetic in Lean; compare native emission with an independent assembler
   and execute generated control-flow/memory examples. Neither comparison nor
   a Lean reference model substitutes for proving the Lanius emitter correct.
2. **Storage and calls.** Lower Core values to byte memory and stack slots,
   retain slice lengths and checked indexing, implement struct value semantics,
   define call/return storage, and connect these to Core memory/lifetime rules.
3. **Structured control flow and operations.** Compile actual function bodies,
   including short-circuit evaluation, integer widths, division edge cases,
   loops, and failure behavior. Compose instruction and storage simulations.
4. **ELF and host boundary.** Emit x86-64 Linux ELF and Lanius runtime code.
   State syscall/environment assumptions, handle I/O failures, and account for
   the difference between Linux file descriptors and the Core host model.
5. **Whole-extractor acceptance.** Compile every function in the exact source
   closure; link the source-derived IR, Lanius backend proof, machine semantics,
   runtime assumptions, and exact emitted executable. This closes milestone 4
   only with its full semantic-preservation theorem, not merely native tests.

Later source-to-IR implementation/proofs, the composed compiler theorem, verified
recompilation of the extractor, and the trusted fast path remain milestones 5–7.

## Current program path — September 11

The same recursive Lanius compiler now compiles and links a closed Core call
graph. `program.lani` validates the module, supplies each function's structural
input to `compile.lani`, and resolves entry/call relocations. `layout.lani`,
`value.lani`, and `call.lani` own shared value storage and argument passing.
The existing parameter-return optimization remains inside this function
compiler. There is no old single-function CLI fallback.

The implementation supports:

- i32/bool operations, comparisons, short-circuiting, scoped initialized
  locals, local assignments, branches, nested loops, break, and continue.
  Compound assignment reads the old value before evaluating its right side.
- Uninitialized scalar and aggregate locals. Only those declarations allocate
  an initialization flag; reads, compound assignments, and field/index place
  resolution trap until a whole-value assignment finishes. The flag resets
  at each scope entry, including loop iterations. An RHS cannot observe its
  target as initialized before the store.
- Full-width usize/raw-pointer values and scalar constants; i32/usize casts
  preserve Core's sign-extension/truncation rules. Pointer and usize equality
  compares all 64 bits and captures operands across calls. General wide arithmetic
  is not implemented.
- Nested struct construction, field projection, local/field aggregate assignment,
  aggregate arguments, and aggregate returns. Reads snapshot values before
  subsequent operands or calls can change their source.
- Slice/string descriptors as two-word values, checked packed-i32 reads and
  indexed stores, including recursive field/index assignment targets. Signed
  negative and full-width out-of-range indices trap before the element access.
  Place resolution captures the descriptor before evaluating the index, and
  compound assignment captures the old element before evaluating the RHS.
  Raw-parts construction and slice/string data-pointer access now compile.
  Raw-parts construction rejects a negative signed length; allocation
  provenance, exact extent, alignment, and lifetime are still storage/runtime
  premises, not checks established by writing the descriptor.
- String literals and constants retain exact UTF-8 bytes and byte length.
  Lanius emits position-independent, four-byte-aligned data using RIP-relative
  LEA and a jump over the bytes, then constructs the normal two-word descriptor.
  Code-image bases must be four-byte aligned. Aggregate calls and returns use
  the same existing ABI. `string_data_ptr` now makes a fresh four-aligned copy
  on every call, including empty strings. Pointer equality and mutation isolation
  agree with Core in focused tests. Borrowed allocation protection and the general
  content/storage relation remain proof and runtime obligations.
- Direct calls, forward/backward relocations, recursion, mutual recursion,
  and register/stack arguments. Argument expressions finish before their
  values are assigned to ABI registers. All functions use the same compiler.

### Value representation and calling convention

Scalar arguments follow the integer register order and 16-byte call-site
stack alignment in the
[System V AMD64 ABI](https://gitlab.com/x86-psABIs/x86-64-ABI/-/raw/master/x86-64-ABI/low-level-sys-info.tex).
Aggregate passing is an explicit **internal Lanius ABI**, not C/SysV aggregate
classification:

- A scalar takes one ABI word. The first six words use RDI, RSI, RDX, RCX,
  R8, R9; the rest use the stack, with padding before the stack arguments.
- An aggregate argument takes one ABI word pointing to a caller-owned
  snapshot. The callee copies it into its own local storage.
- An aggregate result uses a caller-owned buffer whose address is the hidden
  first ABI word. RAX returns that same address.
- Struct fields concatenate eight-byte internal words. i32/bool use the low
  four bytes; padding is not interpreted. A slice/string descriptor contains
  a full-width pointer and length. Referenced i32 array elements remain packed
  four-byte values; they do not use the padded internal struct layout.

Foreign aggregate interoperability is not claimed. Heap ownership,
pointer/length validity, and native runtime correspondence remain explicit
proof obligations.

Checked indexing sign-extends an i32 index, then uses one unsigned comparison
against the full 64-bit length. A live, nonwrapping packed i32 allocation has
at most 2^62 elements, so negative signed indices cannot pass that comparison.
The accepted path uses scaled LEA without an RCX scratch register. The signed
sequence is 43 bytes instead of 55; the usize sequence is 40 instead of 43.
The proof requires valid descriptor/backing storage. It makes no behavior
promise for forged foreign descriptors with impossible lengths, and does not
retain a second indexing implementation for those invalid inputs.

### Structural input and publication

`Transport/Core.lean` contains the moved serializer, not an import wrapper.
It serializes the selected source-derived Core call closure, struct metadata,
and used scalar constants. It does not choose layouts, registers, instructions,
or relocation targets. Those decisions run in Lanius.

The current program header is
`[2,64,entry,structCount,constantCount,functionCount]`, followed by struct
records, constants, and length-prefixed Core functions. A function retains its
existing six-word structural header. The compiler copies those function words
into caller-owned scratch storage; this is not a second parse or reconstruction.
Scalar constants use `(id,kind,low,high)`; string constants use
`(id,STRING,byte_count,bytes...)`. `backend::literal` validates and walks both
value representations. The transport supplies no native addresses or layouts.

### Whole-extractor ELF checkpoint

The Lanius backend now emits the complete extractor executable, including all
106 internal functions, nine host-service bodies and Linux startup/ELF headers.
`Tools/Transport.lean` authenticates the exact 18-source embedding and serializes
26,811 structural Core words. It does not lower instructions or emit ELF.
The GPU compiler bootstraps the Lanius backend; the resulting executable is
still untrusted until the implementation proof is complete.

`target/verified-compiler/extractor-lanius-x86` self-extracts the exact closure
in 2.12 seconds. Its 7,967,195-byte output is byte-identical to
`SelfCompactRequirements.lean`. The executable is a static ELF with an RX load
segment and an RW, non-executable stack. The production path uses no assembler,
linker, Rust exporter, Python wrapper, libc or Wasm runtime.

Verification (`runtime-*` logs in `target/verified-compiler`):

- `runtime-native.log`: 15 argument/allocation/file/byte/trap cases, 21 native
  allocator alignments through 1 MiB with freshness/zero-fill/caller checks,
  and 30 malformed runtime-service rejections, 3.40 seconds.
- `runtime-string-native.log`: 61 Core/native string/local results, 29 classified
  traps, and 39 malformed rejections, 10.71 seconds. Repeated string-pointer
  calls are distinct; mutating a borrowed copy changes neither the immutable
  string nor its other copies.
- `runtime-values-regression.log`: 83 scalar/aggregate/call results and 112
  malformed rejections, 8.45 seconds, with the final backend.
- `runtime-extractor-boundaries.log`: 12 actual-extractor lexical/oversize cases,
  including failure after zero, one or three valid files, 1.03 seconds.
- `runtime-backend-source.log`: the current 22-file, 12,699,327-byte backend
  pack passes exact source/Core validation and the existing source-linked
  helper/whole-index proof checks, 45.96 seconds. This is not a general proof
  of the new runtime or recursive compiler.

Current identities:

- Lanius-backend-produced extractor: `4154562ec218bee543bca351100230f15987a16b18585a2c7f996fefe0b4ecbf`.
- Self-extraction: `bc11dd2187755d63eb1ad4f8de4ac547c4e753f44c5142fc15f64113e62a675e`.
- Backend source pack: `3a5cd28336f18ee41f9988ead7fbbd0a2f566679c328f7523d93784fb4bad183`.

#### Native runtime boundary

The nine services live in `src/runtime/`. They use the existing architectural
emitter, with signature checking in `service.lani`. The ABI reserves R15 as a
pointer to startup state: the original Linux argument stack and next file-handle
number. Read/write loops retry EINTR, finish short writes, and read through EOF;
other errors normalize to -1. Open copies the exact bounded path and appends
the OS terminator. Closed handle numbers are not recycled: low OS descriptors
are duplicated above the previous handle counter. Allocation returns distinct,
zero-filled, aligned anonymous mappings; invalid alignment traps and resource
failure returns null. Fresh borrowed string copies trap if their backing mapping
cannot be allocated; this resource condition remains explicit.
Zero-byte reads still validate the handle, and byte writes reject stdin rather
than relying on its OS access mode. Startup exits with the low eight bits of
the Core entry's i32 return, following the Linux process-status interface.

The intended refinement domain includes sufficient native memory/stack and
descriptor resources, valid live raw memory ranges, NUL-free Linux-representable
paths, stable regular-file contents, initial standard descriptors and no other
inherited descriptors, and eventual successful I/O without asynchronous errors.
Partial side effects before OS errors are not covered by the deterministic Core
world. The wrapper does not by itself prove raw allocation provenance, exact
raw-slice extent, borrowed lifetime protection, or alias synchronization. General
recursive preservation must establish these properties or add the necessary
runtime checks. It must also reconcile the current one-address-per-string
`Storage.Locations.string` relation with content-based immutable literal storage.

The implementation follows the [AMD64 process/syscall conventions](https://gitlab.com/x86-psABIs/x86-64-ABI/-/tree/master/x86-64-ABI),
the [ELF header](https://gabi.xinuos.com/elf/02-eheader.html) and
[program loading](https://gabi.xinuos.com/elf/07-pheader.html) specifications,
and Linux's [read](https://man7.org/linux/man-pages/man2/read.2.html),
[write](https://man7.org/linux/man-pages/man2/write.2.html),
[mmap](https://man7.org/linux/man-pages/man2/mmap.2.html) and
[descriptor duplication](https://man7.org/linux/man-pages/man2/F_DUPFD.2const.html) contracts.

### Native pointer representation

The selected architecture is native addresses at runtime and abstract blocks
in proofs, with no runtime translation table. [Memory and pointer contracts](MEMORY.md)
records the implemented partial correspondence, the null-only literal boundary,
and the remaining allocator, one-past, raw-range, and general-semantics obligations.
The old equality between Core address numbers and native pointer words is no
longer the value-storage contract. `usize` remains numerical.

The connected storage step derives a raw i32 slice from actual Core
allocation and an explicit native allocation effect, including borrowing,
loading, decoding, and packed backing. A decoded two-store descriptor initializer
then composes with the checked native indexed load. The actual compiler branch
now has its own complete source-emission proof for pointer-local/i32-literal
operands: `Lower.Expression.Raw.compiles` derives both recursive calls,
pointer save, length evaluation/sign guard, descriptor address, and wrapper
return. It emits the exact 45-byte sequence and retains `TOP = oldTop + 2`.
`Lower.Expression.Raw.Preservation.compiles` connects the full emitted sequence
to the actual Core expression: pointer-local load, capture, literal evaluation,
signed guard, and descriptor construction. It derives recursive calls and
constructor execution, rather than assuming them. Success takes eight native
instructions; negative length reaches UD2 after five, before the length store.
The theorem retains the caller, mapped heap, and live slots below `oldTop`.
Nonnegative lengths require an exact live i32 backing block; both descriptor
words require code/heap separation. Neither those conditions nor native
allocator correctness follow merely from writing a descriptor.

The preservation leaf passed in 1.34 seconds. The connected backend proof and
standard-axiom audit passed in 14.45 seconds, including affected dependency
rebuilds (`raw-connected-audit.log`). Actual-source regression passed in
45.04 seconds (`raw-emission-source.log`): 17 compiler cases, 19 LEA/address
cases, and 13 altered-source rejections. No production-source refresh, new Rust,
Python, `native_decide`, or proof axiom was needed. These checks do not close the
general recursive compiler, allocator, host, ELF, or milestone-3 trust proofs.
See `Storage.Slice.Allocate.construct` and `Lower.Slice.Raw.read_initialized`.

### Earlier pointer/string implementation checkpoint

Pointer/slice intrinsics, full-width equality, string storage, and uninitialized
locals increased the actually compiled extractor call closures from 97 to 103.
The 60 scalar/record functions still pass 480 Core/native comparisons; the real
`verified::output::text` now passes 20 comparisons including UTF-8, embedded NUL
padding, dirty output buffers, and insufficient capacity. This is native
execution evidence, not a completed recursive compiler proof.

Focused checks for the new implementation:

- `pointer-values.log`: 83 Core/native value results and 112 malformed-program
  rejections, 8.32 seconds.
- `local-slices.log`: 54 results and 32 matching bounds traps, 10.09 seconds.
  Includes raw-parts returns on valid backing blocks, nonzero-offset pointers,
  and delayed initialization of a slice.
- `local-native.log`: 51 string/local results, 29 classified bounds or
  uninitialized-value traps, and 35 malformed rejections, 10.08 seconds.
- `relative-encoding.log`: 46,018 instructions agree byte-for-byte with GNU as,
  including all RIP-relative destinations and signed disp32 boundaries; operand,
  capacity, and untouched-buffer checks pass in 1.37 seconds.
- `pointer-string-extractor.log`: 103 actual extractor closures compiled,
  480 scalar/record results and 20 actual text-output results, 27.25 seconds.

The larger backend source pack is 8,502,803 bytes. The production extractor's
output capacity is now 16 MiB, with its allocation and formal capacity bounds
updated together; the existing 16 MiB packed workspace remains sufficient.
`output-capacity-backend-extract.log` records successful singular extraction in
1.50 seconds. Fresh backend source integration passed in 38.36 seconds
(`pointer-string-backend-source.log`), including the existing whole-index
source-to-Core proof connection and Core/native compiler-byte comparisons.
The backend standard-axiom audit passed in 18.45 seconds
(`pointer-string-backend-audit.log`). Neither proves the new recursive lowering
cases generally.

The earlier exact-source census (`pointer-string-requirements.log`, 18.96
seconds) accepts 103 of 106 internal bodies. The remaining internal functions
are `app::main::main`, `verified::byte_io::read_file`, and
`verified::byte_io::write_stderr_natural`; they call the nine external services
listed by the census. Implement their runtime linkage and the ELF entry point
next at that checkpoint. The ELF checkpoint above now closes that engineering
boundary and fixes fresh string-pointer behavior. The remaining runtime/storage
and proof obligations are recorded there.

The wider extractor proof rebuild is **not yet verified** for the new capacity.
The updated packing bounds and packing/alias tests built, but the complete
`Entry.Source` build reached the 119-second cutoff while rebuilding stale
frontend dependencies. `output-capacity-proof-build.log` records that timeout,
including a 57-second symbolic parser data rebuild and unfinished parent-loop
dependencies. Do not treat partial build output as an accepted milestone-3
instance, or repeatedly rerun the same build solely to warm its cache. Inspect
and reduce that rebuild cost before the next full acceptance run.

`tools/backend.lani` emits a complete ELF by default; `--raw` emits a linked
code image beginning with an entry jump for ABI tests. Input, function scratch,
workspace, and output are separate caller-owned buffers. Failure leaves scratch
state; the driver publishes bytes only after the entire program succeeds.
The stronger atomic-failure contract of the parameter optimization does not
apply to the general compiler.

Limits are 65,536 program words, expression/statement depth 512, type-layout
depth 64, 4,096 words per value, and 1,048,576 frame words. The frame helpers'
source and signed-displacement proofs now cover the expanded frame bound;
deriving that bound and every allocation's ownership from the recursive
compiler remains part of its implementation proof.

### Connected proof boundary

The indexed-expression caller now has source-linked allocation and descriptor
preparation proofs. `Frame.Allocate.succeeds` and `rejects` cover the actual
allocator, including high-water-mark reuse, slot exhaustion, and caller framing.
`Lower.Expression.Indexed.compiles` composes the complete actual caller under
an explicit recursive-expression emission hypothesis: reserve one slot, save
RAX, compile the index expression, emit checked address calculation, and close
both lexical scopes. Its hypothesis retains the original caller's storage
frame, so input/context invariants can survive preparation. The recursive
compiler has not yet been proved to supply that hypothesis.

The failure paths are connected too. `Indexed.Reject.rejects` returns false
at exhausted slot capacity without reading output or recursing.
`Indexed.Failure.rejects` propagates an invalid recursive result kind to false,
retaining the operand-save and child bytes already emitted; it does not claim
atomic rejection. The actual-source integration on the unchanged 22-file pack
passed in 52.49 seconds: 32 allocator boundaries, two exhausted-slot calls with
poisoned unused arguments, 24 complete indexed calls, 16 source mutations,
and the existing emitter/frame/Core-native comparisons. The shared kernel
axiom audit passed for the new source-composition proofs. Logs:
`indexed-source-integration.log`, `indexed-failure-build.log`, and the focused
test/audit logs under `target/verified-compiler`.

Full-width slot separation and descriptor capture now preserve older live
slots, the saved caller header, and following code.
`Indexed.Preservation.compiles` attaches the whole emitted window's
`NativeRefines` contract to the actual source call. Consumers need no hidden
prepared-state witness. The machine composition keeps recursive machine
execution separate from recursive source emission; neither is assumed proved
for the whole compiler. Its focused kernel build passed in 2.35 seconds
(`indexed-preservation-build.log`).

The signed-i32 literal base case now supplies a complete source-execution
theorem without a recursive or helper-execution hypothesis.
`Lower.Expression.Literal.compiles` covers the actual expression wrapper,
three transport reads, kind checks, width selection, five-byte MOV EAX emission,
TOP restoration, and caller framing. It consumes exactly three input words.
Its kernel build passed in 2.44 seconds; the shared source-proof audit passed
in 6.44 seconds. The unchanged 22-file source pack passed expanded integration
in 52.20 seconds: 36 literal wrappers, 72 immediate emissions, 28 transport
reads, three entry guards, 23 source mutations, and the prior indexed/frame
cases. Logs: `expression-literal-wrapper-build.log`,
`literal-source-integration.log`.

`Literal.Preservation.from_transport` now connects actual Core serialization,
that source call, and one decoded native step. The signed range and three
transport words come from serialization, not independent assertions. The
result preserves memory, flags, non-RAX registers, caller frame, and following
code. Its focused build passed in 1.34 seconds.
`Indexed.Literal.Preservation.from_transport` composes the literal with actual
descriptor capture and bounds/address generation. Neither recursive source
execution nor recursive native execution remains a hypothesis for this case.
Descriptor, backing-array, frame and code separation remain explicit storage
preconditions. Its build passed in 1.64 seconds. Logs:
`literal-preservation-build.log`, `indexed-literal-preservation-build.log`.
These close a concrete indexed-helper case, not general source indexing or
the remaining recursive expression cases.

Rejection proofs retain the real protocol: an out-of-capacity literal wrapper
returns kind `1` with `CODE = -1`, consumes its three words, restores TOP, and
does not change output (`Literal.Capacity.records_failure`, 3.24-second build).
The transport reader's negative/exhausted-cursor path returns zero and sets
only FAILED, without inspecting even an invalid input argument
(`Frame.Take.Reject.rejects`, 1.04-second build). Their concrete helper tests
run in Core; they are not claimed as physical native helper calls.

Initialized i32 locals are now connected through the actual expression wrapper
too. `Local.Preservation.from_transport` derives the identifier and input words
from serialized Core, proves actual reverse lexical lookup and table selection,
emits the six-byte frame load, and relates decoded execution to the Core local
value. Canonical value and frame-slot correspondence are explicit representation
conditions, not execution hypotheses. The shared `Expression.Wrapper` rule
handles TOP capture/restoration and caller bookkeeping for scalar cases.
`Local.Reject.wrapper_rejects` proves lookup failure before any kind/slot access;
it returns -1, preserves output and restores TOP. The combined source/native
proof leaf passed in 3.74 seconds, the integration/axiom audit in 11.34 seconds,
and the unchanged exact source pack in 55.40 seconds. Twenty-four successful
or shadowed-local Core cases and eight missing-name cases passed; all 35 source
mutations were rejected (`local-integration-build.log`,
`local-source-integration.log`). These cases execute authenticated Core;
physical native wrapper execution is not claimed.

The wide immediate helper also has source-to-machine preservation.
`Encode.Immediate.Wide.Preservation.from_transport` reconstructs the exact
64-bit usize from its actual low/high transport words and proves the source
helper emits the ten bytes consumed by decoded MOV r64, imm64. Other registers,
memory, flags and following code survive. The shared decoder extension retained
all existing proofs; the expanded Lookup/Get/Wide source suite passed in
54.08 seconds (`wide-lookup-source-integration.log`). This is the wide emitter
helper proof, not yet the whole usize-expression wrapper proof.

Two independent compiler-path components have also advanced. New
`src/lowering/types.lani` translates the existing Surface type arena to the
backend's structural type tags, with explicit name-resolution input. Its
builtin catalog is materialized at most once per invocation; 112 source/Core/native
cases passed in 10.59 seconds. `src/lowering/declarations.lani` now collects
headers from actual materialized file trees, retaining unit, kind, visibility,
source origins, names and alias/module/import targets. Seventy-two cases passed
in 30.86 seconds, comparing source-executed and native results with independently
reconstructed Surface declarations. These components are not yet called by the
production source-to-Core path or universally proved. Pack-level allocation,
name resolution and lowering of bodies remain to be connected.
The new `src/lowering/allocation.lani` does now consume actual collector tables
and derive declaration/Core IDs, preserving origin rows and matching
`CoreSynthesis.Program.allocate`; 64 connected Core/native cases passed in
28.85 seconds. `src/lowering/modules.lani` materializes module/import paths as
checked token/source-byte spans without copied strings or host-assigned IDs;
97 Core/native path cases and 12 collector cases passed in 27.54 seconds.
Import linking, symbol resolution and production pipeline integration remain
open, as do universal correctness proofs for these new Lanius passes.
`Storage.String` and `Storage.StringCopy` provide content-based descriptors,
fresh-copy isolation (including empty strings), and a bridge from actual Core
string allocation to a conditional native-copy postcondition. Actual runtime
allocator/copy execution and a whole-heap address relation remain open.

### Frontend checking cost and trust

Selective `reduce_data%` normalization now retains unused proof-rich source-use
metadata while proving exact equality of the complete value in the kernel.
The symbolic parser data build fell from 57 to 27 seconds; its immediate
consumer stayed at 2.5 seconds (previously 2.6). The combined focused build
passed in 30.36 seconds, with peak RSS 4,653,636 KB. Baseline profiling attributed
44.8 seconds of a 64.69-second standalone run to kernel declaration checking.
Logs: `symbolic-data-profile.log`, `symbolic-data-retention-build.log`.

The first parser frame-trust cleanup removed 14 `native_decide` sites,
including seven previously reachable assumption owners, and passed its
connected audit in 38.07 seconds (`trust-frame-integrated.log`). This is not
a new global assumption count. A second frame/source-ID family initially hit
the 119-second limit. After replacing repeated enclosing-statement type checks
in the shared reifier with composition of child typing proofs, a newly
invalidated connected closure passed in 103.12 seconds. The family removes
21 native sites covering 12 additional historically reachable assumptions
(nine owners); 24 metadata/source-ID declarations are kernel-only and six
unions add no trust. The generic reifier's accepted/rejected typing, loop
control and exact-roundtrip tests passed in 1.35 seconds.

That algorithmic cleanup did not measurably speed up the State.Core hotspot:
35 seconds versus 34 previously. The integrated timings had different
invalidation scopes, so 103.12 versus the earlier cutoff is not a speedup
claim. A named kernel-declaration profile is the next performance step.
The refreshed complete extractor instance and the kernel-only self-validation
boundary remain open.

Two later scanner/decimal metadata families also passed their connected
audits: 13 historically reachable ABI/delimiter/route assumptions removed
(31.76-second production build and 1.14-second test-fix audit), then 16
body-presence assumptions removed (30.46 seconds). Body/reification correctness
assumptions were not silently replaced. Logs: `trust-call-metadata.log`,
`trust-call-metadata-audit.log`, `trust-body-presence.log`.

A whole-`ReifiedCommand` cache experiment regressed State.Core to 85 seconds
and hit the 119-second closure cap. That experiment was reverted; only the
earlier data retention and bottom-up typing changes remain. The restored
State.Core text is the previously accepted implementation, but its experimental
build artifact must be replaced by normal stale-source rebuilding before a
fresh complete-source acceptance claim.

The existing parameter-return implementation proof remains intact. Frame
layout, source-bound displacement/size helpers, decoded scalar spill/reload,
and actual return emission also remain proved. Prologue/body/epilogue
composition still has an explicit body-execution/frame premise; it is not a
proof of the recursive compiler.

This checkpoint adds:

- One shared 32/64-bit MOV memory decoder and encoding theorem, covering
  all sixteen register/base choices, signed disp32, optional REX, and the
  no-index RSP/R12 SIB form. Width behavior follows the
  [Intel SDM](https://www.intel.com/content/www/us/en/developer/articles/technical/intel-sdm.html)
  MOV entry. It uses the existing memory model, not a second decoder.
- `Machine.Copy.correct`: the whole two-instructions-per-word copy executes
  decoded x86 for up to 4,096 words, copies every source word, changes only
  destination bytes, and preserves all registers except R10 and all flags.
  Source/destination and code/destination separation are explicit.
- `Storage.copy_value`: that sequence preserves a represented Core value
  at both the source and destination. The relation accounts for scalar
  padding, nested structs, and pointer-and-length descriptors. Address
  assignment is a parameter; valid/live backing allocations are not assumed
  to have been proved by copying a descriptor.
- `Frame.BodyFrame.copy`: a copy into a private allocated frame block
  preserves the caller's saved frame pointer, return address, callee-saved
  registers, and direction flag.
- `Storage.Slice.Represents`: a packed i32 backing-array relation with a
  nonwrapping extent and canonical signed values. Its theorems establish
  in-bounds byte addresses, distinct element windows, signed reads through
  nonzero slice offsets, exact list updates, and preservation outside a store.
- `Lower.Slice.index_refines` and `assign_refines`: the final decoded MOV32
  accesses agree with the corresponding Core continuations. The index may
  mutate backing storage, and the assignment RHS may mutate it again; stores
  update the current backing array while retaining the previously resolved
  target and old value. Read views allow projected cells and nonzero starts;
  the store theorem covers resolved elements of root backing arrays.
- `Frame.BodyFrame.write32` and `Lower.Slice.store_preserves_caller`: one
  shared frame-preservation rule now covers both private-slot and heap-element
  stores. Heap separation must protect the saved caller header.
- `Machine.Index.correct`: decoded MOVSXD, descriptor loads, CMP/JB/UD2,
  and scaled LEA establish the accepted address or the architectural bounds
  fault. The shared machine model now includes those instructions; LEA does
  not read the addressed element or change flags.
- `Lower.Index.read_refines` and `reject_refines`: the whole checked-address
  sequence connects to effectful Core indexing, including signed negatives,
  full-width usize indices, nonzero slice origins, and bounds failure. The
  correctly calculated address is no longer a caller-supplied premise.
- `Encode.Indexed.succeeds` and `rejects_capacity`: the actual Lanius
  `indexed_address` body has general source-linked contracts for valid
  register/scale operands, signed displacement bytes, exact output, and
  caller-state preservation. Capacity rejection touches no output, even if
  the output argument is invalid. `slice_address_emits` connects its slice
  indexing instance to the decoded LEA machine step. `Source.Indexed.check?`
  authenticates the complete body, callees, and RSP constant lookup.
- `Encode.Memory.succeeds` and `rejects_capacity`: the actual `memory_form`
  body now has general source-linked contracts for valid width/register and
  opcode-map inputs. They cover REX/escape/SIB size selection, reservation,
  every header store, signed disp32 output, and all local scopes. Rejection
  precedes output access. Shared cursor advancement, register validation, and
  header-plus-word proofs serve both existing and new emitters.
- `Encode.Memory.move_emits` and `move_rejects_capacity`: the public Lanius
  `load` and `store` calls connect to the existing decoded 32/64-bit MOV model
  for all register/base choices and displacements. The resulting bytes,
  cursor, output window, and caller state are proved, not assumed. Loading
  the emitted bytes into machine memory remains an explicit premise.
- `Frame.Slot.emits`: the actual `backend::frame::load`,
  `backend::value::load_word`, and `save_word` bodies compose the displacement
  helper, memory emitter, and workspace cursor assignment. For every register
  and slot through 1,048,576, sufficient capacity yields exact MOV bytes and
  their decoded machine step. Output and workspace must be distinct arrays;
  all other workspace fields, output slots, caller cells, and host state are
  preserved. `Source.Slot.check?` authenticates CODE and RBP constant lookups
  as well as the complete body and callees. Other frame/workspace wrappers
  still need proofs.
- `Control.Require.emits`: the actual `backend::index::require` body composes
  a conditional branch with displacement two, its local cursor binding, and
  UD2 emission. The source-linked result covers every condition code, arbitrary
  valid output offsets, sufficient capacity, and caller/output framing. Loading
  those emitted bytes produces one branch step: it either skips UD2 or reaches
  the precise fault address, preserving registers, flags, and memory. The BELOW
  instance is exactly `Machine.Index.guard`. General capacity-failure
  composition for this helper remains open; two calls need not reject atomically.
- `Buffer.Emission.append` combines exact byte windows and their integer-slot
  frames without re-executing either emitter. The shared indexed-store rule
  `evaluatesFramedSliceStore` permits a disjoint RHS write footprint; the slot
  wrapper uses it to preserve workspace while its RHS emits into output.
  Reusable constant authentication now lives in `Source/Constant.lean`, not
  parameter lowering. Callers use the moved definitions directly.
- `Lower.Index.Emission.compiles`: the complete actual
  `backend::index::address` body now composes normalization, workspace cursor
  stores, saved descriptor loading, both descriptor-field loads, comparison,
  branch/trap, scaled LEA, and return. For either supported index width and
  sufficient compiler resources, the result is the exact whole machine
  sequence and its Core address/bounds contract. Arbitrary valid offsets,
  signed-negative and full-width runtime failures, both write footprints,
  and the fresh local cursor are accounted for. Source authentication checks
  the entire body, all eight constant references/values, and all callees.
  The shared `Ready.assign` rule carries effectful emitter calls through
  cursor assignments without re-proving ownership for every instruction.

All these theorems pass the standard-axiom audit. The actual extracted Lanius
copy emitter agrees with the proved byte sequence for five sizes and preserves
its caller/output windows. **That source check is concrete execution evidence,
not yet the general source-emission theorem.**

Still open: source composition through the copy loop and remaining work-buffer
routines, actual prologue and parameter/call marshaling, recursive body
simulation, transport correspondence, relocation composition, and general rejection/resource
proofs. Whole checked-address source emission and its Core address/bounds
contract are now connected on the sufficient-capacity domain. The surrounding
subexpression execution/storage relation remains a premise for the recursive
compiler to establish: it must capture the descriptor and index correctly
before calling this routine. General compiler-capacity rejection and the copy
loop's source proof also remain open. The partial machine semantics still
need the remaining arithmetic, control-flow, and call instructions. Mapping,
permissions, canonical addresses, asynchronous events, CET, and host behavior
remain environmental boundaries.

### Earlier extractor census and current proof connection

The exact 18-source census finds 106 reachable internal functions and nine
external runtime functions. The serializer accepts **100 function bodies**;
the closed-program check compiles **97 real extractor functions** with all
their callees. Its scalar/record sampler executes **60 functions on 480 inputs**;
it does not execute the other 37. A dedicated buffer check executes the actual
raw lexer's `scan_one` and `lex_into` call graphs on **96 inputs**, checking
every output-buffer element, aggregate result, input/canary, and caller ABI
state. `lex_into` links 46 functions into 34,777 x86 bytes; `scan_one` links
38 functions into 31,855 bytes. These counts are
execution coverage, not a percentage of the correctness proof.

The indexing fixture also exposed a missing frontend field-assignment path.
The source-to-Core checker and synthesizer now use the existing `PlaceLowers.field`
rule for member targets; the fix adds no new native-decision proof.

The later checkpoints above implement those remaining extractor features.
The next proof target is the real lexer's recursive expression/place simulation,
establishing captured operands and storage for the checked-address contract,
then composing with control flow and calls. Do not expand an isolated instruction
inventory or introduce another backend to bypass this composition.
The immediate caller is `backend::compile::indexed`: allocate a saved slot,
store the captured descriptor pointer, compile the index expression, then call
`backend::index::address`. Its proof needs the allocation/layout invariant and
the recursive expression hypothesis to preserve the captured descriptor and
establish RAX's index representation. The address theorem now discharges the
last phase; it does not establish these caller premises by itself.

Source-to-Core production still runs in Lean. Moving/proving it in Lanius,
runtime/ELF preservation, the whole source-to-x86 theorem, verified extractor
recompilation, and the fast trusted path remain unfinished. Milestone 3's
inherited native dependencies and concrete kernel self-instance also remain
open.

### Verification

- GPU bootstrap: **2.95 s**, `index-lea-bootstrap.log`; the output is an
  untrusted x86-64 executable.
- Independent GNU assembler comparison: **45,938 instructions / 316,153 bytes**,
  including all supported indexed LEA register/scale combinations and disp32,
  **1.39 s**, `index-lea-encoding.log`. Native emitter capacity/rejection and
  untouched-buffer checks also pass.
- Values/calls: **59 Core/native results**, three full-width slice descriptor
  transports, one Core alias check, and 80 malformed-program rejections,
  **6.48 s**, `indexed-values-regression.log`. Includes aggregate returns, nested
  argument effects, odd/even stack padding, recursion, and signed casts.
- Real extractor: **97 closed functions compiled; 60 executed on 480 inputs**,
  **25.52 s**, `indexed-extractor-regression.log`, including exact-source checking.
  Batching native input cases cut this same check from 49.74 seconds without
  reducing coverage.
- Slices/field places: **34 results and 24 matching bounds traps**, **7.43 s**,
  `index-lea-slices.log`. Checks packed offsets, alias effects, effectful
  index/RHS ordering, signed and full-width bounds, and nested field targets.
- Actual raw lexer: **96 Core/native comparisons**, **27.36 s**,
  `index-lea-lexer.log`. Includes malformed tokens, capacity exhaustion,
  exact token records, nonzero slice origins, and untouched buffer windows.
- Existing scalar behavior: **50 results, seven matching traps, 84
  rejections, 12 machine-model frame protocols**, **7.25 s**,
  `index-scalar-regression.log`.
- Parameter optimization: **24 results, 43 rejections**, **3.70 s**,
  `values-parameter-regression.log`.
- Actual backend source/Core integration: **28.24 s**,
  `index-composition-final-source.log`. Includes eleven rejected source
  mutations, frame arithmetic through
  1,048,576 slots, 72 slot emissions, 64 guard emissions and four
  invalid/overflow rejections, 48 memory emissions and 60 atomic rejections,
  24 indexed-address emissions and 12 atomic rejections,
  24 whole-indexing emissions and 28 capacity/kind rejections, five copy
  emissions, return emission/rejection, and Core/native compiler byte equality
  on both frame helpers. The slot, guard, memory/public MOV, and indexed
  emitter proofs are retained;
  whole-indexing success also has the general source-emission/Core-address
  proof; compiler-capacity rejection and copy emission remain concrete evidence only.
- Whole-index source-emission proof: **1.04 s**,
  `index-composition-emission-build.log`; its Core address/bounds connection:
  **1.14 s**, `index-composition-preservation-build.log`, with shared
  dependencies built. The final affected dependency rebuild, source-test
  build, and axiom audit passed in **10.94 s**,
  `index-composition-final-audit.log`. No new assumptions. The production
  Lanius sources and GPU-bootstrap artifacts are unchanged by this proof work.
- General indexed-address source proof build: **1.54 s**,
  `indexed-source-build.log`; shared x86 axiom audit and source-test build:
  **2.14 s**, `indexed-emission-audit.log`. These timings assume shared
  infrastructure is built. No new axioms or native-decision assumptions.
- General memory/public MOV source proof build: **3.34 s**,
  `memory-emission-build.log`. The shared x86 axiom audit passes; the final
  source-test build took **2.84 s**, `memory-proof-audit.log`. Common validation,
  cursor, and header/word proofs are reused by the register and indexed
  emitters. These checks add no axioms or native-decision assumptions.
- Workspace slot source proof: **1.24 s**, `slot-source-build.log`.
  Branch/trap source-to-machine proof: **1.24 s**, `require-machine-build.log`.
  These are general proofs, with shared infrastructure already built; the
  x86 axiom audit checks them and the common slice-store/window rules. The
  final audit/source-test build passed in **3.34 s**,
  `slot-guard-final-audit.log`, with no new assumptions.
- Final affected dependency rebuild and audit: **13.45 s**,
  `indexed-final-audit.log`, including downstream modules invalidated by the
  register-helper documentation correction. The production Lanius sources
  and bootstrap artifacts did not change during the source-proof work.
- Exact-source requirements census: **19.87 s**, `slice-requirements.log`.

The exact backend closure has fourteen files in `backend-sources.txt`.
Current SHA-256 identities:

- GPU-built backend: `caf856ca49cf509e1cb0624a2d6dfd811e576bc5656899e4bb19661a1dec4d86`.
- Singular backend extraction: `d92dd4098e659b60a6c188054d4aa5ddb4d82681d5f39a3e8c8ab782f956876d`.
- Backend source manifest: `2a3f35a13eca3330477042f4be253feeec634578b58cb80c3835254bc059d45d`.

The extractor source and singular self-embedding are unchanged. No command
exceeded two minutes; no Rust, Python, or Wasm implementation was added.
Earlier checkpoints below retain their narrower historical scope.

## First connected compilation case — September 11

`src/backend/parameter.lani` is a 68-line Lanius selector and code generator
for actual Core functions with one to six i32 parameters that return one of
those parameters. It accepts a word transport of the function signature and
Core return/local/sequence/skip syntax. It checks lengths, types, unique local
IDs, and the returned local before mapping the parameter's **position** to
RDI, RSI, RDX, RCX, R8, or R9. It reserves the whole output window, then calls
the existing MOV and RET emitters. Unsupported forms fail explicitly. The
transport does not introduce independent language semantics.

At this checkpoint, `tools/backend.lani` read that transport and wrote raw function bytes. It
builds through the GPU compiler in 2.97 seconds (`backend-bootstrap.log`).
This executable remains untrusted. It is not the final compiler CLI or an
ELF emitter; the temporary native harness still uses GNU as/ld.

The new formal boundary is broader than instruction identity:

- `Lower/Parameter.lean` selects the actual `Core.Function`, retaining exact
  body/signature facts, and serializes it as input data. The serializer does
  not select x86 registers or generate machine instructions. The production
  selector and machine-code generation are in Lanius.
- `Machine/Scalar.lean` defines the initial exception-free, flat-byte-memory
  MOV32/RET subset. Each step requires the decoded instruction bytes to be
  loaded at RIP. MOV clears the upper 32 result bits; RET reads eight bytes
  from the stack, updates RIP, and advances RSP. Paging/permissions, canonical
  address checks, asynchronous events, and CET remain outside this model.
- `Lower/Return.lean` checks concrete emitted bytes and proves preservation
  of the selected Core function body under the stated ABI entry relation.
  The result i32 agrees, RET reaches the stack's return address, RSP advances
  by eight, and other registers, memory, and flags are unchanged.
- `Tests/Parameter.lean` obtains Core from the existing exact-source checker
  for six real Lanius functions, sends the function data to the Lanius backend,
  certifies the resulting bytes, and executes them in the native test harness.
  All six ABI argument positions are exercised with four input sets, including
  signed i32 boundaries and deliberately dirty upper register bits. Incorrect
  opcodes, register selection, width, truncation, and extra code fail byte
  certification. Malformed input transports must fail without stdout bytes;
  renumbering local IDs must not change ABI argument order.

The final check passed all 24 native/Core comparisons, 43 malformed-transport
rejections, and the renamed-local-ID case in 3.24 seconds, including source-pack
validation (`parameter-final-native.log`). The final affected proof and test
build took 1.34 seconds (`parameter-final-proof.log`); the separate standard-axiom
audit took 1.24 seconds (`parameter-audit.log`). These are small-case bootstrap
measurements, not the completed extractor's fast proving workflow.

**Completed for supported input:** the selector now has a general source-linked
proof of termination, safe reads, parameter identity, and caller framing. The
public implementation theorem derives its result from `Checked.words` and
owned input storage, with no selector-execution premise. Whole-function
capacity rejection is proved without output access.

**Still open:** general malformed-transport rejection (the focused rejection
tests are not that proof). The ABI entry relation remains a precondition, not
a proof of caller marshaling or OS loading. The full extractor remains the
target; this subset does not close milestone 4 or any of milestones 5–7.

### Complete supported-input implementation — September 11

`Select/Source.lean` links the existing Core-function serializer to the selector's
input domain. `Select/Syntax.lean` describes the complete command; source
authentication checks it against the entire current Lanius body. The proofs in
`Select/Loops.lean` cover duplicate checking and parameter search for arbitrary
distinct, representable local IDs, including unsorted IDs. `Select/Execution.lean`
adds every header/length/type/body guard and both return-body layouts.
`Select/Frame.lean` converts this execution to the actual Core call, preserves
input and caller cells, and hides fresh locals. Heap, raw views, and the host
world are unchanged.

`Lower/Implementation.lean` discharges the previously explicit selector premise
inside the public compiler's actual entered state. `compile_function` proves
the exact output bytes; `compile_function_certified` constructs their existing
Core/machine preservation certificate without an output checker. The separate
`compile_function_rejects_capacity` theorem covers failed reservation even with
an unusable output value. Input/output aliasing is permitted: selection finishes
before emission begins.

The standard-axiom audit initially caught an inherited native proof of i32
negation of one. `ExecutionRules.wrapSigned_i32_neg_one` now uses ordinary
kernel arithmetic. Rebuilding affected dependencies and auditing the combined
theorems took 22.06 seconds (`selector-kernel-proof.log`); the final affected
proof/test build took 4.64 seconds (`selector-completion-proof.log`). The focused
actual-source check passed 102 successful calls, 288 rejection calls, and 10
ABI mapping calls in 4.61 seconds (`selector-final-source.log`). New cases use
unsorted IDs containing zero and the exact signed-i32 maximum. No command
exceeded two minutes.

The Lanius sources and five-source embedding are unchanged. The inherited
source-validation trust boundary, concrete self-instance, full ISA/runtime
coverage, and milestones 3–7 acceptance obligations remain open. The historical
lowering checkpoint below describes the composition layers before the selector
premise was discharged; use the public implementation theorems above.

### Earlier source-linked lowering checkpoint — September 11

The singular five-source backend pack adds `backend/parameter.lani` to the four
existing emitter sources. `Source/Lower.lean` authenticates the complete
`argument_register` and `compile` bodies, their signatures, actual constant
lookups, and callee identities in that same checked program. The selector has
an exact typed stateful view derived from its source body; obtaining that view
does not prove its algorithm correct.

The new implementation proofs cover:

- `Lower/Arguments.lean`: the complete constant-return chain, including
  out-of-range rejection, and the source-linked ABI mapping call. Constant
  pool IDs need not equal architectural register numbers.
- `Lower/Emission.lean`: whole-function reservation, the actual MOV call,
  returned-cursor binding, and actual RET call. The final buffer contains
  exactly the machine model's bytes; no helper execution is assumed.
- `Lower/Compile.lean`: size selection, lexical scopes, mapping and emission
  compose into the public `compile_selected` theorem. The sole remaining
  algorithmic premise is the selector call in the actual entered compiler
  state returning the correct position with its frame preserved.
- `Lower/Reject.lean`: complete-function capacity rejection and selector
  failure propagate through the public compile call without output access.
  Capacity rejection allows an invalid output value. The selector's result
  and its own frame remain explicit premises on both paths.
- `Lower/Preservation.lean`: `compile_certified` constructs the existing
  Core/machine preservation certificate for the actual output-buffer slice
  from the implementation theorem, without calling `certify?` or assuming
  acceptance. Output length, untouched slots, and caller/host/heap frames
  are retained. This is conditional composition until the selector is proved.

The final proof/test build and standard-axiom audit passed in 2.44 seconds
(`parameter-lowering-final-proof.log`). Source integration passed 90 successful
full compile calls, 288 rejection calls, and 10 ABI mapping calls in 4.77 seconds
(`parameter-lowering-source.log`). It covers all parameter counts 1–6 and
positions, both Core body forms, local IDs near the signed-i32 limit, exact-fit
and one-short buffers, negative/overflowing cursor domains, malformed transports,
dirty caller frames, and six input/output-alias cases. Rejected calls receive
an unusable output value. Swapped callees and reversed mapping bodies fail
source authentication. These timings include a small interpreted integration
corpus, not the final trusted-extraction workflow.

No Lanius source or native executable changed for these proofs. The existing
four-source hashes and embedding still match; the new five-source embedding is
`e164dfe844912599e90caf2d2826d929676cb10ead25d0cb2d7fd25978ea4173`.
No new native proof dependency, Rust, Python, or Wasm implementation was added.
The existing source-validation trust boundary and milestone-3 findings remain.

## Encoding boundary

The instruction emitter owns byte encodings, not register allocation or Core
lowering. It uses the sixteen ordinary x86-64 general-purpose registers and
32/64-bit integer operations, plus byte loads/stores. Memory operands initially
use a base register and signed disp32; indexed addresses are computed explicitly.
Branches and calls use fixed rel32 encodings, avoiding branch relaxation and
layout iteration. This trades a few bytes for simpler layout/proof obligations.

Buffers follow the extractor's existing i32-per-byte convention. A caller owns
the slice and supplies a capacity no larger than its actual length. A successful
emission returns the next cursor; invalid inputs or insufficient space return
-1 without modifying the buffer. Cursor arithmetic is checked by subtraction
before addition. Relative targets are offsets in a single image below 2 GiB.

The architectural reference is Intel's Software Developer's Manual, volume 2:
[instruction encoding and semantics](https://www.intel.com/content/www/us/en/developer/articles/technical/intel-sdm.html).
Linux calling and process conventions must be checked against the
[x86-64 psABI](https://gitlab.com/x86-psABIs/x86-64-ABI) before implementing that
boundary. The GPU compiler's emitter is bootstrap code, not the specification.

## Verification scope

Use fast focused checks: cross-product register tests, memory-base special cases
(rsp/r12 and rbp/r13), signed displacements, width and byte-register behavior,
forward/backward branches, relocation bounds, buffer canaries, and rejection
without writes. Independent assembly comparison checks encodings; native runs
check observable instruction interactions. Formal proofs must separately link
the actual Lanius source to those encodings and to the machine semantics.

## Instruction-emitter checkpoint — September 10

The production component is 313 lines in four Lanius modules:

- `src/x86/register.lani`: named registers, widths, and REX construction.
- `src/x86/buffer.lani`: subtraction-based reservations and little-endian words.
- `src/x86/encode.lani`: register/immediate operations, memory, shifts, division,
  multiplication, negation, and sign/zero extension.
- `src/x86/control.lani`: conditions, rel32 calls/jumps/branches and patching,
  stack operations, return, syscall, traps, and dividend sign extension.

Only 32/64-bit integer operations and byte memory operations are implemented at
this boundary. This is not a claim that every Core operation is compiled. In
particular, storage/lifetime lowering, full instruction semantics, Core control
flow, call conventions, ELF emission, and runtime refinement remain open.
The low/high arguments to `immediate` are the two bit-pattern halves of a
64-bit immediate; the 32-bit form uses only the low half. The low-level
`store_word` and REX helpers require the caller's reservation/operand invariants.

Evidence:

- GPU-bootstrap builds of the Lanius encoding and execution test producers:
  2.43 and 2.53 seconds, both x86-64 ELF. No Rust/Python implementation added.
- 30,578 instruction encodings (193,273 bytes) match GNU as exactly in 1.18
  seconds. Cases include every register pair, both widths, signed disp32,
  all conditions, near transfers, and 259 consecutive small displacements
  across all memory bases. Each emission also tests insufficient capacities,
  exact-fit capacity, and buffer framing. Invalid operands reject without
  writes. A further 957 patch cases check displacement decoding and framing.
- 255 bytes of generated x86 execute successfully in 0.88 seconds, exercising
  64-bit and byte memory, signed quotient/remainder, a backward loop, a forward
  call, return, a 64-bit shift, and patched failure edges. GNU ld supplies a
  **test-only** ELF wrapper; this does not complete Lanius ELF emission.
- `formal/Lanius/X86/Word.lean` proves little-endian round-trip, injectivity,
  read-after-write, and preservation outside the four written bytes.
  `Relative.lean` proves signed-i32 displacement bounds, exact target recovery
  for arbitrary image bases with 64-bit wrapping, patched targets, and the
  buffer reservation condition. `Word/Core.lean` connects this representation
  to existing Core i32 storage and its proved shift/mask byte expressions.
  `Tests/Proofs.lean` rejects any nonstandard axiom in these results.
- Existing Lanius extraction of the four production modules took 0.19 seconds;
  exact source/syntax/Surface/typed-Core validation took 3.40 seconds.
  `X86EncodingExtracted.lean` has SHA-256
  `0f183c9f0199019f891aabc86956c69a178f33e8166c295d049aee08b275bf63`.
  This validation executes natively, with the same explicit trust limitation
  as milestone 3. The original extractor/self-embedding was not changed.

### Source-linked emitter proofs — September 10

Nineteen actual Lanius functions now have general execution contracts. These are
proofs about their checked Core bodies, not assumptions that calls succeeded.

| Lanius function | Proved contract |
|---|---|
| `register::valid` | Executes for every integer input; accepts exactly register numbers 0 through 15; preserves caller state |
| `register::width_valid` | Executes for every integer input; accepts exactly 32 or 64; preserves caller state |
| `register::rex` | For validated operands, returns either the precisely characterized absence sentinel or a byte decoded as the intended W/R/X/B fields; preserves caller state |
| `encode::register_form` | Executes validation, REX construction, size selection, reservation, and exact prefix/opcode/ModR/M stores; rejects invalid operands or insufficient space before output access; restores all three temporary scopes |
| `encode::move_register`, `multiply`, `sign_extend_i32`, `zero_extend_byte`, `negate` | Complete source-linked calls select the architectural operand roles, opcode and width, including forced byte-register REX; success and operand/capacity rejection preserve caller frames |
| `buffer::fits` | The subtraction-based check equals the mathematical range condition, including negative and exhausted inputs; no output access or caller-memory changes |
| `buffer::store_word` | The reserved four slots contain the exact little-endian Core i32 bytes; every other buffer slot is preserved |
| `control::patch_relative` | Executes its real `fits` and `store_word` calls; invalid fields/targets return -1 before output access; success changes only the displacement field |
| `control::return_near` | Exact source execution emits bytes decoded as unprefixed 64-bit-mode near RET |
| `control::syscall` | Exact source execution emits bytes decoded as SYSCALL |
| `control::trap` | Exact source execution emits bytes decoded as UD2 |
| `control::relative` | Reserves the full instruction before writes; emits its header and rel32 field through the real word-store call; restores both temporary locals |
| `control::jump` | Actual source call emits a decoded near JMP with the requested target calculation |
| `control::call` | Actual source call emits a decoded near CALL with the requested target calculation |
| `control::branch` | Actual source call emits the selected Jcc for all 16 conditions; invalid conditions reject before calling the helper or accessing output |

`Buffer.patch_lands` reads the resulting buffer's bytes, decodes the signed
displacement, and proves the requested target calculation at every image base,
including modulo-2^64 arithmetic. It does not assume the intended displacement
was written. Instruction-boundary and executable/canonical-target validity are
separate obligations; a target at the emitted length can still be a data/end
label rather than executable code.

The fixed emitters share one source-shape family and one induction over their
byte stores (`Source/Fixed.lean`, `Buffer/Fixed.lean`).
`Control.fixed_emits` composes that actual-source execution with instruction
decoding. This does not model executing RET, the OS handling SYSCALL, or
delivering UD2's exception. `Control/Decode.lean` recognizes the unprefixed
control subset; unsupported/truncated input is not classified as an invalid
x86 instruction. Its displacement lemmas cover every i32 bit pattern, every
condition nibble, and arbitrary trailing bytes.

The parameterized control emitter is now connected as well.
`Buffer.Relative.succeeds` and `rejects` prove the complete internal function,
including size selection, short-circuit rejection, the optional second opcode
byte, word emission, and lexical-scope restoration. `Control.direct_success`,
`direct_reject`, `branch_success`, `branch_invalid`, and `branch_reject` derive
the public wrappers' behavior from those proved calls. None assumes that the
helper executed correctly or that a validator will accept its output.

The successful public contracts retain `Transfer.Emission`: the resulting
buffer decodes to the requested instruction, keeps its original length, changes
only the instruction window, and yields the requested target address when the
displacement is read back from that window. Target arithmetic holds at every
image base with 64-bit wrapping. Forward targets may lie beyond the current
buffer, but must fit a nonnegative signed-i32 image offset. The theorem does not
claim that every such target is mapped, canonical, or executable. Actual flag
testing for Jcc and return-address stack writes for CALL remain instruction
execution obligations, not emission guarantees.

The source checker retains the original source-pack construction equation in
`CheckedBuffer.produced`, and authenticates signatures, complete bodies, and
callee identities against that same program. It does not extract or synthesize
the sources a second time. All nineteen contracts restore caller locals and preserve
unrelated old cells and host observations, while allowing fresh parameter cells.
Their successful write domains use a well-formed Core state and a root-backed,
zero-offset output slice. Capacity/emitted length cannot exceed its storage or
signed-i32 range; callers reserve `store_word`'s four slots. Arbitrary sub-slice
offsets and native allocation/runtime behavior are not claimed here.

Focused evidence:

- The final affected proof/source-test build passed in 2.44 seconds
  (`x86-control-word-proof.log`). All new execution, frame, relocation,
  serialization, and decoder theorems pass the standard-axiom-only audit.
  Source authentication adds no assumptions beyond its existing checker
  constituents; this does not remove milestone 3's concrete/native boundary.
- Actual-source checking passed in 4.61 seconds (`x86-decoded-source-check.log`):
  180 reservation calls, 182 word stores, 6,143 patches, and 1,041 fixed-emitter
  calls. Checks cover dirty-buffer framing, exact-fit and insufficient capacity,
  signed integer boundaries, rejection with a deliberately non-slice output,
  decoded fixed instructions, and patched targets at four image bases.
  Missing, shifted, duplicated, swapped, and wrong-opcode source shapes reject.
- Decoder checks also cover negative displacements, the signed-i32 endpoints,
  trailing instructions, truncation, and unsupported prefixes/return forms.
- Production Lanius sources and their singular four-source embedding are
  unchanged; the recorded embedding hash still matches. No Rust or Python
  implementation was added. No command exceeded two minutes.

The subsequent relative-transfer checkpoint passed:

- Final public-contract, layout, source-test, and axiom-audit build: 2.84 seconds
  (`x86-transfer-contract-proof.log`). All new results use standard Lean axioms;
  source authentication adds no trust beyond its existing constituents.
- Actual-source integration: 9.21 seconds (`x86-relative-source-check.log`).
  In addition to the previous 7,546 calls, 24,726 public relative-transfer calls
  cover JMP, CALL, every condition nibble, dirty caller state, exact-fit and
  insufficient capacity, negative cursors/targets, signed-i32 boundary rejection,
  backward targets, and forward targets up to 2^31-1. Successful bytes are read
  back and decoded; rejected calls receive a deliberately non-slice output.
  Swapping the authenticated CALL/JMP opcodes is rejected.
- The source bodies and embedding are unchanged, with hashes rechecked. No GPU
  rebuild or full extractor self-check was needed for these proof-only changes.
  Every command stayed below two minutes; `git diff --check` passed.

The register/REX checkpoint is complete:

- `Register.validation_call` proves both actual validator bodies for every
  integer input. `register_domain` and `width_domain` connect acceptance to
  finite register numbers and the two supported widths.
- `Register.rex_call` proves the actual initializer, conditional compound
  assignment, early-return condition, and final return. Its fresh temporary
  cannot alias the parameters or caller storage; the returned call restores
  caller locals, old cells, and the host/heap frame.
- `Register.Rex` follows Intel SDM volume 2A section 2.2.1/Table 2-4. The model
  proves encode/decode round-trip, prefix-byte bounds, and the exact omission
  condition. The backend's X bit is zero. A forced byte-register prefix is
  retained even when its byte is just 0x40. This is a prefix-encoding contract,
  not a claim about operand size for every x86 opcode. `rex` itself does not
  validate its arguments; the public emitters must establish its domain.
- Actual-source integration passed in 8.71 seconds
  (`x86-register-source-check.log`): 54 validator calls cover register and width
  boundaries plus signed-i32 extremes; 1,024 REX calls cover all register/base
  pairs, widths, and force-byte flags. Tests inspect returned bits independently
  of the additive model and preserve a dirty caller frame. The previous 32,272
  buffer/control calls also pass. These are focused integration timings, not
  the final trusted-extraction benchmark.
- The final proof/source-test build passed in 4.44 seconds
  (`x86-register-final-proof.log`), including the standard-axiom audit. Source
  authentication accepts the exact three existing Lanius bodies in the same
  four-source embedding; no GPU rebuild or self-extraction is needed.
  All four source hashes and the embedding hash still match the recorded
  identities. No new native proof dependency, Rust, or Python was added;
  every command stayed below two minutes and `git diff --check` passed.

The shared register-form checkpoint is complete:

- `Encode.succeeds` connects the whole actual `register_form` body to exact
  REX/escape/opcode/ModR/M bytes, the returned cursor, and the caller frame.
  Its `Config.Emission` postcondition preserves buffer length and every slot
  outside the emitted instruction window, and reads the exact bytes back from
  that window. The proof executes the real validator, REX, and reservation
  calls; it does not assume successful helper execution or output acceptance.
- `Encode.rejects_invalid` proves short-circuit rejection for invalid register
  or width inputs. `Encode.rejects_capacity` proves rejection for negative,
  invalid, or insufficient reservations. Both allow an arbitrary output value
  and preserve caller cells and host/heap state, so they establish rejection
  before output access rather than relying on a valid buffer backing.
- The encoding domain consists of valid 32/64-bit operands, registers 0–15,
  and primary or 0F-escaped opcode bytes. The internal helper does not validate
  opcode identity; callers select supported instructions and must justify
  operand roles and byte-register restrictions. Successful output requires
  owned root-backed storage, capacity no larger than storage, and enough room
  within signed-i32 cursor limits. Capacity rejection requires capacity at most
  2^31-1. This does not yet establish instruction execution semantics.
- `Encoding.modRM_fields` proves the mod=11 and low-register fields, and
  `extend_register` reconstructs the full register number from low and extension
  bits. Prefix/escape ordering, byte bounds, and instruction length are proved
  independently of the actual-source execution rules.
- `Buffer.Locals` retains input cell identities below a temporary-allocation
  frontier; equal numeric input/cursor values cannot justify aliasing them.
  `Buffer.Cursor` proves optional prefix writes and cursor increments with
  disjoint buffer/temporary effects. These rules accept the source's local IDs
  and can be reused by the immediate and memory emitters. Size counting is
  shared by the success and capacity-rejection proofs.
- Final proof/source-test build and standard-axiom audit: 3.54 seconds
  (`x86-form-final-proof.log`). Actual-source integration: 20.88 seconds
  (`x86-form-final-source-check.log`). The new 34,834 calls cover all register
  pairs, widths and force-byte flags across 17 primary/escaped opcode choices,
  exact-fit and one-short capacity, signed-i32 rejection boundaries, and dirty
  caller locals including the emitter's three shadowed temporary names.
  Expected bytes use independent bit-field construction, not the additive
  model. The previous 33,350 calls also pass. These timings include a large
  interpreted test corpus, not just one extraction check or the final trusted
  per-program path.
- All production-source and embedding hashes still match. No GPU rebuild,
  repeated self-extraction, Rust, or Python was needed. No new native proof
  assumption was added; the existing concrete source-validation trust boundary
  is unchanged. Every command stayed below two minutes; `git diff --check`
  passed.

The five direct register wrappers are now connected to the shared contract:
MOV, IMUL, MOVSXD, MOVZX, and NEG. Their actual-source success and rejection
proofs preserve caller frames. The focused source check passed 5,198 new wrapper
calls and the existing corpus in 23.95 seconds (`x86-wrapper-source-check.log`).
Generic guarded binary/shift wrapper proofs also build, but their source-checker
integration remains open.

The selector premise is now discharged by the implementation checkpoint above.
The next work extends that connected path to frame-based scalar locals and
operations, adding emitter proofs as
those features need them. Reuse the proved reservation, byte-store, word-store,
and decoder contracts. The remaining emitter bodies and instruction execution
semantics are still required for the full backend; neither the nineteen source
contracts nor differential tests complete that work.

### Bootstrap limitation found

The GPU compiler's `shaders/parser/hir/literal_values.slang::parse_uint_token`
consumes decimal digits only. A hexadecimal `ADD` opcode constant was compiled
as zero, causing the invalid-operation rejection test to fail. Diagnostics
confirmed the zero value. The Lanius lexer supports hexadecimal literals, but
that does not fix GPU numeric lowering. The new emitter therefore uses named
constants with decimal values. This turn did not change the GPU compiler or
silently treat its executable as trusted. Decimal-source emission subsequently
matched the independent assembler corpus.

### Focused commands

Run each command with the user's two-minute timeout. These are separate builds
and checks, not fragments of one overlong artifact check. The pinned Lake is
`/home/andrew-peterson/.elan/toolchains/leanprover--lean4---v4.33.1/bin/lake`.

```sh
target/debug/laniusc --emit x86_64 --source-root verified_compiler/src --stdlib-root stdlib -o target/verified-compiler/x86-encode-test verified_compiler/tests/x86/encode.lani
target/debug/laniusc --emit x86_64 --source-root verified_compiler/src --stdlib-root stdlib -o target/verified-compiler/x86-execute-test verified_compiler/tests/x86/execute.lani

# Use the pinned Lake for each line below.
lake -d formal env lean --run formal/Lanius/X86/Tests/Encoding.lean target/verified-compiler/x86-encode-test target/verified-compiler/x86
lake -d formal env lean --run formal/Lanius/X86/Tests/Native.lean target/verified-compiler/x86-execute-test target/verified-compiler/x86
lake -d formal build Lanius.X86.Tests.Proofs Lanius.X86.Tests.Source

target/verified-compiler/lanius-extractor verified_compiler/src/x86/register.lani verified_compiler/src/x86/buffer.lani verified_compiler/src/x86/encode.lani verified_compiler/src/x86/control.lani > target/verified-compiler/X86EncodingExtracted.lean
lake -d formal env lean --run target/verified-compiler/X86EncodingExtracted.lean verified_compiler/src/x86/register.lani verified_compiler/src/x86/buffer.lani verified_compiler/src/x86/encode.lani verified_compiler/src/x86/control.lani
lake -d formal env lean --run formal/Lanius/X86/Tests/Source.lean target/verified-compiler/X86EncodingExtracted.lean verified_compiler/src/x86/register.lani verified_compiler/src/x86/buffer.lani verified_compiler/src/x86/encode.lani verified_compiler/src/x86/control.lani

# The backend closure includes the real Lanius selector and compile routine.
target/verified-compiler/lanius-extractor verified_compiler/src/x86/register.lani verified_compiler/src/x86/buffer.lani verified_compiler/src/x86/encode.lani verified_compiler/src/x86/control.lani verified_compiler/src/backend/parameter.lani > target/verified-compiler/ParameterBackendExtracted.lean
lake -d formal build Lanius.X86.Tests.Lower Lanius.X86.Tests.Proofs
lake -d formal env lean --run formal/Lanius/X86/Tests/Lower.lean target/verified-compiler/ParameterBackendExtracted.lean verified_compiler/src/x86/register.lani verified_compiler/src/x86/buffer.lani verified_compiler/src/x86/encode.lani verified_compiler/src/x86/control.lani verified_compiler/src/backend/parameter.lani

# Current linked backend and exact source-linked frame/compiler integration.
mapfile -t backend_sources < verified_compiler/backend-sources.txt
target/debug/laniusc --emit x86_64 --source-root verified_compiler/src --stdlib-root stdlib -o target/verified-compiler/lanius-backend verified_compiler/tools/backend.lani
target/verified-compiler/lanius-extractor "${backend_sources[@]}" > target/verified-compiler/BackendExtracted.lean
lake -d formal build Lanius.X86.Tests.Proofs Lanius.X86.Tests.Frame Lanius.X86.Tests.Scalar Lanius.X86.Tests.Values Lanius.X86.Tests.Extractor
lake -d formal run check-backend target/verified-compiler/lanius-backend target/verified-compiler/frame-native target/verified-compiler/BackendExtracted.lean
target/verified-compiler/lanius-extractor verified_compiler/tests/x86/scalars.lani > target/verified-compiler/ScalarsExtracted.lean
ulimit -c 0
lake -d formal env lean --run formal/Lanius/X86/Tests/Scalar.lean target/verified-compiler/lanius-backend target/verified-compiler/ScalarsExtracted.lean verified_compiler/tests/x86/scalars.lani target/verified-compiler/scalar-native
target/verified-compiler/lanius-extractor verified_compiler/tests/x86/values.lani > target/verified-compiler/ValuesExtracted.lean
lake -d formal env lean --run formal/Lanius/X86/Tests/Values.lean target/verified-compiler/lanius-backend target/verified-compiler/ValuesExtracted.lean verified_compiler/tests/x86/values.lani target/verified-compiler/values-native
target/verified-compiler/lanius-extractor verified_compiler/tests/x86/strings.lani > target/verified-compiler/StringsExtracted.lean
lake -d formal env lean --run formal/Lanius/X86/Tests/Strings.lean target/verified-compiler/lanius-backend target/verified-compiler/StringsExtracted.lean verified_compiler/tests/x86/strings.lani target/verified-compiler/strings-native

# Read-only implementation census over the authenticated extractor call graph.
mapfile -t self_sources < verified_compiler/source-closure.txt
target/verified-compiler/lanius-extractor "${self_sources[@]}" > target/verified-compiler/SelfCompactRequirements.lean
lake -d formal build Lanius.X86.Tools.Requirements
lake -d formal env lean --run formal/Lanius/X86/Tools/Requirements.lean target/verified-compiler/SelfCompactRequirements.lean "${self_sources[@]}"
lake -d formal env lean --run formal/Lanius/X86/Tests/Extractor.lean target/verified-compiler/lanius-backend target/verified-compiler/SelfCompactRequirements.lean target/verified-compiler/extractor-native "${self_sources[@]}"
```
