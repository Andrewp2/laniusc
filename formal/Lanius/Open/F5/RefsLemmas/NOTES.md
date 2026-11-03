# RefsLemmas

F5's construct lemmas (leafA, 11-03, revised after review). The conjunction of the fifteen leaves; `Red1` is the conjunction's introduction. Not F5's top theorem: stage 2 states `compileSource` correctness for programs with references and needs, besides these, a call passing a reference (the callee's `RefsAgree` at entry), `Corr` for homed locals, `Keeps` with callee writes through references, and effectful right-hand sides (SEMANTIC_DECISIONS "References: the memory model", "Stage 2's root"). Definitions: `Lanius/Mini/Refs/Model.lean` (untrusted until stage 1's `HoldsAt.ref`).


## Replaced by RefsLemmasV2 (leafC, 11-03)

Its conjuncts `HomesCongr` (the static region is not kept; HomesCongr/NOTES.md has the counterexample) and `RefStore` (an enum tag past `2 ^ 32` is truncated; RefStore/NOTES.md) are false, so this conjunction is false. `RefsLemmasV2` is the same conjunction with `RefStoreV2` and `HomesCongrV2`.
