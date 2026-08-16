import codegen.lowering_ir;

bool x86_semantic_type_is_aggregate(SemanticLirCore core)
{
    // TYPE_REF_SCALAR means a fully concrete type reference, not necessarily
    // a scalar machine value: monomorphic arrays/structs/enums retain their
    // canonical aggregate type code in the payload. Instantiated generic
    // aggregates instead carry TYPE_REF_INSTANCE. Keep the invalid-reference
    // fallback only for partially projected producers that still have a
    // checked concrete type code.
    uint type_ref_tag = semantic_lir_type_ref_tag(core);
    return type_ref_tag == SEMANTIC_TYPE_REF_INSTANCE ||
        (type_ref_tag == SEMANTIC_TYPE_REF_SCALAR &&
         core.type_ref_payload >= 128u) ||
        (type_ref_tag == SEMANTIC_TYPE_REF_INVALID && core.type_id >= 128u);
}

uint x86_aggregate_value_word_count(SemanticLirCore core,
                                    SemanticLirOperands operands)
{
    return semantic_lir_op(core) == SEMANTIC_LIR_OP_AGGREGATE_NEW
        ? max(core.value_word_count, operands.b) : core.value_word_count;
}

static const uint X86_LIR_TY_FLOAT = 5u;
uint x86_lir_count(SemanticLirCore core, SemanticLirOperands operands)
{
    if (semantic_lir_op(core) == SEMANTIC_LIR_OP_NOP) return 0u;
    // Native strings are a pointer/length pair. Every value-producing string
    // row has the same two-row target representation, whether its source is
    // rodata or a declaration read.
    if (semantic_lir_op(core) == SEMANTIC_LIR_OP_CONST_STRING ||
        (semantic_lir_op(core) == SEMANTIC_LIR_OP_VALUE_GET &&
         core.type_id == SEMANTIC_LIR_TY_STRING))
        return 2u;
    return semantic_lir_op(core) == SEMANTIC_LIR_OP_AGGREGATE_NEW
        ? 1u + core.value_word_count
        : 1u;
}

uint x86_abi_type_width(uint type_id)
{
    return type_id == SEMANTIC_LIR_TY_STRING ? 2u : 1u;
}

// Declarations use a fixed two-word home. This keeps component locations a
// pure arithmetic projection and avoids a per-function prefix table. Scalar
// declarations use the first word; strings use both words.
uint x86_declaration_slot_offset(uint logical_ordinal)
{
    return logical_ordinal * 2u;
}

uint x86_declaration_slot_count(uint param_count, uint local_count)
{
    return x86_declaration_slot_offset(param_count + local_count);
}

uint x86_binary_payload(SemanticLirCore core)
{
    bool f32 = core.type_id == X86_LIR_TY_FLOAT;
    if (semantic_lir_op(core) == SEMANTIC_LIR_OP_ADD) return f32 ? X86_LIR_BINARY_ADD_F32 : X86_LIR_BINARY_ADD_I32;
    if (semantic_lir_op(core) == SEMANTIC_LIR_OP_SUB) return f32 ? X86_LIR_BINARY_SUB_F32 : X86_LIR_BINARY_SUB_I32;
    if (semantic_lir_op(core) == SEMANTIC_LIR_OP_MUL) return f32 ? X86_LIR_BINARY_MUL_F32 : X86_LIR_BINARY_MUL_I32;
    if (semantic_lir_op(core) == SEMANTIC_LIR_OP_DIV) return f32 ? X86_LIR_BINARY_DIV_F32 : X86_LIR_BINARY_DIV_I32;
    if (semantic_lir_op(core) == SEMANTIC_LIR_OP_REM) return X86_LIR_BINARY_REM_I32;
    if (semantic_lir_op(core) == SEMANTIC_LIR_OP_BIT_AND) return X86_LIR_BINARY_BIT_AND_I32;
    if (semantic_lir_op(core) == SEMANTIC_LIR_OP_BIT_OR) return X86_LIR_BINARY_BIT_OR_I32;
    if (semantic_lir_op(core) == SEMANTIC_LIR_OP_BIT_XOR) return X86_LIR_BINARY_BIT_XOR_I32;
    if (semantic_lir_op(core) == SEMANTIC_LIR_OP_SHIFT_LEFT) return X86_LIR_BINARY_SHL_I32;
    if (semantic_lir_op(core) == SEMANTIC_LIR_OP_SHIFT_RIGHT) return X86_LIR_BINARY_SHR_I32;
    if (semantic_lir_op(core) == SEMANTIC_LIR_OP_LOGICAL_AND) return X86_LIR_BINARY_AND_BOOL;
    if (semantic_lir_op(core) == SEMANTIC_LIR_OP_LOGICAL_OR) return X86_LIR_BINARY_OR_BOOL;
    return 0u;
}

uint x86_lir_opcode(SemanticLirCore core)
{
    if (semantic_lir_op(core) == SEMANTIC_LIR_OP_CONST_I32 || semantic_lir_op(core) == SEMANTIC_LIR_OP_CONST_F32)
        return X86_LIR_OP_IMM_I32;
    if (semantic_lir_op(core) == SEMANTIC_LIR_OP_VALUE_GET) return X86_LIR_OP_ALIAS;
    if (semantic_lir_op(core) == SEMANTIC_LIR_OP_STORE &&
        (core.flags & SEMANTIC_LIR_FLAG_INDEXED) != 0u)
        return X86_LIR_OP_INDEX_STORE;
    if (semantic_lir_op(core) == SEMANTIC_LIR_OP_STORE &&
        (core.flags & SEMANTIC_LIR_FLAG_FIELD) != 0u)
        return X86_LIR_OP_FIELD_STORE;
    if (semantic_lir_op(core) == SEMANTIC_LIR_OP_VALUE_SET || semantic_lir_op(core) == SEMANTIC_LIR_OP_STORE)
        return X86_LIR_OP_STORE_LOCAL;
    if ((semantic_lir_op(core) >= SEMANTIC_LIR_OP_ADD && semantic_lir_op(core) <= SEMANTIC_LIR_OP_SHIFT_RIGHT) ||
        semantic_lir_op(core) == SEMANTIC_LIR_OP_LOGICAL_AND || semantic_lir_op(core) == SEMANTIC_LIR_OP_LOGICAL_OR)
        return X86_LIR_OP_BINARY;
    if (semantic_lir_op(core) == SEMANTIC_LIR_OP_COMPARE) return X86_LIR_OP_COMPARE;
    if (semantic_lir_op(core) == SEMANTIC_LIR_OP_NEGATE || semantic_lir_op(core) == SEMANTIC_LIR_OP_LOGICAL_NOT)
        return X86_LIR_OP_UNARY;
    if (semantic_lir_op(core) == SEMANTIC_LIR_OP_CALL_HOST) return X86_LIR_OP_CALL_HOST;
    if (semantic_lir_op(core) == SEMANTIC_LIR_OP_CALL_SYMBOL) return X86_LIR_OP_CALL_SYMBOL;
    if (semantic_lir_op(core) == SEMANTIC_LIR_OP_CALL_INTRINSIC) return X86_LIR_OP_PRINT_I32;
    if (semantic_lir_op(core) == SEMANTIC_LIR_OP_AGGREGATE_NEW) return X86_LIR_OP_AGGREGATE_ADDR;
    if (semantic_lir_op(core) == SEMANTIC_LIR_OP_LOAD &&
        (core.flags & SEMANTIC_LIR_FLAG_INDEXED) != 0u)
        return X86_LIR_OP_INDEX_LOAD;
    if (semantic_lir_op(core) == SEMANTIC_LIR_OP_LOAD &&
        (core.flags & SEMANTIC_LIR_FLAG_FIELD) != 0u)
        return X86_LIR_OP_FIELD_LOAD;
    if (semantic_lir_op(core) == SEMANTIC_LIR_OP_CALL)
        return X86_LIR_OP_CALL;
    if (semantic_lir_op(core) == SEMANTIC_LIR_OP_IF_BEGIN || semantic_lir_op(core) == SEMANTIC_LIR_OP_ELSE ||
        semantic_lir_op(core) == SEMANTIC_LIR_OP_BRANCH || semantic_lir_op(core) == SEMANTIC_LIR_OP_BRANCH_IF)
        return X86_LIR_OP_BRANCH;
    if (semantic_lir_op(core) == SEMANTIC_LIR_OP_BLOCK_BEGIN ||
        semantic_lir_op(core) == SEMANTIC_LIR_OP_LOOP_BEGIN ||
        semantic_lir_op(core) == SEMANTIC_LIR_OP_CONTROL_END)
        return X86_LIR_OP_LABEL;
    if (semantic_lir_op(core) == SEMANTIC_LIR_OP_RETURN) return X86_LIR_OP_RETURN;
    return 0u;
}

bool x86_lir_supported(SemanticLirCore core)
{
    // Semantic branch targets are stable LIR control-row identities. They
    // become x86 relative targets only in the control-label resolver.
    // Host calls require service-specific ABI validation in scatter. Compiler
    // intrinsics likewise validate their stable tag there.
    return x86_lir_opcode(core) != 0u &&
        semantic_lir_op(core) != SEMANTIC_LIR_OP_CALL_HOST;
}
