# Verified compiler roadmap

After the mini compiler (`MINI_COMPILER.md`). The rules there still hold: pure
Lanius, shallow extraction, the top-level theorem first, one simulation lemma
per pass, files that check in seconds. Each step records what it proves, what
it still trusts, proof lines against code lines, and check time.

| # | step | status |
|---|------|--------|
| 1 | Mini compiler lists proved against the list specs the extractor assumes | done: a cons list `List<T>`; each list operation is extracted with a Lean-checked spec theorem; `std::vec` specs move to step 10 |
| 2 | Extractor faithfulness: proof for the pure subset, at least a large difftest | difftests done: 3,006 programs end to end and 8,200 per-function calls (`fn_difftest.py`), no differences. The proof needs a Core heap model for `Box`, so it moves to step 6 |
| 3 | laniusc limits pure code hits at scale: per-allocation mmap and no free, `view` copying the tail, match arms without blocks or `if` | `<` match-arm parse fixed (fb6f3310); 1 GiB `MAP_32BIT` cap removed (70a4134f); `view` gone with the cons list. Open: a small-object allocator (needed by step 11; must keep the strace allocation-failure tests meaningful), block/`if` match arms |
| 4 | The real verified compiler in `verified_compiler/`, pure style, top-level theorem first | first pass done: `compile_source` lowers a typed Core subset (i32/bool, operators, `let`, assignment, calls, `if`, `while`, `return`) to the mini IR; `compileSource_correct` proves it against Core's evaluator, composed with the mini compiler's theorem. It lives with the mini compiler in `formal/lani/mini/`; moving to `verified_compiler/` waits for step 5's features |
| 5 | Source features one at a time: structs, enums and `match`, `Vec`, generics (monomorphized) | |
| 6 | Target memory model for aggregates and the heap; allocator spec | |
| 7 | Type checker soundness, which establishes the theorem's "well typed" premise | |
| 8 | Front end by translation validation: the parser's tree re-prints to the source tokens | |
| 9 | Modules and separate compilation; linking correctness | |
| 10 | Stdlib (`std::vec`, `std::set`, `std::map`) proved against functional specs | |
| 11 | Self-hosting: laniusc-built and self-built verified compiler agree byte for byte | |
| 12 | The verified compiler as an oracle for laniusc on the stdlib and fuzzed programs | |
| 13 | Optimizations as unverified passes checked by proved validators | |
| 14 | Trusted base: list every unproved assumption; test the x86 model against the CPU | |

Order of work: 3, 1, 2, 4, then 5 to 14. Steps 5 to 7 are the long stretch;
12 is where the proofs start making laniusc itself more trustworthy.
