import codegen.lowering_ir;

bool x86_semantic_type_is_aggregate(SemanticLirCore core)
{
    // TYPE_REF_SCALAR means a fully concrete type reference, not necessarily
    // a scalar machine value: monomorphic arrays/structs/enums retain their
    // canonical aggregate type code in the payload. Instantiated generic
    // aggregates instead carry TYPE_REF_INSTANCE. Keep the invalid-reference
    // fallback only for partially projected producers that still have a
    // checked concrete type code.
    return core.type_ref_tag == SEMANTIC_TYPE_REF_INSTANCE ||
        (core.type_ref_tag == SEMANTIC_TYPE_REF_SCALAR &&
         core.type_ref_payload >= 128u) ||
        (core.type_ref_tag == SEMANTIC_TYPE_REF_INVALID && core.type_id >= 128u);
}

bool x86_semantic_type_is_string(SemanticLirCore core)
{
    return (core.type_ref_tag == SEMANTIC_TYPE_REF_SCALAR &&
            core.type_ref_payload == 7u) ||
        (core.type_ref_tag == SEMANTIC_TYPE_REF_INVALID && core.type_id == 7u);
}

static const uint X86_LIR_INVALID = 0xffffffffu;
static const uint X86_LIR_TY_FLOAT = 5u;

uint x86_lir_count(SemanticLirCore core, SemanticLirOperands operands)
{
    // Expansion is explicit and will become >1 for ABI/control records that
    // require payload rows. Scalar rows currently map one-to-one.
    if (core.op == SEMANTIC_LIR_OP_CONST_STRING) return 2u;
    return core.op == SEMANTIC_LIR_OP_AGGREGATE_NEW
        ? 1u + operands.b
        : 1u;
}

uint x86_binary_payload(SemanticLirCore core)
{
    bool f32 = core.type_id == X86_LIR_TY_FLOAT;
    if (core.op == SEMANTIC_LIR_OP_ADD) return f32 ? X86_LIR_BINARY_ADD_F32 : X86_LIR_BINARY_ADD_I32;
    if (core.op == SEMANTIC_LIR_OP_SUB) return f32 ? X86_LIR_BINARY_SUB_F32 : X86_LIR_BINARY_SUB_I32;
    if (core.op == SEMANTIC_LIR_OP_MUL) return f32 ? X86_LIR_BINARY_MUL_F32 : X86_LIR_BINARY_MUL_I32;
    if (core.op == SEMANTIC_LIR_OP_DIV) return f32 ? X86_LIR_BINARY_DIV_F32 : X86_LIR_BINARY_DIV_I32;
    if (core.op == SEMANTIC_LIR_OP_REM) return X86_LIR_BINARY_REM_I32;
    if (core.op == SEMANTIC_LIR_OP_BIT_AND) return X86_LIR_BINARY_BIT_AND_I32;
    if (core.op == SEMANTIC_LIR_OP_BIT_OR) return X86_LIR_BINARY_BIT_OR_I32;
    if (core.op == SEMANTIC_LIR_OP_BIT_XOR) return X86_LIR_BINARY_BIT_XOR_I32;
    if (core.op == SEMANTIC_LIR_OP_SHIFT_LEFT) return X86_LIR_BINARY_SHL_I32;
    if (core.op == SEMANTIC_LIR_OP_SHIFT_RIGHT) return X86_LIR_BINARY_SHR_I32;
    if (core.op == SEMANTIC_LIR_OP_LOGICAL_AND) return X86_LIR_BINARY_AND_BOOL;
    if (core.op == SEMANTIC_LIR_OP_LOGICAL_OR) return X86_LIR_BINARY_OR_BOOL;
    return 0u;
}

uint x86_lir_opcode(SemanticLirCore core)
{
    if (core.op == SEMANTIC_LIR_OP_CONST_I32 || core.op == SEMANTIC_LIR_OP_CONST_F32)
        return X86_LIR_OP_IMM_I32;
    if (core.op == SEMANTIC_LIR_OP_VALUE_GET) return X86_LIR_OP_ALIAS;
    if (core.op == SEMANTIC_LIR_OP_VALUE_SET || core.op == SEMANTIC_LIR_OP_STORE)
        return X86_LIR_OP_STORE_LOCAL;
    if ((core.op >= SEMANTIC_LIR_OP_ADD && core.op <= SEMANTIC_LIR_OP_SHIFT_RIGHT) ||
        core.op == SEMANTIC_LIR_OP_LOGICAL_AND || core.op == SEMANTIC_LIR_OP_LOGICAL_OR)
        return X86_LIR_OP_BINARY;
    if (core.op == SEMANTIC_LIR_OP_COMPARE) return X86_LIR_OP_COMPARE;
    if (core.op == SEMANTIC_LIR_OP_NEGATE || core.op == SEMANTIC_LIR_OP_LOGICAL_NOT)
        return X86_LIR_OP_UNARY;
    if (core.op == SEMANTIC_LIR_OP_CALL_HOST) return X86_LIR_OP_CALL_HOST;
    if (core.op == SEMANTIC_LIR_OP_CALL_SYMBOL) return X86_LIR_OP_CALL_SYMBOL;
    if (core.op == SEMANTIC_LIR_OP_CALL_INTRINSIC) return X86_LIR_OP_PRINT_I32;
    if (core.op == SEMANTIC_LIR_OP_AGGREGATE_NEW) return X86_LIR_OP_ARRAY_ADDR;
    if (core.op == SEMANTIC_LIR_OP_LOAD &&
        (core.flags & SEMANTIC_LIR_FLAG_INDEXED) != 0u)
        return X86_LIR_OP_INDEX_LOAD;
    if (core.op == SEMANTIC_LIR_OP_LOAD &&
        (core.flags & SEMANTIC_LIR_FLAG_FIELD) != 0u)
        return X86_LIR_OP_FIELD_LOAD;
    if (core.op == SEMANTIC_LIR_OP_CALL)
        return X86_LIR_OP_CALL;
    if (core.op == SEMANTIC_LIR_OP_IF_BEGIN || core.op == SEMANTIC_LIR_OP_ELSE ||
        core.op == SEMANTIC_LIR_OP_BRANCH || core.op == SEMANTIC_LIR_OP_BRANCH_IF)
        return X86_LIR_OP_BRANCH;
    if (core.op == SEMANTIC_LIR_OP_BLOCK_BEGIN ||
        core.op == SEMANTIC_LIR_OP_LOOP_BEGIN ||
        core.op == SEMANTIC_LIR_OP_CONTROL_END)
        return X86_LIR_OP_LABEL;
    if (core.op == SEMANTIC_LIR_OP_RETURN) return X86_LIR_OP_RETURN;
    return 0u;
}

bool x86_lir_supported(SemanticLirCore core)
{
    // Semantic branch targets are stable LIR control-row identities. They
    // become x86 relative targets only in the control-label resolver.
    // Host calls require service-specific ABI validation in scatter. Compiler
    // intrinsics likewise validate their stable tag there.
    return x86_lir_opcode(core) != 0u &&
        core.op != SEMANTIC_LIR_OP_CALL_HOST;
}
