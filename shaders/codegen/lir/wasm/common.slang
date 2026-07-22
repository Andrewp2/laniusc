import codegen.lowering_ir;

static const uint WASM_LIR_INVALID = 0xffffffffu;
static const uint TY_FLOAT = 5u;
static const uint TY_UINT = 4u;
static const uint TY_CHAR = 6u;

uint wasm_lir_count(SemanticLirCore core, SemanticLirOperands operands)
{
    // Expression operands are already on the Wasm stack when their semantic
    // owner is lowered. Signed integer negation therefore appends
    // `i32.const -1; i32.mul` and owns two target records.
    bool false_branch = core.op == SEMANTIC_LIR_OP_BRANCH_IF &&
        (core.flags & SEMANTIC_LIR_FLAG_BRANCH_DEPTH_VALID) != 0u &&
        (core.flags & SEMANTIC_LIR_FLAG_BRANCH_FALSE) != 0u;
    if (core.op == SEMANTIC_LIR_OP_AGGREGATE_NEW)
        return operands.b * 6u + 5u;
    if (core.op == SEMANTIC_LIR_OP_CONST_STRING) return 2u;
    if (core.op == SEMANTIC_LIR_OP_LOAD &&
        (core.flags & SEMANTIC_LIR_FLAG_INDEXED) != 0u)
        return 4u;
    if (core.op == SEMANTIC_LIR_OP_LOAD &&
        (core.flags & SEMANTIC_LIR_FLAG_FIELD) != 0u)
        return 5u;
    // The language print intrinsic accepts an i32, while the stable Wasm
    // runtime boundary accepts i64. Keep that ABI choice in target lowering:
    // one row widens the checked value and one row calls import zero.
    if (core.op == SEMANTIC_LIR_OP_CALL_INTRINSIC && operands.a == 1u)
        return 2u;
    return (core.op == SEMANTIC_LIR_OP_NEGATE && core.type_id != TY_FLOAT) || false_branch
        ? 2u : 1u;
}

uint wasm_compare_opcode(uint predicate, uint type_id)
{
    if (type_id == TY_FLOAT)
    {
        if (predicate == 0u) return WASM_LIR_OP_F32_EQ;
        if (predicate == 1u) return WASM_LIR_OP_F32_NE;
        if (predicate == 2u) return WASM_LIR_OP_F32_LT;
        if (predicate == 3u) return WASM_LIR_OP_F32_GT;
        if (predicate == 4u) return WASM_LIR_OP_F32_LE;
        return WASM_LIR_OP_F32_GE;
    }
    if (predicate == 0u) return WASM_LIR_OP_I32_EQ;
    if (predicate == 1u) return WASM_LIR_OP_I32_NE;
    bool is_unsigned = type_id == TY_UINT || type_id == TY_CHAR;
    if (is_unsigned)
    {
        if (predicate == 2u) return WASM_LIR_OP_I32_LT_U;
        if (predicate == 3u) return WASM_LIR_OP_I32_GT_U;
        if (predicate == 4u) return WASM_LIR_OP_I32_LE_U;
        return WASM_LIR_OP_I32_GE_U;
    }
    if (predicate == 2u) return WASM_LIR_OP_I32_LT_S;
    if (predicate == 3u) return WASM_LIR_OP_I32_GT_S;
    if (predicate == 4u) return WASM_LIR_OP_I32_LE_S;
    return WASM_LIR_OP_I32_GE_S;
}

uint wasm_scalar_opcode(SemanticLirCore core, SemanticLirOperands operands)
{
    bool f32 = core.type_id == TY_FLOAT;
    if (core.op == SEMANTIC_LIR_OP_CONST_I32) return WASM_LIR_OP_I32_CONST;
    if (core.op == SEMANTIC_LIR_OP_CONST_F32) return WASM_LIR_OP_F32_CONST;
    if (core.op == SEMANTIC_LIR_OP_VALUE_GET) return WASM_LIR_OP_LOCAL_GET;
    if (core.op == SEMANTIC_LIR_OP_VALUE_SET || core.op == SEMANTIC_LIR_OP_STORE)
        return WASM_LIR_OP_LOCAL_SET;
    if (core.op == SEMANTIC_LIR_OP_ADD) return f32 ? WASM_LIR_OP_F32_ADD : WASM_LIR_OP_I32_ADD;
    if (core.op == SEMANTIC_LIR_OP_SUB) return f32 ? WASM_LIR_OP_F32_SUB : WASM_LIR_OP_I32_SUB;
    if (core.op == SEMANTIC_LIR_OP_MUL) return f32 ? WASM_LIR_OP_F32_MUL : WASM_LIR_OP_I32_MUL;
    if (core.op == SEMANTIC_LIR_OP_DIV) return f32 ? WASM_LIR_OP_F32_DIV : WASM_LIR_OP_I32_DIV_S;
    if (core.op == SEMANTIC_LIR_OP_REM) return WASM_LIR_OP_I32_REM_S;
    if (core.op == SEMANTIC_LIR_OP_BIT_AND) return WASM_LIR_OP_I32_AND;
    if (core.op == SEMANTIC_LIR_OP_BIT_OR) return WASM_LIR_OP_I32_OR;
    if (core.op == SEMANTIC_LIR_OP_BIT_XOR) return WASM_LIR_OP_I32_XOR;
    if (core.op == SEMANTIC_LIR_OP_SHIFT_LEFT) return WASM_LIR_OP_I32_SHL;
    if (core.op == SEMANTIC_LIR_OP_SHIFT_RIGHT) return WASM_LIR_OP_I32_SHR_S;
    if (core.op == SEMANTIC_LIR_OP_LOGICAL_AND) return WASM_LIR_OP_I32_AND;
    if (core.op == SEMANTIC_LIR_OP_LOGICAL_OR) return WASM_LIR_OP_I32_OR;
    if (core.op == SEMANTIC_LIR_OP_COMPARE)
        return wasm_compare_opcode(operands.c, core.type_id);
    if (core.op == SEMANTIC_LIR_OP_LOGICAL_NOT) return WASM_LIR_OP_I32_EQZ;
    if (core.op == SEMANTIC_LIR_OP_NEGATE && f32) return WASM_LIR_OP_F32_NEG;
    if (core.op == SEMANTIC_LIR_OP_CALL) return WASM_LIR_OP_CALL;
    if (core.op == SEMANTIC_LIR_OP_CALL_HOST) return WASM_LIR_OP_CALL_HOST;
    if (core.op == SEMANTIC_LIR_OP_CALL_SYMBOL) return WASM_LIR_OP_CALL_SYMBOL;
    if (core.op == SEMANTIC_LIR_OP_BLOCK_BEGIN) return WASM_LIR_OP_BLOCK;
    if (core.op == SEMANTIC_LIR_OP_LOOP_BEGIN) return WASM_LIR_OP_LOOP;
    if (core.op == SEMANTIC_LIR_OP_IF_BEGIN) return WASM_LIR_OP_IF;
    if (core.op == SEMANTIC_LIR_OP_ELSE) return WASM_LIR_OP_ELSE;
    if (core.op == SEMANTIC_LIR_OP_CONTROL_END) return WASM_LIR_OP_END;
    if (core.op == SEMANTIC_LIR_OP_BRANCH) return WASM_LIR_OP_BRANCH;
    if (core.op == SEMANTIC_LIR_OP_BRANCH_IF) return WASM_LIR_OP_BRANCH_IF;
    if (core.op == SEMANTIC_LIR_OP_RETURN) return WASM_LIR_OP_RETURN;
    if (core.op == SEMANTIC_LIR_OP_DROP) return WASM_LIR_OP_DROP;
    return WASM_LIR_OP_UNREACHABLE;
}

bool wasm_lir_supported(SemanticLirCore core)
{
    uint op = core.op;
    return op == SEMANTIC_LIR_OP_CONST_I32 || op == SEMANTIC_LIR_OP_CONST_F32 ||
        op == SEMANTIC_LIR_OP_CONST_STRING ||
        op == SEMANTIC_LIR_OP_VALUE_GET || op == SEMANTIC_LIR_OP_VALUE_SET ||
        op == SEMANTIC_LIR_OP_STORE ||
        (op >= SEMANTIC_LIR_OP_ADD && op <= SEMANTIC_LIR_OP_LOGICAL_NOT) ||
        op == SEMANTIC_LIR_OP_LOGICAL_AND || op == SEMANTIC_LIR_OP_LOGICAL_OR ||
        op == SEMANTIC_LIR_OP_CALL || op == SEMANTIC_LIR_OP_CALL_SYMBOL ||
        op == SEMANTIC_LIR_OP_BLOCK_BEGIN || op == SEMANTIC_LIR_OP_LOOP_BEGIN ||
        op == SEMANTIC_LIR_OP_IF_BEGIN ||
        op == SEMANTIC_LIR_OP_ELSE || op == SEMANTIC_LIR_OP_CONTROL_END ||
        op == SEMANTIC_LIR_OP_AGGREGATE_NEW ||
        (op == SEMANTIC_LIR_OP_LOAD &&
         (core.flags & (SEMANTIC_LIR_FLAG_INDEXED | SEMANTIC_LIR_FLAG_FIELD)) != 0u) ||
        ((op == SEMANTIC_LIR_OP_BRANCH || op == SEMANTIC_LIR_OP_BRANCH_IF) &&
         (core.flags & SEMANTIC_LIR_FLAG_BRANCH_DEPTH_VALID) != 0u) ||
        op == SEMANTIC_LIR_OP_RETURN || op == SEMANTIC_LIR_OP_DROP;
}
