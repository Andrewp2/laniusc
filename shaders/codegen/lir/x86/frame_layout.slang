import codegen.lowering_ir;
import codegen.lir.x86.location_common;

// Byte counting, emission, and relocation placement consume the same frame
// contract. This module owns no buffers; callers supply the finalized metadata.
uint base_frame_slots(TargetLirFunction function,
                      SemanticLirFunction semantic_function)
{
    return (function.flags & X86_TARGET_FUNCTION_FRAME_SLOT_MASK) +
        (semantic_function.result_word_count > 2u ? 1u : 0u);
}

bool frameless_function(TargetLirFunction function,
                        SemanticLirFunction semantic_function)
{
    // A hidden structure-return pointer needs an addressable frame slot even
    // when ordinary allocation found no spills.
    return (function.flags & X86_TARGET_FUNCTION_FRAMELESS) != 0u &&
        semantic_function.result_word_count <= 2u;
}

bool stackless_caller(TargetLirFunction function,
                      SemanticLirFunction semantic_function)
{
    return (function.flags & X86_TARGET_FUNCTION_STACKLESS_CALLER) != 0u &&
        semantic_function.result_word_count <= 2u;
}

uint implicit_footer_bytes(TargetLirFunction function,
                           SemanticLirFunction semantic_function,
                           uint saved_mask)
{
    return frameless_function(function, semantic_function) ? 3u :
        stackless_caller(function, semantic_function) ? 4u :
        4u + x86_saved_gpr_frame_bytes(saved_mask,
            base_frame_slots(function, semantic_function));
}
