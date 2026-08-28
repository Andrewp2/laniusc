import codegen.lowering_ir;
import codegen.optimization_ir;

static const uint WASM_LIR_INVALID = 0xffffffffu;
static const uint TY_FLOAT = 5u;
static const uint TY_UINT = 4u;
static const uint TY_CHAR = 6u;
static const uint TY_STRING = 7u;

uint wasm_lir_count(OptIrNodeCore core, OptIrNodeOperands operands,
                    bool call_index_base, bool direct_field_store_receiver)
{
    if (opt_ir_op(core) == SEMANTIC_LIR_OP_NOP) return 0u;
    // Expression operands are already on the Wasm stack when their semantic
    // owner is lowered. Signed integer negation therefore appends
    // `i32.const -1; i32.mul` and owns two target records.
    bool false_branch = opt_ir_op(core) == SEMANTIC_LIR_OP_BRANCH_IF &&
        (core.flags & SEMANTIC_LIR_FLAG_BRANCH_DEPTH_VALID) != 0u &&
        (core.flags & SEMANTIC_LIR_FLAG_BRANCH_FALSE) != 0u;
    if (opt_ir_op(core) == SEMANTIC_LIR_OP_AGGREGATE_NEW)
        return operands.b * 6u +
            ((operands.c & SEMANTIC_LIR_AGGREGATE_ENUM) != 0u ? 5u : 0u) + 5u;
    if (opt_ir_op(core) == SEMANTIC_LIR_OP_CONST_STRING) return 2u;
    // Strings are represented by the Wasm ABI as `(data_ptr, byte_len)`.
    // A semantic value operation still names one source value, so target
    // lowering expands its local access to the two ABI stack values here.
    if ((opt_ir_op(core) == SEMANTIC_LIR_OP_VALUE_GET ||
         opt_ir_op(core) == SEMANTIC_LIR_OP_VALUE_SET) && core.type_id == TY_STRING)
        return 2u;
    if (opt_ir_op(core) == SEMANTIC_LIR_OP_LOAD &&
        (core.flags & SEMANTIC_LIR_FLAG_INDEXED) != 0u)
        return call_index_base ? 6u : 4u;
    // The semantic schedule leaves `(aggregate, index, value)` on the stack.
    // Preserve the value while computing the byte address, then perform the
    // typed store. A call-produced aggregate follows the already evaluated
    // index, so that form also preserves the aggregate pointer.
    if (opt_ir_op(core) == SEMANTIC_LIR_OP_STORE &&
        (core.flags & SEMANTIC_LIR_FLAG_INDEXED) != 0u)
        return call_index_base ? 8u : 6u;
    if (opt_ir_op(core) == SEMANTIC_LIR_OP_LOAD &&
        (core.flags & SEMANTIC_LIR_FLAG_FIELD) != 0u)
        return 5u;
    // The semantic schedule leaves the evaluated receiver below the RHS.
    // Save the RHS, turn that receiver into the field address, and store.
    // This works for an arbitrarily deep member chain because each receiver is
    // consumed from the preceding semantic LOAD instead of being reconstructed
    // from a source declaration token.
    if (opt_ir_op(core) == SEMANTIC_LIR_OP_STORE &&
        (core.flags & SEMANTIC_LIR_FLAG_FIELD) != 0u)
        return direct_field_store_receiver ? 8u : 7u;
    // The language print intrinsic accepts an i32, while the stable Wasm
    // runtime boundary accepts i64. Keep that ABI choice in target lowering:
    // one row widens the checked value and one row calls import zero.
    if (opt_ir_op(core) == SEMANTIC_LIR_OP_CALL_INTRINSIC && operands.a == 1u)
        return 2u;
    return (opt_ir_op(core) == SEMANTIC_LIR_OP_NEGATE && core.type_id != TY_FLOAT) || false_branch ||
        (opt_ir_op(core) == SEMANTIC_LIR_OP_CALL_INTRINSIC &&
         operands.a == INTRINSIC_I32_ARRAY_DATA_PTR)
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
    bool is_unsigned = type_id == TY_UINT || type_id == TY_CHAR ||
        type_id == SEMANTIC_LIR_TY_POINTER;
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

uint wasm_scalar_opcode(OptIrNodeCore core, OptIrNodeOperands operands)
{
    bool f32 = core.type_id == TY_FLOAT;
    if (opt_ir_op(core) == SEMANTIC_LIR_OP_CONST_I32) return WASM_LIR_OP_I32_CONST;
    if (opt_ir_op(core) == SEMANTIC_LIR_OP_CONST_F32) return WASM_LIR_OP_F32_CONST;
    if (opt_ir_op(core) == SEMANTIC_LIR_OP_VALUE_GET) return WASM_LIR_OP_LOCAL_GET;
    if (opt_ir_op(core) == SEMANTIC_LIR_OP_VALUE_SET || opt_ir_op(core) == SEMANTIC_LIR_OP_STORE)
        return WASM_LIR_OP_LOCAL_SET;
    if (opt_ir_op(core) == SEMANTIC_LIR_OP_ADD) return f32 ? WASM_LIR_OP_F32_ADD : WASM_LIR_OP_I32_ADD;
    if (opt_ir_op(core) == SEMANTIC_LIR_OP_SUB) return f32 ? WASM_LIR_OP_F32_SUB : WASM_LIR_OP_I32_SUB;
    if (opt_ir_op(core) == SEMANTIC_LIR_OP_MUL) return f32 ? WASM_LIR_OP_F32_MUL : WASM_LIR_OP_I32_MUL;
    if (opt_ir_op(core) == SEMANTIC_LIR_OP_DIV) return f32 ? WASM_LIR_OP_F32_DIV : WASM_LIR_OP_I32_DIV_S;
    if (opt_ir_op(core) == SEMANTIC_LIR_OP_REM) return WASM_LIR_OP_I32_REM_S;
    if (opt_ir_op(core) == SEMANTIC_LIR_OP_BIT_AND) return WASM_LIR_OP_I32_AND;
    if (opt_ir_op(core) == SEMANTIC_LIR_OP_BIT_OR) return WASM_LIR_OP_I32_OR;
    if (opt_ir_op(core) == SEMANTIC_LIR_OP_BIT_XOR) return WASM_LIR_OP_I32_XOR;
    if (opt_ir_op(core) == SEMANTIC_LIR_OP_SHIFT_LEFT) return WASM_LIR_OP_I32_SHL;
    if (opt_ir_op(core) == SEMANTIC_LIR_OP_SHIFT_RIGHT) return WASM_LIR_OP_I32_SHR_S;
    if (opt_ir_op(core) == SEMANTIC_LIR_OP_LOGICAL_AND) return WASM_LIR_OP_I32_AND;
    if (opt_ir_op(core) == SEMANTIC_LIR_OP_LOGICAL_OR) return WASM_LIR_OP_I32_OR;
    if (opt_ir_op(core) == SEMANTIC_LIR_OP_COMPARE)
        return wasm_compare_opcode(operands.c, core.type_id);
    if (opt_ir_op(core) == SEMANTIC_LIR_OP_LOGICAL_NOT) return WASM_LIR_OP_I32_EQZ;
    if (opt_ir_op(core) == SEMANTIC_LIR_OP_NEGATE && f32) return WASM_LIR_OP_F32_NEG;
    if (opt_ir_op(core) == SEMANTIC_LIR_OP_CALL) return WASM_LIR_OP_CALL;
    if (opt_ir_op(core) == SEMANTIC_LIR_OP_CALL_HOST) return WASM_LIR_OP_CALL_HOST;
    if (opt_ir_op(core) == SEMANTIC_LIR_OP_CALL_SYMBOL) return WASM_LIR_OP_CALL_SYMBOL;
    if (opt_ir_op(core) == SEMANTIC_LIR_OP_BLOCK_BEGIN) return WASM_LIR_OP_BLOCK;
    if (opt_ir_op(core) == SEMANTIC_LIR_OP_LOOP_BEGIN) return WASM_LIR_OP_LOOP;
    if (opt_ir_op(core) == SEMANTIC_LIR_OP_IF_BEGIN) return WASM_LIR_OP_IF;
    if (opt_ir_op(core) == SEMANTIC_LIR_OP_ELSE) return WASM_LIR_OP_ELSE;
    if (opt_ir_op(core) == SEMANTIC_LIR_OP_CONTROL_END) return WASM_LIR_OP_END;
    if (opt_ir_op(core) == SEMANTIC_LIR_OP_BRANCH) return WASM_LIR_OP_BRANCH;
    if (opt_ir_op(core) == SEMANTIC_LIR_OP_BRANCH_IF) return WASM_LIR_OP_BRANCH_IF;
    if (opt_ir_op(core) == SEMANTIC_LIR_OP_RETURN) return WASM_LIR_OP_RETURN;
    if (opt_ir_op(core) == SEMANTIC_LIR_OP_DROP) return WASM_LIR_OP_DROP;
    return WASM_LIR_OP_UNREACHABLE;
}

bool wasm_lir_supported(OptIrNodeCore core)
{
    uint op = opt_ir_op(core);
    return op == SEMANTIC_LIR_OP_CONST_I32 || op == SEMANTIC_LIR_OP_CONST_F32 ||
        op == SEMANTIC_LIR_OP_CONST_STRING ||
        op == SEMANTIC_LIR_OP_VALUE_GET || op == SEMANTIC_LIR_OP_VALUE_SET ||
        op == SEMANTIC_LIR_OP_STORE ||
        (op >= SEMANTIC_LIR_OP_ADD && op <= SEMANTIC_LIR_OP_LOGICAL_NOT) ||
        op == SEMANTIC_LIR_OP_LOGICAL_AND || op == SEMANTIC_LIR_OP_LOGICAL_OR ||
        op == SEMANTIC_LIR_OP_CALL || op == SEMANTIC_LIR_OP_CALL_INTRINSIC ||
        op == SEMANTIC_LIR_OP_CALL_SYMBOL ||
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
