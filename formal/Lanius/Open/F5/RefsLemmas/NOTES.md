# RefsLemmas

F5's construct lemmas (leafA, 11-03, revised after review). The conjunction of the fifteen leaves; `Red1` is the conjunction's introduction. Not F5's top theorem: stage 2 states `compileSource` correctness for programs with references and needs, besides these, a call passing a reference (the callee's `RefsAgree` at entry), `Corr` for homed locals, `Keeps` with callee writes through references, and effectful right-hand sides (SEMANTIC_DECISIONS "References: the memory model", "Stage 2's root"). Definitions: `Lanius/Mini/Refs/Model.lean` (untrusted until stage 1's `HoldsAt.ref`).
