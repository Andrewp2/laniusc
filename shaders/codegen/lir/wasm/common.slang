import codegen.lowering_ir;
import codegen.optimization_ir;
import primitive_types;
import hir_records;

static const uint WASM_LIR_INVALID = 0xffffffffu;
static const uint TY_FLOAT = 5u;
static const uint TY_UINT = 4u;
static const uint TY_CHAR = 6u;
static const uint TY_STRING = 7u;

// A call whose checked result is the never type `!`.
bool wasm_never_call(OptIrNodeCore core)
{
    return core.type_id == SCALAR_NEVER &&
        (opt_ir_op(core) == SEMANTIC_LIR_OP_CALL || opt_ir_op(core) == SEMANTIC_LIR_OP_CALL_SYMBOL);
}

// Bytes per native layout word in Wasm linear memory.
static const uint WASM_WORD_BYTES = 4u;

// The row's value is a struct, enum, or array (as x86_semantic_type_is_aggregate).
bool wasm_type_is_aggregate(OptIrNodeCore core)
{
    if (core.type_id == SEMANTIC_LIR_TY_POINTER) return false;
    uint type_ref_tag = opt_ir_type_ref_tag(core);
    return type_ref_tag == SEMANTIC_TYPE_REF_INSTANCE ||
        (type_ref_tag == SEMANTIC_TYPE_REF_SCALAR &&
         core.type_ref_payload >= 128u) ||
        (type_ref_tag == SEMANTIC_TYPE_REF_INVALID && core.type_id >= 128u);
}

// Wasm aggregates use the native layout with nested aggregates inline: a
// value is the address of its first word, a nested field or element is the
// address inside its owner, and storing one copies its words. Slice
// descriptors (array-pair rows) have no inline Wasm representation.
bool wasm_inline_aggregate(OptIrNodeCore core)
{
    return wasm_type_is_aggregate(core) && core.value_word_count != 0u &&
        core.value_word_count != WASM_LIR_INVALID &&
        (core.flags & SEMANTIC_LIR_FLAG_ARRAY_PAIR) == 0u;
}

// A local assignment of an aggregate snapshots the value into a fresh heap
// block, so the local never aliases its source. Constructors and copies
// already produce a fresh block.
bool wasm_set_copies_aggregate(OptIrNodeCore core, uint value_op)
{
    uint op = opt_ir_op(core);
    bool local_set = op == SEMANTIC_LIR_OP_VALUE_SET ||
        (op == SEMANTIC_LIR_OP_STORE &&
         (core.flags & (SEMANTIC_LIR_FLAG_INDEXED | SEMANTIC_LIR_FLAG_FIELD)) == 0u);
    return local_set && wasm_inline_aggregate(core) &&
        value_op != SEMANTIC_LIR_OP_AGGREGATE_NEW &&
        value_op != SEMANTIC_LIR_OP_AGGREGATE_COPY;
}

// A field or element store of an aggregate copies its words into place.
bool wasm_store_copies_aggregate(OptIrNodeCore core)
{
    return opt_ir_op(core) == SEMANTIC_LIR_OP_STORE &&
        (core.flags & (SEMANTIC_LIR_FLAG_INDEXED | SEMANTIC_LIR_FLAG_FIELD)) != 0u &&
        wasm_inline_aggregate(core);
}

// Rows of the heap snapshot shared by AGGREGATE_COPY and aggregate sets.
static const uint WASM_HEAP_COPY_ROWS = 10u;

static const uint WASM_INTRINSIC_PRINT = 1u;
static const uint WASM_INTRINSIC_ASSERT = 2u;

// `a || b` lowers to: set T = a; `!a`; if { set T = b }; get T. The `!a` row
// names `a` itself, which a stack machine already consumed into T, so Wasm
// reloads T (the preceding row's local) before negating it.
bool wasm_short_circuit_not(OptIrNodeCore core)
{
    return opt_ir_op(core) == SEMANTIC_LIR_OP_LOGICAL_NOT &&
        (core.flags & SEMANTIC_LIR_FLAG_SYNTHETIC_CONTROL) != 0u;
}

bool wasm_reloads_short_circuit(OptIrNodeCore core, OptIrNodeOperands operands,
                                OptIrNodeCore previous, OptIrNodeOperands previous_operands)
{
    return wasm_short_circuit_not(core) &&
        opt_ir_op(previous) == SEMANTIC_LIR_OP_VALUE_SET &&
        (previous.flags & SEMANTIC_LIR_FLAG_SYNTHETIC_CONTROL) != 0u &&
        previous_operands.b == operands.a;
}

static const uint WASM_HIR_BLOCK = 6u;
static const uint WASM_HIR_CALL_EXPR = 19u;

// A call that is a whole expression statement (`f();`; compaction makes it a
// direct child of its block) leaves a result nobody consumes. Wasm needs one
// `drop` per result value after the call.
bool wasm_statement_call(StructuredBuffer<HirCore> hir_core, uint node)
{
    uint hir_count;
    uint stride;
    hir_core.GetDimensions(hir_count, stride);
    if (node >= hir_count || hir_core[node].kind != WASM_HIR_CALL_EXPR) return false;
    uint parent = hir_core[node].parent;
    return parent < hir_count && hir_core[parent].kind == WASM_HIR_BLOCK;
}

uint wasm_discarded_result_values(OptIrNodeCore core, bool statement_call)
{
    uint op = opt_ir_op(core);
    if (!statement_call ||
        (op != SEMANTIC_LIR_OP_CALL && op != SEMANTIC_LIR_OP_CALL_SYMBOL &&
         op != SEMANTIC_LIR_OP_CALL_HOST))
        return 0u;
    if (core.type_id == 0u || core.type_id == 1u || core.type_id == SCALAR_NEVER) return 0u;
    return core.type_id == TY_STRING ? 2u : 1u;
}

uint wasm_lir_count(OptIrNodeCore core, OptIrNodeOperands operands,
                    bool call_index_base, bool direct_field_store_receiver,
                    bool copy_set_value, uint discarded_values,
                    bool reload_short_circuit)
{
    if (opt_ir_op(core) == SEMANTIC_LIR_OP_NOP) return 0u;
    // A discarded call: the call row, then its drops.
    if (discarded_values != 0u) return 1u + discarded_values;
    if (reload_short_circuit) return 2u;
    // assert(c): `i32.eqz; if; unreachable; end`.
    if (opt_ir_op(core) == SEMANTIC_LIR_OP_CALL_INTRINSIC && operands.a == WASM_INTRINSIC_ASSERT)
        return 4u;
    // Expression operands are already on the Wasm stack when their semantic
    // owner is lowered. Signed integer negation therefore appends
    // `i32.const -1; i32.mul` and owns two target records.
    bool false_branch = opt_ir_op(core) == SEMANTIC_LIR_OP_BRANCH_IF &&
        (core.flags & SEMANTIC_LIR_FLAG_BRANCH_DEPTH_VALID) != 0u &&
        (core.flags & SEMANTIC_LIR_FLAG_BRANCH_FALSE) != 0u;
    if (opt_ir_op(core) == SEMANTIC_LIR_OP_AGGREGATE_NEW)
        return operands.b * 7u +
            ((operands.c & SEMANTIC_LIR_AGGREGATE_ENUM) != 0u ? 5u : 0u) + 5u;
    // Snapshot into a fresh heap block, as AGGREGATE_NEW allocates one:
    // save the source address, memory.copy its words, then push the new
    // address and bump the heap. An aggregate local set snapshots, then sets.
    if (opt_ir_op(core) == SEMANTIC_LIR_OP_AGGREGATE_COPY) return WASM_HEAP_COPY_ROWS;
    if (copy_set_value) return WASM_HEAP_COPY_ROWS + 1u;
    if (opt_ir_op(core) == SEMANTIC_LIR_OP_CONST_STRING) return 2u;
    // A call of a `-> !` function is followed by `unreachable`: the callee
    // has no result, and the stack after the call is polymorphic, so the
    // call fits a statement and any value position alike.
    if (wasm_never_call(core)) return 2u;
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
        return (call_index_base ? 8u : 6u) +
            (wasm_store_copies_aggregate(core) ? 1u : 0u);
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
        return (direct_field_store_receiver ? 8u : 7u) +
            (wasm_store_copies_aggregate(core) ? 1u : 0u);
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
    if (type_id == SCALAR_F64) return WASM_LIR_OP_UNREACHABLE;
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
    if (core.type_id == SCALAR_F64) return WASM_LIR_OP_UNREACHABLE;
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
    if (opt_ir_op(core) == SEMANTIC_LIR_OP_TRAP) return WASM_LIR_OP_UNREACHABLE;
    if (opt_ir_op(core) == SEMANTIC_LIR_OP_DROP) return WASM_LIR_OP_DROP;
    return WASM_LIR_OP_UNREACHABLE;
}

// A by-value aggregate snapshot copies the value's words. Slice descriptors
// and array views (array-pair rows) and packed byte arrays (type 131) have no
// Wasm representation yet. Nested aggregates are pointers in the Wasm layout,
// so the copy is one level deep, as Wasm constructors already are.
bool wasm_aggregate_copy_supported(OptIrNodeCore core)
{
    return opt_ir_op(core) == SEMANTIC_LIR_OP_AGGREGATE_COPY &&
        core.value_word_count != 0u && core.type_id != 131u &&
        (core.flags & (SEMANTIC_LIR_FLAG_ARRAY_PAIR | SEMANTIC_LIR_FLAG_PLACE_VIEW |
                       SEMANTIC_LIR_FLAG_NATIVE_PLACE)) == 0u;
}

bool wasm_lir_supported(OptIrNodeCore core)
{
    // Native f64 support does not imply a Wasm value or ABI representation.
    if (core.type_id == SCALAR_F64) return false;
    uint op = opt_ir_op(core);
    return op == SEMANTIC_LIR_OP_CONST_I32 || op == SEMANTIC_LIR_OP_CONST_F32 ||
        op == SEMANTIC_LIR_OP_CONST_STRING ||
        op == SEMANTIC_LIR_OP_VALUE_GET || op == SEMANTIC_LIR_OP_VALUE_SET ||
        op == SEMANTIC_LIR_OP_STORE ||
        (op >= SEMANTIC_LIR_OP_ADD && op <= SEMANTIC_LIR_OP_LOGICAL_NOT) ||
        op == SEMANTIC_LIR_OP_LOGICAL_AND || op == SEMANTIC_LIR_OP_LOGICAL_OR ||
        op == SEMANTIC_LIR_OP_CALL ||
        op == SEMANTIC_LIR_OP_CALL_SYMBOL ||
        op == SEMANTIC_LIR_OP_BLOCK_BEGIN || op == SEMANTIC_LIR_OP_LOOP_BEGIN ||
        op == SEMANTIC_LIR_OP_IF_BEGIN ||
        op == SEMANTIC_LIR_OP_ELSE || op == SEMANTIC_LIR_OP_CONTROL_END ||
        op == SEMANTIC_LIR_OP_AGGREGATE_NEW ||
        wasm_aggregate_copy_supported(core) ||
        (op == SEMANTIC_LIR_OP_LOAD &&
         (core.flags & (SEMANTIC_LIR_FLAG_INDEXED | SEMANTIC_LIR_FLAG_FIELD)) != 0u) ||
        ((op == SEMANTIC_LIR_OP_BRANCH || op == SEMANTIC_LIR_OP_BRANCH_IF) &&
         (core.flags & SEMANTIC_LIR_FLAG_BRANCH_DEPTH_VALID) != 0u) ||
        op == SEMANTIC_LIR_OP_RETURN || op == SEMANTIC_LIR_OP_DROP ||
        op == SEMANTIC_LIR_OP_TRAP;
}
