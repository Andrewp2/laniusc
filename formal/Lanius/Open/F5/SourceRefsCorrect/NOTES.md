# SourceRefsCorrect

F5's top statement, on `compileSource` itself (coordinator's decision, 11-03: one compiler, one top theorem; no separate `compile_source_refs`). Stage 1 rejects every reference form, so the proof is `compileSource_correct`. S6 adds the lowering cases; then `compileSource_correct`'s proof takes the F5 leaves, or, if that cannot be done in one step, a temporary untrusted decidable hypothesis `noRefs`, and this statement is reproved through the F5 leaves (leafC).
