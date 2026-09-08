# Self-hosted extraction and verified x86 compilation

Current execution plan: [Milestone 3](MILESTONE3.md). It defines ordered
completion boundaries, credits existing proofs, and names the one active
step. Follow it instead of the chronological checkpoint notes below.

The user goal is the complete seven-step pipeline below. The old Rust
exporter has been removed; the extraction implementation is in Lanius.
The earlier self-extraction-only goal is superseded by this expanded scope.

All executables and execution tests in this workflow target x86-64 Linux ELF,
including the untrusted GPU bootstrap. Do not use a Wasm fallback. The existing
GPU compiler is bootstrap machinery, not the verified compiler/backend in
Lanius required by milestone 4.

The first native tests exposed missing conditional-call lowering, runtime-length
array indexing, a six-slot argument ABI limit, and an incoherent raw-array
layout. Conditional lowering, direct-call stack arguments, checked fat-slice
access, and coherent packed `i32` arrays now pass focused native execution
tests. The checked-in Lanius syntax extractor builds and runs as a static
x86-64 ELF. It emits one compact logical `ArtifactPack` for the exact 18-file
source closure recorded in `source-closure.txt`. Lean decodes it through fixed
general infrastructure and returns proof-carrying syntax evidence plus an
independently reconstructed, origin-checked Surface program for every unit.
This completes milestone 2. The milestone-3 self-embedding now validates exact
sources, syntax, reconstructed Surface, proof-producing source-to-Core
lowering and whole-program x86 Core typing. A separate extractor-specific
checker links the declared source `main` to a well-formed Core executable
entrypoint and checks its return codes. General Core preservation proves memory
safety for every terminal execution of an entrypoint accepted by that checker.
Ordinary extracted programs need neither that entrypoint nor those return codes.
The extractor's exact success/failure I/O refinement theorem is still absent,
so milestone 3 remains incomplete.

The derivation reader now has a complete success-path execution proof from
caller buffers and scalar arguments. It executes the input guard, base
initializer, workspace guard, child-count lookup, count and output-capacity
guards, root metadata lookups, header writes, cursor allocation, backpointer
loop, final seed validation, and return of the child count. It derives every
field read, guard, temporary binding, output store, and cursor update. The invariant proves termination
and exact child-record order, preserving the header and trailing capacity.
Fresh cursor allocations supply the non-aliasing conditions; closing their
scopes leaves only output-buffer writes visible to the caller. The complete
record matches `derivationRecordWords` and preserves both surrounding buffer
regions. The complete success-path module checked in 2.18 seconds with shared
dependencies built; its axiom audit found only Lean's standard logical axioms.
The source checker requires exact equality with the entire reader body,
with a statement-equality theorem connecting the checker to the execution
proof. The current self-extraction passed that check in 20.89 seconds.
The complete reader's function-dependency closure is also proved.
The execution proof uses standalone parser symbol coordinates. A checked
reader link now verifies the accessor's program link and exact relocation
of the complete reader body into the current extractor. Execution and
call-boundary transport rules are proved, and the current self-extraction
passed this link check in 20.68 seconds. A runtime constructor connects
the success-path theorem to the checked source's local coordinates.
Caller-state and output-postcondition composition, and the extractor's
full success/failure I/O contract, remain unfinished.
These results do not complete milestone 3 or the x86 backend proof.

The extractor embeds the exact grammar as one hexadecimal string token, decodes
it in Lanius, and uses dynamically allocated native pointer/length slices.
Chunked host I/O replaced the former one-syscall-per-byte bridge. Its output is
one compact hexadecimal string decoded by
`Lanius.Extraction.CompactArtifact`; malformed counts are bounded by the
remaining payload before allocation or iteration. This avoids both the old
121-file generated proof forest and millions of generated Lean constructor
syntax nodes. The process now assembles the entire module before its single
logical stdout write, so pre-write failures cannot expose a partial
certificate. The generated Lean checker then rereads its ordered input paths
and requires the decoded pack's source names and bytes to equal those
independent inputs. It then reconstructs Surface from the accepted parse
artifacts and checks all Surface-origin claims. Closure selection and bootstrap
invocation remain outside the proved Lanius execution semantics, while the
exact execution/output relation and general extractor correctness theorem keep
milestone 3 incomplete.

`Lanius.Extraction.ExtractorContract.Success` now fixes the execution theorem's
target: exact rendered stdout, exact ordered input files, accepted syntax
evidence, preserved source files and arguments, and no leaked file handles.
It intentionally does not require type correctness of the extracted input:
`AcceptedSuccess` adds that obligation only after the typed-Core checker
accepts. A type-error fixture guards this boundary.
The source-bound compact checker also retains independently reconstructed
Surface values with their validity proofs, so subsequent lowering can consume
them without reconstructing a second copy.

The output proof now covers signed-word byte serialization, the complete Core
packing loop (including termination, input preservation, and write footprint),
heap read-after-write, disjoint-view synchronization, and exact stdout for a
successful Core host call. The clearing loop is also proved and establishes
the zeroed-word precondition. A proof-producing structural check locates both
exact loops in the checked source `main`, without copying its body.
`stdout_after_packing` derives the packed buffer and its encoding from the
loop execution. It requires initial ownership, valid registered blocks, and
distinct view addresses; heap well-formedness then supplies non-overlap.
Pointer exposure preserves distinct addresses, while raw-slice construction
requires a fresh address. The enclosing source execution must still establish
these entry conditions and connect the phases in order.
These results do not yet prove the extractor's full execution contract.

The input proof covers the actual Core host read through heap synchronization
and scratch-word refresh. The complete unpacking loop is proved terminating;
it copies exactly the refreshed bytes while preserving earlier chunks, unused
output capacity, and the packed scratch buffer. `unpack_after_read` composes
these proofs, deriving the copied bytes from the file contents rather than
assuming a correct scratch encoding. The enclosing file-reader guards must
still establish its ownership and capacity preconditions. The source checker
links this exact loop to `verified::byte_io::read_file` in the self-embedding.
The read-preservation theorem also derives coherence for other in-range i32
buffers and proves they survive both synchronization passes unchanged. Raw
slice allocation preserves unique backing roots; exposing an existing slice
pointer preserves the registry. The capacity-probe branch is proved to compute
the bounded, positive request size and is linked to the checked source.
The outer reader loop, guard composition, and caller-side handle lifecycle
still need to be composed with these stage proofs.

Frontend proof reuse now has a proof-producing global-ID relocation checker.
Against the current self-embedding, all 18 old lexer functions, 6 token-scan
functions, and 20 parser functions match their relocated definitions; so do
49 constants and 5 structure layouts. Both sides use x86-64 Core. Type IDs use
an invertible permutation, not a non-surjective offset, so pre-existing caller
values can be transported too. This complete source/link check took 19.64 s.

The generic relocation lemmas cover scalar operations, nested assignments,
parameter binding and call state, enum matching, slices, i32 encoding, and
heap/view synchronization. Their focused regressions and axiom audit pass
(1.34 s with dependencies already built); production proofs use only Lean's
standard axioms, not native evaluation as a proof oracle. The full fuel
induction is now proved: `Semantics.Relocation.Execution.evaluates` and
`executes` preserve successful executions of internal modules in the larger
program. This covers expressions, calls, memory operations, statements, and
loops; the internal-call condition is checked with proof-producing evidence.
The complete transport build took 9.38 s. Checking its assumptions against the
three actual frontend modules and exact self-sources took 20.11 s. Its axiom
audit contains only `propext`, `Classical.choice`, and `Quot.sound`.
The merged nine-module frontend has checked name-based cross-module mappings.
`Semantics.Restriction` now proves that removing unreachable functions preserves
successful execution with exactly the same state and result. Its checker
requires every retained function body to call only retained functions, including
calls nested in arguments, mutable places, and loop bounds. Combined with
relocation, `Semantics.Relocation.Link` transports the dependency-closed portion
of an old program into the current program. The self-source check accepted
50 of the old merged frontend's 54 functions and all 92 constants in 21.87 s.
The four historical canonicalization helpers are explicitly excluded; their
replacement is proved separately below. No changed body is assumed equivalent.
Focused closure regressions pass, and the restriction theorems use only
`propext`, `Classical.choice`, and `Quot.sound`. The old pack's source-byte
assertion now covers only its eight unchanged units, not the replaced
canonicalizer. Exact current-source authentication remains in the self checker.

The scanner-model mismatch exposed by rebuilding the old public raw-lexer
contract is repaired. `LexerStreamOffsets.scanOne_eq_scanOneAt` (in the
`Compiler.Lexer` namespace) proves that suffix scanning and absolute-offset
scanning agree for every source and start position. Supporting lemmas cover
identifiers, whitespace, quoted literals, comments, numeric literals, symbols,
and failure offsets. The equivalence proof uses only `propext` and `Quot.sound`.
All eight affected `RawLexer.ScanOne.Execution` proofs now pass; that focused
build took 4.15 s. The initial full public-contract rebuild hit the 29-second
limit, with the old `Symbol.Execution` module taking 19 s.
Profiling traced a substantial part of that cost to 50 native decisions for
constant IDs. The lookup now matches signed-i32 constants directly, avoiding
opaque generic value equality; all 50 decisions use ordinary kernel reduction.
The focused rebuild, including the checked source-structure proof, passed in
11.26 s. No Lanius scanner behavior changed.
The next full-contract attempt exposed `Symbol.CompilerAgreement` at 23 s.
That proof enumerated 24 × 256 × 256 three-byte inputs. A new kernel-checked
equivalence shows that the third byte matters only when it is `=`, reducing
the enumeration to 24 × 256 × 2 without weakening coverage. The agreement
declaration now checks in 4.4 s, and the complete `LexInto.EndToEnd` build
passes in 5.67 s. The reduced finite agreement checks still use the legacy
native-decision mechanism; this is not a claim that the old frontend's entire
trust footprint is kernel-only.

`RawLexer.LexInto.Linked.call_evaluates` now transports the existing complete
raw-lexer call theorem through a checked dependency-closed link. Invocation
preconditions remain in the original state coordinates; the executed call and
result state are explicitly relocated. The exact self-source integration check
now links `verifiedFrontendCore`, the program used by that theorem, rather than
a separately decoded JSON copy. It requires the raw-lexer entrypoint to remain
in the retained set and instantiates the linked call theorem. This check passes
in 24.06 s. Caller-state composition with the canonicalizer, parser contract
instantiation, and the full extractor I/O theorem remain unfinished.

The linked raw-lexer theorem now also returns ownership of the unchanged
source buffer and the exact encoded emitted-token prefix followed by unchanged
spare capacity. `LexInto.run_records_prefix` proves that format directly from
the lexer's three stores per token; it matches the canonicalizer's input
encoding and also covers prefixes emitted before failure. The prefix proof
checked in 0.32 s, and the new ownership/prefix audit contains only standard
Lean axioms. This strengthens the existing theorem rather than adding a weaker
compatibility wrapper. One caller-side limitation remains explicit: the old
raw-lexer model fixes source and record backing cells to 0 and 1. Global-ID
relocation preserves cell addresses, so these results do not yet cover the
extractor's arbitrary buffer allocation layout. That address generalization
must be proved before claiming complete caller-state composition.

`Semantics.CellRenaming` now provides the state-level foundation for that
generalization. A bounded permutation can place two distinct model buffers at
arbitrary distinct existing caller cells, including overlapping placements,
while fixing every future allocation identity. Renaming covers nested slices
and references, local bindings, cells, and registered view roots; native byte
addresses, heap contents, and the host world remain unchanged. Kernel proofs
establish reversibility, cell lookup, state well-formedness, and compatibility
with local-cell and temporary allocation. Focused checks cover all 56 distinct
destination pairs below eight, nested references, native-address preservation,
and round trips. The state module checked in 0.43 s and the tests/audit in
0.46 s, using only standard Lean axioms. The complete evaluation-transport
theorem and its lexer instantiation are not yet proved.

Cell-renaming rules now also cover cell/local reads and writes, nested field
and array assignments, projected reads, parameter binding, caller-local
restoration, scalar operations, and i32 encoding/decoding. Both registered-view
synchronization directions are proved compatible with renamed cell roots while
preserving native addresses and bytes. The synchronization module checked in
0.48 s; the combined focused checks and axiom audit checked in 0.43 s with
dependencies built. All audited new rules use only standard Lean axioms.
Pointer exposure now covers array views, slice pointers, strings, and raw-slice
construction, including fresh-cell allocation and registered roots. Pattern
bindings and execution outcomes also respect cell renaming. Source literals
are proved unchanged, including literals inside aggregates.

The execution induction now carries the allocation boundary through argument
lists, match arms, mutable places, both loop-iteration forms, and every statement
form. These are conditional fuel-step lemmas: they use the smaller-fuel
execution hypothesis, not an axiom asserting full transport. Explicit evaluator
cases keep the place and statement modules at 1.3 s and 1.2 s respectively.
Expression cases now cover internal calls and constants under explicit program
invariance premises, scalar operations (including short-circuiting), aggregate
construction, matches, field/index reads, locals, borrowing, dereferencing, and
assignment. Calls preserve parameter allocation and caller-local restoration;
missing bodies are not silently treated as pure external calls. Separate
counter lemmas prove that writes, view synchronization and pointer exposure
preserve `nextCell`, while raw-slice construction increments it by one. The
call, scalar, aggregate and reference modules checked in 0.72 s, 1.8 s, 1.0 s
and 0.56 s respectively.
All expression cases now pass, including array-to-slice conversion, pointer
exposure, raw memory operations and intrinsics. The complete fuel induction is
closed: `CellRenaming.Execution.evaluates` and `executes` transport successful
execution and preserve the allocation boundary. The assembled expression step
checked in 0.48 s and the final induction in 0.45 s with dependencies built.
These theorems require `ProgramInvariant`: constants and internal function
bodies must be unchanged by cell renaming. A proved structural checker now
establishes this premise for every renaming from one source check. It rejects
embedded runtime references/slices and missing function bodies, while allowing
source operations that create references during execution. The actual
`verifiedFrontendCore` passes this check; the self-embedding/link check also
passes with this evidence.

`RawLexer.LexInto.Linked.call_evaluates_renamed` now composes cell renaming and
symbol relocation for the complete lexer call. It preserves the source buffer
at the renamed source root and the encoded-token prefix plus untouched suffix
at the renamed record root. The module checked in 0.99 s. Its initial
representation remains in model coordinates. A new
`RawLexer.LexInto.Caller.body_executes_at` contract now accepts arbitrary
distinct caller source/record cells and the caller's local-cell layout
directly. It constructs the permutation and inverse representation internally,
derives allocation bounds from ownership and well-formedness, and preserves
the caller-coordinate output representation. Its module checked in 0.99 s.
`Caller.call_evaluates_at` lifts it to a complete call with argument evaluation,
parameter binding, restored caller locals, and the exact token-prefix plus
untouched-suffix buffer postcondition. The self-source check using the caller
body theorem passed in 21.59 s. `Linked.call_evaluates_at` now connects this
caller-coordinate contract to the checked linked program. The body contract
also preserves its store effect through cell renaming; the call uses the
resulting allocation-domain extension to prove well-formedness after restoring
caller locals. It requires well-formedness of the post-argument caller state,
not an assumption that the final state is well-formed. The strengthened linked
module checked in 0.99 s.
Raw-token span validity is now proved for every emitted token, including
lexical-failure and capacity-limited prefixes. The scanner proofs cover numeric
forms, quoted literals, comments, and fixed symbols. `canonicalize_emitted`
uses the lexer's buffer postcondition to invoke the checked canonicalizer,
deriving span and buffer-size preconditions without repeated validation.
The bridge module checked in 0.45 s with dependencies built; its axiom audit
reports only `propext`, `Classical.choice`, and `Quot.sound`.
The two buffer-copy loops now have a shared total execution proof, covering
contiguous raw words and every-third-word token kinds. The invariant preserves
the source, replaces exactly the destination prefix, retains unused capacity,
and bounds i32 cursor arithmetic. A proof-producing matcher accepted both loops
in the current self-embedding: raw local 4 to canonical local 6, and canonical
local 6 to kinds local 8. The complete source/link check passed in 21.76 s.
The loop proof checked in under one second and uses only standard Lean axioms.
Token-record lemmas derive the copied-word and kind-selection relations;
they do not assume a successful read or a correct iteration. Focused tests
reject mismatched read/write cursors, incorrect increments, and wrong strides.
Cursor initialization now derives the loop invariant from caller storage and a
fresh binding. Closing the cursor scope exposes only destination-buffer writes.
`copy_then_canonicalize` composes the loop with the checked canonicalizer call
inside the original cursor scope and binds the returned count for the rest of
the extractor. Canonical capacity may differ from raw capacity; only the copied
prefix must fit. The composed theorem checked in 0.54 s and its audit reports
only standard Lean axioms. The self-source checker also authenticates the
enclosing scope, call arguments, and canonicalizer function identity; it passed
in 20.55 s. Negative tests reject a different cursor or miswired count/buffer.
`copy_kinds` now constructs its memory model and initial invariant directly from
the canonicalizer's buffer, allocates the cursor, executes the kind loop, and
passes the exact kind prefix and count to a continuation in the original scope.
Its first check took 0.46 s. `kind_prefix` converts that output to `I32Prefix`,
which retains physical capacity while describing only the meaningful input.
The new prefix read and frame-preservation rules are kernel-checked.

Parser composition has a concrete remaining contract gap: the old
`RecognizerResources.tokensBacking` and `parserTokensValue` require exactly
the logical token list and its length. The extractor supplies a larger kinds
slice with an untouched suffix. The parser contract must be generalized to
prefix-backed read-only input; the current proof cannot be applied by assuming
away spare capacity. The new prefix rules are a basis, not that generalization.
Inspection confirms `scan_terminal` is the parser's only direct token-array
reader. Its functional-view read helpers now accept explicit storage and are
verified. Their initial check was delayed because rebuilding the legacy parser
artifact exceeded the 29-second command limit before reaching the scan module.
The first build also spent 26 seconds on unrelated lexer artifacts imported
only for `sourceBytes`; that import was removed from the parser program module.
Standalone artifact quotation now caches decoded JSON by exact input text,
matching the existing pack-cache design. Cached/uncached replacement, repeated,
equivalent-encoding, and malformed-input tests pass (test module: 0.87 s).
The parser artifact still exceeded 29 seconds after this change. A bounded
debugger sample subsequently located active work in Lean's LCNF specialization
(`isGround` / `shouldSpecialize`), not kernel checking. Temporary file-backed
timing instrumentation bypassed buffered diagnostics: decoding took about
0.18 seconds, while compiling each 6,474-node parse-table field took about
9 seconds. Literal `include_str` paths alone did not fix the timeout.
Standalone field quotation now bounds constructor expressions with ordinary
auxiliary definitions and batches their compilation. It does not add shard
files or trust assumptions. Kernel equality tests cover empty, short, and
multi-definition nested data; a runtime check also compares compiled data.
An intermediate 512-node, synchronous direct Lean check completed within
29 seconds, with parse-table fields taking roughly 4.3 seconds each. This is
not itself a successful normal build: normal builds, including the batched
variant, still timed out at 29 seconds. Subsequently disabling redundant
closed-term extraction for this generated module cleared the full normal
build in 24.33 seconds (about 2.7 GB peak RSS).
The next check exposed a stale whole-file source claim: the current parser
appends `copy_derivation` to the exact original source. The assertion is now
explicitly `verifiedParserArtifact_tracks_source_prefix`; it does not claim
to validate the appended function. Reuse in the current self-embedding still
requires the exact Core relocation link and full-current-source check.
With closed-term extraction disabled, the parser program module rebuilt in
2.22 seconds. The parser scan proof and its dependencies then rebuilt in
11.84 seconds; the functional-view scan module itself took 3.4 seconds.
This verifies the generalized raw-token and grammar-read helpers, not yet
the full prefix-backed recognizer contract.
`scanTerminal_evaluates_storage` now composes those helpers into the complete
in-bounds scan evaluator for arbitrary unused token storage. The exact-sized
scan theorem specializes it with an empty suffix, avoiding duplicate proofs.
The module checks in 3.7 seconds. Its axiom audit retains the existing
`native_decide` dependencies for signed minus one and parser constants; no
new axiom was added. `scanTerminal_rejects_past_end_storage` now proves
rejection for any storage world using only logical count and position; spare
capacity cannot expose extra tokens. `extractedParserScanTerminalBody_scans_storage`
connects the in-bounds result to actual Core execution, preserving caller
cells and state well-formedness. The module still checks in 3.7 seconds.
`ScanStorageEntry` now derives the world representation and local-environment
assumptions from concrete locals and backing cells. The combined body theorem
covers both branches, and `extractedParserScanTerminalCall_implements_model_storage`
proves the actual call result, caller-cell preservation, restored-state
well-formedness, and preservation of both the grammar and complete token buffer.
`parserScanStorageCallee_entry` now derives the entered-state facts from
caller well-formedness, distinct buffers, and their concrete contents. The
call theorem no longer assumes its own callee invariant. The module checks
in 3.9 seconds. Generalizing persistent recognizer resources and carrying
the suffix through workspace updates and nested loops remain unfinished.
`I32PrefixLocal` now couples a slice local to its physical backing capacity
and logical prefix. Its read and frame-preservation rules check in 0.4 seconds.
`parserRecognizeScanTerminalCall_implements_prefix_model` uses that resource
at the recognizer's exact call expression and returns it preserved, without
exposing a capacity parameter in the statement. The recognizer module passes.
`RecognizerResources` and `RecognizerInvariant` now use `tokenStorage` instead
of separate exact-sized token-local/backing fields. Preservation across local
binding, read-only calls, workspace writes, scoped effects, and both scan paths
has been updated; the recognizer module passes. The downstream soundness build
does not yet pass. The common Functional View world now carries an explicit
physical suffix, and `recognizerWorld_from_invariant` obtains a consistent
world and slice local from the persistent resource (common module: 0.96 s).
Chart clearing now preserves the combined prefix resource. Phase-specific
worlds/environments and setup code still need migration; the whole parser
soundness build is not yet restored.
Prediction migration exposed a missing retained frame fact:
`RecognizerSeededAppendResult` now includes `argumentsEffect`, proving that
argument evaluation preserves existing cells. Its constructor supplies the
already-proved seed effect, and the recognizer module passes. This permits
transport of a chosen physical suffix into the append argument state.
Experimental prediction suffix propagation was not retained: it still
needs the suffix/backing relation carried through configuration and loop
outcome definitions, not a fresh unrelated witness at each step.
`I32PrefixLocal.unused` now names the suffix selected from a resource, with
proofs that backing contents determine it uniquely and that untouched cells
preserve it across reconstructed proofs (module: 0.44 s). The common world
module uses this to prove representation from the named suffix and equality
between workspace-updated worlds built from different before/after invariants.
Both preservation theorems audit to standard Lean axioms only. Phase migration
can therefore use invariant-selected suffixes without adding data fields to
every loop configuration; it remains to apply those equalities in the phases.
The distinct-buffer premise was subsequently removed from the storage entry,
call, and recognizer call-site contracts. When both slices share a cell,
their concrete backing equalities prove that the encoded contents agree;
the read-only world then reduces to a singleton. The generalized contract
therefore retains the old recognizer's aliasing domain rather than imposing
an extra separation assumption. The scan and recognizer modules pass.
The exact current self-source and frontend relocation check also passed again
in 22.21 seconds, including all old parser functions, constants, and layouts.
Composing the preceding guards and lexer call, the following parser,
and full I/O contracts
remain unfinished. The reused lexer proof still
has legacy `native_decide` dependencies; the new generic source and transport
proofs use only standard Lean axioms.
The generic link theorem and actual self-source link check pass independently
(the latter took 20.21 s after using the reusable checker).

The compact ASCII helper now has a kernel-checked proof of its complete Core
body: string exposure, exact raw-word borrowing, decoding, local bindings,
terminating byte comparison, and both return paths. It preserves caller cells,
locals, and the host world. The body proof checked in 0.49 s. The proof exposed
an actual source bug: ordinary strings do not guarantee readable word padding.
Keyword literals now include explicit zero padding, while comparison lengths
exclude it. No memory-model relaxation was needed. Execution tests cover all
keyword spellings, every mismatch position, and the source dispatcher against
the independent lexer table, including keyword prefixes and suffixes. The
updated full self-source check and execution regressions took 19.29 s.

The helper is now composed through keyword dispatch. The general proof covers
rule choices, length branches, the fallback return, and the end-minus-start
initializer. Exact-spelling lookup is proved equivalent to the independent
lexer's keyword classifier, including its handling of non-byte integers.
`Dispatch.Checked.executes` ties that theorem to an actual Core body after
checking its matcher, padding, constants, and complete reference-table
permutation. The updated self-source check accepted all six length groups in
20.85 s. New production proofs use only Lean's standard axioms.

`Kind.result_canonicalKind` connects the callable classifier to the independent
lexer specification. The actual `canonicalize_in_place` source now passes a
proof-producing whole-body check. Its first loop has a total-correctness proof
for filtering and keyword retagging; its second loop has a total-correctness
proof for inclusive-range marking, including empty and singleton streams.
These proofs account for the caller's spare buffer capacity and fresh helper
allocations. They prove each iteration from Core execution rules rather than
assuming an abstract iteration is correct. The loop declarations checked in
0.59 s and 0.65 s respectively; these are incremental proof-build times, not
whole-extractor checking times. Their axiom audit passed without `sorry` or
project-specific axioms. `Compaction.CheckedSource.evaluates_call` now composes
both loops with local initialization, scope cleanup, the return, and the actual
function call. It proves the canonical token count, the encoded output prefix,
and preservation of the rest of the caller's capacity. The function body and
call proof declarations checked in 0.51 s and 0.46 s. Regression execution of
the checked source covers empty input, singleton keywords, all-trivia input,
contiguous and separated range operators, and several spare-capacity sizes.

The old public lexer/parser contracts still need composition in the complete
extractor. Fresh borrowed storage means the new matcher preserves caller cells
and the host world, but not literal heap/view identity; `CellEffect` states
that distinction without claiming raw-memory preservation. No whole extractor
I/O refinement theorem follows from these results alone. Milestone 3 remains
incomplete.

## Milestones and acceptance evidence

1. **Lanius extractor.** Build on the current Lanius lexer/parser. Implement
   derivation materialization, semantic analysis and lowering required by the
   embedding, and serialization in Lanius. Support the complete extractor's
   source closure; reject unsupported inputs explicitly. Differential tests
   against the Rust exporter are useful but are not a correctness proof.
2. **GPU bootstrap.** Compile that source with the existing GPU compiler and
   execute the resulting untrusted program. Host services may supply memory
   and I/O, but must not perform parsing, lowering, or extraction on its behalf.
   Record the source closure, compilation command, and executable identity.
3. **Self-extraction and extractor correctness.** Run the Lanius executable on
   its own source closure, produce the deep Lean embedding, and validate the
   source-to-embedding connection. Then prove the extractor's general
   correctness for supported inputs. An accepted embedding alone does not
   establish that general theorem. Include memory safety, failure behavior,
   and exact input/output semantics in the stated contract.
4. **Verified Lanius x86 backend.** Implement a simple backend in Lanius and
   prove that emitted machine code preserves the input IR semantics. Specify
   instruction encodings, machine state, memory, calling convention, runtime
   boundary, and supported IR. It must support the extractor, not just a toy
   arithmetic example. State any limitations explicitly.
5. **Whole compiler correctness.** Compose the frontend, lowering, and backend
   theorems into a source-to-x86 result. Cover the supported language and the
   whole compiler/extractor source closure; no omitted pass may be silently
   assumed correct. Identify environmental assumptions separately.
6. **Extractor x86 executable.** Run the verified compiler to produce it.
   Establish the connection between the exact executable bytes and the
   compiled program in the correctness theorem. A proof about the compiler
   algorithm does not alone justify an arbitrary bootstrap executable.
7. **Fast trusted extraction.** Provide an explicit trusted extraction boundary
   that relies on the established compiler/extractor correctness. The user
   permits certificates, object-file integration, or explicit extraction
   axioms as appropriate. Keep these assumptions identifiable and separate
   from ordinary kernel-checked theorems; do not disguise trusted results as
   kernel reduction. Bind results to exact source, tool version, and output.
   Measure fresh per-program extraction, emission, loading, and checking with
   only general infrastructure prebuilt. Target a couple of seconds, not
   minutes; cached prior program certificates do not satisfy this target.

## Current checkpoint

- `src/verified/parser.lani` is a workspace-backed Earley recognizer. The
  extractor materializes its retained derivation without reparsing and
  serializes ordered parse nodes.
- All bootstrap artifacts used by this plan are x86-64 Linux ELF executables.
  Historical Wasm recognizer tests are not part of the bootstrap or trust path.
- The former Rust `laniusc-formal-export` extractor has been removed. The
  supported syntax-certificate producer is now `src/extractor.lani`; it does
  not yet emit complete Surface/Core semantics.
- `src/verified/host.lani` is the extractor's deliberately small host boundary.
  It replaces four unrelated general-stdlib files in the proof closure and
  contains only the allocator, filesystem, argument, output, and three raw-view
  operations the extractor calls. Core syntax, typing, executable semantics,
  artifact decoding/checking, and fuel stability now model
  `i32_slice_from_raw_parts`, `i32_slice_data_ptr`, and `string_data_ptr`.
  Connecting those operations through the complete program-elaboration and
  preservation proofs remains part of the extractor execution theorem.
- On September 6, 2026 the current x86 extractor emitted its exact 18-file,
  2,331-line, 105,021-byte closure in 1.22 seconds with about 39 MiB peak
  RSS. With shared Lean infrastructure built, compact decoding plus
  proof-producing exact-source, syntax, reconstructed-Surface, source-to-Core
  lowering and whole-program x86 Core typing took 18.97 seconds
  with about 1.65 GiB peak RSS. A pruned
  postorder-origin lookup avoids rescanning irrelevant parse subtrees. These
  are major representation improvements, but the full-closure check is not yet
  the milestone-7 couple-of-seconds target.
- The self-embedding check with extractor-specific entrypoint analysis and
  ordered count/clear/pack, input-unpacking, and capacity-probe source linkage
  took 19.70 seconds.
  The loop and memory proofs
  depend only on Lean's standard `propext`, `Classical.choice`, and `Quot.sound`;
  they introduce no project-specific axiom or `sorryAx`.
- The focused input/output proof and regression build took 6.42 seconds.
  Input-loop execution tests cover every byte value at every packed-word lane,
  empty input, partial final words, preceding chunks, and unused capacity.
  After the later preservation and capacity-probe additions, the incremental
  focused build took 2.35 seconds. A Core host-call regression covers a partial
  read followed by EOF, preserving an unrelated signed buffer and the unread
  scratch tail. The impacted relational adequacy module also checks.
- File reads reuse the existing scratch slice rather than registering an
  overlapping raw view for every file. The GPU compiler also now uses narrow
  moves for known narrow scalars; unclassified values retain full pointer
  width. This fixes a native failure where an i32 argument carried stale
  stack bytes in its upper half.
- The generic checker accepts both a library without `main` and a program
  returning `42`; extractor-specific entrypoint analysis is separate.
  `writeStdout_exact` and `writeStdout_invalidRange` prove the modeled host
  output boundary. They do not prove that the Lanius packing loop supplies the
  correct bytes, or that native OS writes cannot be short.

## Previous work-sequence checkpoints

Latest parser integration checkpoint (September 7):

- Prediction now uses the invariant-selected physical token suffix throughout
  its FunctionalView execution. Its append proof preserves the backing through
  argument evaluation, and its loop-step proof shows that the suffix is unchanged.
  `Lanius.Extraction.Parser.Recognize.Prediction` builds successfully within the
  29-second command limit (`prediction-selected-suffix.log`).
- Nullable and parent traversal now build with the invariant-selected physical
  suffix (`nullable-world.log`, `parent-world.log`). Their scoped restoration,
  append argument evaluation, and all six loop transitions preserve that suffix.
  Both focused builds finished within the 29-second command limit.
- `TraversalPrefixAudit.lean` checks the traversal theorem dependencies. They
  still inherit legacy `native_decide` axioms from existing parser proofs; this
  migration does not remove that trust boundary or add a new one.
- Setup's resource-preservation code has also been migrated, but its build is
  not yet validated: it depends on the unfinished traversal migration.
- The state scanner call model now accepts a logical token prefix plus arbitrary
  spare capacity, with a full-capacity slice value and a separate logical count.
  Its generalized call theorem builds (`scan-registry-prefix.log`, 2.86s).
  Terminal append results now expose their existing no-write argument effect;
  the recognizer and call-model build passed in 9.07s, and all three traversal
  modules rebuilt together in 17.19s.
- The complete parser integration still needs state/initialization consumers
  and the full extractor composition. The first state-module check hit the
  29-second cutoff; ordinary retries stopped in favor of bounded profiling.
  The first asynchronous profile attributed 4–13s to shape-check declarations.
  A serial profile clarified that expensive concrete-command structural proofs
  contribute to those waits. Replacing native decisions with `rfl` failed and
  was reverted. Generalizing structural proofs over a command instead worked:
  branch decomposition fell from about 4.7s to 0.26s; incomplete and body
  structural proofs now take about 0.58s and 0.46s. These are profiler timings,
  not a complete successful-build benchmark.
  The normal state-module check now terminates within 29s with the outstanding
  token-buffer integration errors (`state-generic-build.log`). Generic branch
  projections retain the same source-derived command and add no trust premise.
  After migrating the state module's scoped token-storage restoration, the
  complete error-reporting build took 27.52s and about 2.46 GiB peak RSS
  (`state-generic-resource-build.log`); the restored-resource errors are gone.
  Subsequent token-world, scanner, append, and parent-return integration removed
  the remaining State.Core errors. Its first error-free attempt hit the cutoff;
  disabling `compiler.extract_closed` allowed the complete module to build in
  28.88s with about 2.58 GiB peak RSS (`state-prefix-no-closed-build.log`).
  This remains far from the desired fast checking time.
  `stateEnvironment`, `positionEnvironment`, `positionStatementEnvironment`,
  and `StateAfterBindingsEnvironment` now carry physical token capacity
  separately from logical count. State.Core rebuilt successfully in 27.88s
  (`state-capacity-environments.log`).
  State.Terminal also builds (`state-terminal-capacity.log`): scanner matching
  and source-local binding preserve the same suffix, and completed miss/append
  outcomes preserve the caller's full-capacity environment.
  State.Nonterminal now builds in 11.68s (`nonterminal-capacity.log`). Its
  prediction/nullable outcomes retain the selected physical suffix, and joining
  a restored physical frame with its functional result now explicitly requires
  equality of the token backing before and after scope restoration. The driver
  caller supplies that equality from the recorded restoration equation.
  State.Driver now builds successfully in 10.66s with about 2.19 GiB peak RSS
  (`state-driver-capacity.log`). Parent, prediction, nullable, and candidate-field
  setup preserve the physical token backing across reads and temporary bindings.
  Completed branches and scope restoration preserve the same capacity in both
  the physical state and functional environment. Explicit suffix equalities
  replace expensive implicit reduction in the combined state-step proof; no
  heartbeat-limit increase was needed. The outer position loop and initialization
  still need integration. This check validates the driver's restored-frame
  composition call, but does not establish the complete extractor theorem.
  Position.Core now builds in 8.15s (`position-capacity.log`). Its activity,
  scoped state execution, and full position loop carry physical capacity through
  normal advancement and early capacity failure. Token-backing preservation
  follows from the real cursor-binding, activity, and scope-closing effects.
  The position-update lemma remains generic in capacity. Root.Commands also
  builds in 2.15s (`root-commands-capacity.log`). Root selection and initialization
  remain to be integrated; these results do not complete milestone 3.
  Root.Selection now builds in 6.30s (`root-selection-capacity.log`). Its
  read-only field/predicate helpers accept an explicit unused suffix; candidate
  executions use the invariant's physical suffix. Cursor updates preserve that
  suffix through the synchronized root loop. Root-head initialization and the
  rejected fallback retain the caller's physical world. Position.Continuation
  now builds in 2.25s (`position-continuation-capacity.log`), including both
  local-counter bindings and the position-to-root connection. Initial.Loop now
  builds in 3.55s (`initial-loop-capacity.log`). Its shared continuation
  environment carries physical capacity separately from logical count. The
  append bridge proves token backing through argument evaluation, and successful
  seeding preserves the same suffix in the successor runtime.
  Initial.Continuation builds in 2.16s (`initial-continuation-capacity.log`),
  Recognize.Setup in 9.43s (`setup-capacity.log`), and Parser.Soundness in 1.52s
  (`parser-soundness-capacity.log`), with shared dependencies already built.
  The parser theorem states that success of a checked `recognize` call implies
  recognition by the declarative grammar. This completes this buffer-capacity
  integration through that soundness theorem, not the extractor's end-to-end
  correctness or the x86 milestones.
  `ParserCapacityAudit.lean` reports only `propext`, `Classical.choice`, and
  `Quot.sound` for `RecognizerCallExecution.success_recognizesInput`. This audits
  the implication from a supplied execution, not construction of that execution;
  inherited `native_decide` in earlier construction proofs remains a separate
  trust consideration.
  The public `parserRecognizeValues`, `parserRecognizeBindings`, and
  `parserRecognizeCallee` now take physical token capacity explicitly, and
  `executeRecognizerCall` propagates it. Previously this public boundary still
  constructed an exact-length slice despite the generalized internal proofs.
  `parserRecognizeCallee_tokenStorage` now derives callee token ownership from
  the caller's prefix-backed storage and well-formed state, using actual call
  parameter binding and cell preservation. Setup and Soundness rebuild together
  in 9.04s (`parser-call-capacity.log`). Grammar/workspace entry resources and the
  extractor's concrete call arguments still need caller-side composition.
  `Parser.Recognize.Caller.parserRecognizeCallee_resources` now constructs all
  `RecognizerResources` from caller-side grammar facts, bounds, and backing
  storage. Dense call-parameter binding supplies all six locals; call effects
  preserve the three backing buffers. The module builds in 1.65s
  (`parser-caller-resources.log`), and its axiom audit reports only `propext`,
  `Classical.choice`, and `Quot.sound`. The remaining entry obligation is
  separation of fresh parameter cells from the mutable workspace, followed by
  composition with the extractor's actual argument evaluation.
  `Separation.CallFrame.enterCall_frame_disjoint_old_cell` now proves that any
  callee local-binding frame is disjoint from a pre-existing caller cell, even
  with shadowed parameter names. It builds in 1.05s (`call-frame.log`) and uses
  only standard Lean axioms. `parserRecognizeCallee_entry` combines this with
  the resource constructor to discharge the full callee-entry obligation from
  caller facts; Caller builds in 1.70s (`parser-caller-resources.log`). Its audit
  also exposes three inherited `native_decide` assumptions from the checked
  parser parameter frame (`verifiedParserRecognizerSymbolic`,
  `verifiedParser_scoped_surface_accepted`, and
  `verifiedParser_symbolic_derivation_accepted`). No new such assumptions were
  added. Concrete extractor argument evaluation and pipeline composition remain.
  Passing State.Core does not establish the complete extractor theorem.
  Milestone 3 and the x86 correctness milestones remain
  incomplete. No new trust assumptions were added for this migration.

- The actual kind-copy/recognizer source region now has a proof-producing
  checker in `BufferCopy/RecognizeSource.lean`. It checks the cursor scope,
  triple-stride reads, single-stride writes, and the destination/count passed
  among the recognizer's six arguments. Focused tests reject wrong cursors,
  buffers, counts, and strides; they build in 1.3s. The self-embedding linkage
  check also verifies the callee is `parser::recognize` and that the copy uses
  the canonicalizer's buffer and returned token count. It passes in 20.47s
  (`recognize-source-link-run.log`). This authenticates source wiring, not
  execution of the whole pipeline. No new axioms were introduced.
  The initial integration build hit its 29s cutoff rebuilding shared proofs.
  Removing unused theorem bindings and the full lexer-correctness import from
  the runtime linkage executable reduced its dependency graph from 369 to 184
  jobs; the next build passed in 2.34s with already-built dependencies. The
  proof-producing relocation checks remain, and the correctness theorems remain
  in their proof modules. This is not a cold-build benchmark.

The complete x86 Core embedding is now synthesized from the checked Surface
values without introducing a second program copy, and it retains indexed
lowering evidence for internal functions plus checked extern construction.
Next prove the extractor I/O contract now exercised by the source-bound
self-pack and prove the Lanius extractor implementation refines
the Lean specification for every supported input, including explicit failure
behavior and memory bounds. Only after that
proof boundary is stable should the x86 backend semantics and implementation be
fixed around the actual IR required to compile the extractor.

Backend design must follow the semantics needed by the resulting extractor;
do not invent an incompatible IR just to obtain an easy backend proof.
No milestone is complete yet merely because this plan exists.

## Historical baseline

On September 5, 2026, `cargo test -j 1 --test verified_parser -- --nocapture`
passed: one GPU-compiled recognizer test, 3.27 s test execution after 25.47 s
incremental build. That historical Wasm route is not used by the current x86
bootstrap and establishes no part of the x86 trust chain.
