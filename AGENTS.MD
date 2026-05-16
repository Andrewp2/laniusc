Compiler architecture contract

Non-negotiable goal:
Implement the paper-aligned compiler pipeline. Passing a focused stdlib test is not success unless the change also preserves the architecture below.

Required dataflow:
1. Source bytes enter GPU-resident buffers.
2. Lexing produces token records.
3. Parsing produces parse-tree records.
4. Semantic passes produce GPU-resident HIR or attributed AST records.
5. Later semantic passes consume HIR, resolver records, type-instance records, and literal records.
6. Backend lowering consumes attributed AST or HIR records only.
7. Instruction counting is per node.
8. Instruction locations are produced by prefix sums over node-local instruction counts.
9. Instruction generation is per node, scheduled bottom-up where needed.
10. Instruction records use virtual registers before register allocation.
11. Register allocation consumes virtual instruction and virtual register records.
12. x86_64 byte emission consumes allocated instruction records.
13. CPU code may launch passes and write final bytes, but must not rewrite the program semantically.

Forbidden:
1. No helper-name matching in semantic analysis or backend lowering.
2. No stdlib-function-specific backend cases.
3. No function-body expression shape recognizers.
4. No token spelling or source-byte inspection after the lexeme-to-semantic-record pass.
5. No return-expression extractors that decide whether a whole callee matches a supported shape.
6. No backend cases named after source patterns, helper functions, or tests.
7. No deleting, renaming, or bypassing instruction files.

Do not even perform forbidden actions as "narrow slices" to "move towards" a working stdlib.

Testing strategy:
1. Prefer property-based and generative tests over exact shader-source string checks.
2. Randomize function names, parameter names, local names, module names, helper-like names, and stdlib-like names so semantic behavior cannot depend on spelling.
3. Randomize simple function shapes, including direct returns, let-bound returns, nested blocks, if/else returns, calls, reused locals, and equivalent expression rewrites.
4. Test semantic equivalence through generated GPU records and final output behavior for supported language slices.
5. Test stage invariants over records: counts match, references are valid, sorted tables are sorted, duplicate detection works, use edges match vreg args, instruction ranges equal prefix sums of per-node counts, and emitted bytes match allocated instruction records.
6. CPU implementations are allowed only as clearly named test-only oracles. They must never be used as compiler fallbacks.
7. Keep source-text audits small and architectural. They may deny forbidden classes such as source-byte reads, token spelling reads, helper-name matching, return-expression extractors, and backend shape recognizers, but they should not assert incidental helper names, exact lines, or implementation-specific shader structure.

Required review output for every change:
1. List the pipeline stage changed.
2. List the input record arrays consumed by that stage.
3. List the output record arrays produced by that stage.
4. State whether any source text, token spelling, helper name, or function-body shape was inspected.
5. If yes, stop and redesign.
6. Add at least one architecture test proving the stage consumes the right records.
