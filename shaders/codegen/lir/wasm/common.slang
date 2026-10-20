import codegen.lowering_ir;
import codegen.optimization_ir;
import primitive_types;
import hir_records;
import native_value_layout;

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

// ---- Linear-memory model (docs/wasm-memory-layout.md) ----
// Wasm consumes the shared native layout (native_value_layout.slang): a value
// of n words occupies n eight-byte words, word k at byte offset -8k from the
// value's address. A scalar fills the low bytes of its word at its own width
// (pointer-sized integers are four bytes on wasm32, i64 is eight).
static const uint WASM_WORD_BYTES = 8u;
// Global 0 is the shadow stack pointer. A function with a frame lowers it by
// the frame size in its prologue and restores it before every return; inside
// the body the pointer is the frame base.
static const uint WASM_STACK_POINTER = 0u;
static const uint WASM_HIR_FUNCTION = 3u;
static const uint WASM_HIR_TYPE = 5u;
// wasm_frame_slots per semantic row: the slot's absolute word 0, a parameter
// home's checked type, an argument view's descriptor word 0, and that view's
// array length (frame_words.slang, frame_bounds.slang).
static const uint WASM_FRAME_SLOT_STRIDE = 4u;

// Target-private temporaries, declared after a function's own locals in this
// order (module_emit_functions.slang, resolve_indices.slang).
static const uint WASM_SYNTHETIC_I32_TEMP = 0xfffffffeu;
static const uint WASM_SYNTHETIC_F32_TEMP = 0xfffffffdu;
static const uint WASM_SYNTHETIC_I32_ADDRESS_TEMP = 0xfffffffcu;
static const uint WASM_SYNTHETIC_I64_TEMP = 0xfffffffbu;
static const uint WASM_SYNTHETIC_I32_INDEX_TEMP = 0xfffffffau;

// The row's value is a struct, enum, array or slice descriptor (as
// x86_semantic_type_is_aggregate). Such a value is the address of its word 0.
bool wasm_type_is_aggregate(OptIrNodeCore core)
{
    if (core.type_id == SEMANTIC_LIR_TY_POINTER) return false;
    uint type_ref_tag = opt_ir_type_ref_tag(core);
    return type_ref_tag == SEMANTIC_TYPE_REF_INSTANCE ||
        (type_ref_tag == SEMANTIC_TYPE_REF_SCALAR &&
         core.type_ref_payload >= 128u) ||
        (type_ref_tag == SEMANTIC_TYPE_REF_INVALID && core.type_id >= 128u);
}

// An aggregate value with a known width. Slices are three-word descriptors
// (data, length, byte stride), like any other aggregate.
bool wasm_inline_aggregate(OptIrNodeCore core)
{
    return wasm_type_is_aggregate(core) && core.value_word_count != WASM_LIR_INVALID;
}

// A local assignment of an aggregate copies the value into the assignment's
// own frame slot, so the local never aliases its source. A snapshot, a call
// result or an intrinsic descriptor already lives in a slot of its own row.
bool wasm_set_copies_aggregate(OptIrNodeCore core, uint value_op)
{
    uint op = opt_ir_op(core);
    bool local_set = op == SEMANTIC_LIR_OP_VALUE_SET ||
        (op == SEMANTIC_LIR_OP_STORE &&
         (core.flags & (SEMANTIC_LIR_FLAG_INDEXED | SEMANTIC_LIR_FLAG_FIELD)) == 0u);
    return local_set && wasm_inline_aggregate(core) &&
        value_op != SEMANTIC_LIR_OP_AGGREGATE_COPY &&
        value_op != SEMANTIC_LIR_OP_CALL && value_op != SEMANTIC_LIR_OP_CALL_SYMBOL &&
        value_op != SEMANTIC_LIR_OP_CALL_INTRINSIC;
}

// `[value; count]` stores its one element, then fills the rest by doubling:
// each step copies the filled prefix (at most the remainder) after itself.
// The element's word count of a supported repeat, else WASM_LIR_INVALID.
uint wasm_repeat_element_words(OptIrNodeCore core, OptIrNodeOperands operands,
                               StructuredBuffer<SemanticLirAggregateElement> elements)
{
    if (opt_ir_op(core) != SEMANTIC_LIR_OP_AGGREGATE_NEW ||
        operands.c != SEMANTIC_LIR_AGGREGATE_REPEAT || operands.b != 1u)
        return WASM_LIR_INVALID;
    uint count;
    uint stride;
    elements.GetDimensions(count, stride);
    if (operands.a >= count) return WASM_LIR_INVALID;
    SemanticLirAggregateElement element = elements[operands.a];
    return element.word_offset == 0u && element.word_count != 0u &&
        element.word_count != WASM_LIR_INVALID &&
        core.value_word_count != WASM_LIR_INVALID &&
        core.value_word_count % element.word_count == 0u
        ? element.word_count : WASM_LIR_INVALID;
}

uint wasm_repeat_steps(uint element_words, uint total_words)
{
    if (element_words == 0u || element_words == WASM_LIR_INVALID) return 0u;
    uint filled = element_words;
    uint steps = 0u;
    for (uint index = 0u; index < 32u && filled < total_words; index++)
    {
        filled += min(filled, total_words - filled);
        steps += 1u;
    }
    return steps;
}

// The words already filled before doubling step `step`, and the words that
// step copies.
void wasm_repeat_step(uint element_words, uint total_words, uint step,
                      out uint filled_words, out uint length_words)
{
    uint filled = element_words;
    uint length = 0u;
    for (uint index = 0u; index < 32u && filled < total_words; index++)
    {
        length = min(filled, total_words - filled);
        if (index == step) break;
        filled += length;
    }
    filled_words = filled;
    length_words = length;
}

// A header row (the function item's own rows) of an address-taken
// declaration: its ADDRESS owns the declaration's home in the frame.
bool wasm_home_row(uint row, StructuredBuffer<OptIrNodeCore> cores,
                   StructuredBuffer<uint> source_hir, StructuredBuffer<HirCore> hir_core)
{
    uint rows;
    uint stride;
    cores.GetDimensions(rows, stride);
    uint hir_count;
    hir_core.GetDimensions(hir_count, stride);
    if (row >= rows || opt_ir_op(cores[row]) != SEMANTIC_LIR_OP_ADDRESS) return false;
    uint node = source_hir[row];
    return node < hir_count && hir_core[node].kind == WASM_HIR_FUNCTION;
}

// Frame words a row owns: a declaration home, or the slot of a value the row
// materializes in memory (a constructor, a snapshot, a copied local
// assignment, a call's aggregate result, or a raw-parts slice descriptor).
// Every slot has at least one word, so its address is unique.
uint wasm_row_frame_words(OptIrNodeCore core, OptIrNodeOperands operands,
                          bool home_row, uint4 home_storage, uint value_op,
                          bool discarded_call)
{
    uint op = opt_ir_op(core);
    uint words = core.value_word_count == WASM_LIR_INVALID ? 0u : core.value_word_count;
    if (op == SEMANTIC_LIR_OP_ADDRESS)
        return home_row && home_storage.x != 0u ? max(home_storage.y, 1u) : 0u;
    if (op == SEMANTIC_LIR_OP_AGGREGATE_NEW || op == SEMANTIC_LIR_OP_AGGREGATE_COPY)
        return max(words, 1u);
    if (op == SEMANTIC_LIR_OP_CALL_INTRINSIC && intrinsic_slice_from_raw_parts(operands.a))
        return NATIVE_SLICE_WORDS;
    if ((op == SEMANTIC_LIR_OP_CALL || op == SEMANTIC_LIR_OP_CALL_SYMBOL) &&
        !discarded_call && wasm_inline_aggregate(core))
        return max(words, 1u);
    if (wasm_set_copies_aggregate(core, value_op)) return max(words, 1u);
    return 0u;
}

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

// A range loop tests exhaustion (`value != bound`) between reading the
// induction value and incrementing it, and both read one VALUE_GET row. A
// stack machine consumes that value in the test, so after the exit branch
// Wasm pushes the induction variable again. Returns its declaration, or
// WASM_LIR_INVALID. Loop-exit tests are `<` or `<=`; only exhaustion is `!=`.
uint wasm_exhaustion_reload(OptIrNodeCore core, OptIrNodeOperands operands,
                            StructuredBuffer<OptIrNodeCore> cores,
                            StructuredBuffer<OptIrNodeOperands> row_operands, uint count)
{
    if (opt_ir_op(core) != SEMANTIC_LIR_OP_BRANCH_IF ||
        (core.flags & (SEMANTIC_LIR_FLAG_SYNTHETIC_CONTROL | SEMANTIC_LIR_FLAG_BRANCH_FALSE)) !=
            (SEMANTIC_LIR_FLAG_SYNTHETIC_CONTROL | SEMANTIC_LIR_FLAG_BRANCH_FALSE) ||
        operands.a >= count)
        return WASM_LIR_INVALID;
    OptIrNodeCore compare = cores[operands.a];
    OptIrNodeOperands compare_operands = row_operands[operands.a];
    if (opt_ir_op(compare) != SEMANTIC_LIR_OP_COMPARE || compare_operands.c != 1u ||
        (compare.flags & SEMANTIC_LIR_FLAG_SYNTHETIC_CONTROL) == 0u ||
        compare_operands.a >= count ||
        opt_ir_op(cores[compare_operands.a]) != SEMANTIC_LIR_OP_VALUE_GET)
        return WASM_LIR_INVALID;
    return row_operands[compare_operands.a].a;
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

// Wasm value classes. Pointer-sized integers are i32 on wasm32 (the host ABI
// passes i32 lengths and addresses); i64 and u64 are native i64.
static const uint WASM_CLASS_I32 = 0u;
static const uint WASM_CLASS_I64 = 1u;
static const uint WASM_CLASS_F32 = 2u;
static const uint WASM_CLASS_NONE = 3u;

uint wasm_scalar_class(uint type_id)
{
    if (type_id == SCALAR_I64 || type_id == SCALAR_U64) return WASM_CLASS_I64;
    if (type_id == SCALAR_F32) return WASM_CLASS_F32;
    if (type_id == SCALAR_F64) return WASM_CLASS_NONE;
    return WASM_CLASS_I32;
}

// The class of the value a row leaves on the stack (a comparison's type is
// its operands' type; its result is a bool).
uint wasm_row_value_class(OptIrNodeCore core)
{
    return opt_ir_op(core) == SEMANTIC_LIR_OP_COMPARE
        ? WASM_CLASS_I32 : wasm_scalar_class(core.type_id);
}

// Rows that renormalize an i32-class value to a narrow integer type.
uint wasm_narrow_rows(uint type_id)
{
    if (type_id == SCALAR_U8 || type_id == SCALAR_U16) return 2u;
    return type_id == SCALAR_I8 || type_id == SCALAR_I16 ? 1u : 0u;
}

// The class change of `value as T`, or NOP when the class is kept.
uint wasm_convert_class_opcode(uint target, uint source)
{
    uint target_class = wasm_scalar_class(target);
    uint source_class = wasm_scalar_class(source);
    bool source_unsigned = scalar_is_unsigned_value(source);
    bool target_unsigned = scalar_is_unsigned_value(target);
    if (target_class == WASM_CLASS_NONE || source_class == WASM_CLASS_NONE)
        return WASM_LIR_OP_UNREACHABLE;
    if (target_class == source_class) return WASM_LIR_OP_NOP;
    if (target_class == WASM_CLASS_I64 && source_class == WASM_CLASS_I32)
        return source_unsigned ? WASM_LIR_OP_I64_EXTEND_I32_U : WASM_LIR_OP_I64_EXTEND_I32_S;
    if (target_class == WASM_CLASS_I32 && source_class == WASM_CLASS_I64)
        return WASM_LIR_OP_I32_WRAP_I64;
    if (target_class == WASM_CLASS_F32)
        return source_class == WASM_CLASS_I64
            ? (source_unsigned ? WASM_LIR_OP_F32_CONVERT_I64_U : WASM_LIR_OP_F32_CONVERT_I64_S)
            : (source_unsigned ? WASM_LIR_OP_F32_CONVERT_I32_U : WASM_LIR_OP_F32_CONVERT_I32_S);
    return target_class == WASM_CLASS_I64
        ? (target_unsigned ? WASM_LIR_OP_I64_TRUNC_F32_U : WASM_LIR_OP_I64_TRUNC_F32_S)
        : (target_unsigned ? WASM_LIR_OP_I32_TRUNC_F32_U : WASM_LIR_OP_I32_TRUNC_F32_S);
}

// A conversion is its class change (operands.b is the source scalar), then
// the narrow renormalization of an i32-class target.
uint wasm_convert_class_rows(OptIrNodeCore core, OptIrNodeOperands operands)
{
    return wasm_convert_class_opcode(core.type_id, operands.b) == WASM_LIR_OP_NOP ? 0u : 1u;
}

uint wasm_convert_rows(OptIrNodeCore core, OptIrNodeOperands operands)
{
    return max(1u, wasm_convert_class_rows(core, operands) +
        (wasm_scalar_class(core.type_id) == WASM_CLASS_I32 ? wasm_narrow_rows(core.type_id) : 0u));
}

// A shift whose amount has another class than the shifted value first
// converts the amount (Wasm shifts take both operands in one class).
uint wasm_shift_amount_opcode(OptIrNodeCore core, uint amount_type)
{
    uint op = opt_ir_op(core);
    if (op != SEMANTIC_LIR_OP_SHIFT_LEFT && op != SEMANTIC_LIR_OP_SHIFT_RIGHT)
        return WASM_LIR_OP_NOP;
    uint value_class = wasm_scalar_class(core.type_id);
    uint amount_class = wasm_scalar_class(amount_type);
    if (value_class == amount_class) return WASM_LIR_OP_NOP;
    if (value_class == WASM_CLASS_I64 && amount_class == WASM_CLASS_I32)
        return WASM_LIR_OP_I64_EXTEND_I32_U;
    if (value_class == WASM_CLASS_I32 && amount_class == WASM_CLASS_I64)
        return WASM_LIR_OP_I32_WRAP_I64;
    return WASM_LIR_OP_UNREACHABLE;
}

// A 64-bit constant whose high word is the sign extension of its low word
// is one `i64.const`; any other is built from its two words.
bool wasm_const_i64_is_short(OptIrNodeOperands operands)
{
    return operands.b == ((operands.a & 0x80000000u) != 0u ? 0xffffffffu : 0u);
}

uint wasm_const_i64_rows(OptIrNodeCore core, OptIrNodeOperands operands)
{
    return wasm_scalar_class(core.type_id) != WASM_CLASS_I64 ||
        wasm_const_i64_is_short(operands) ? 1u : 5u;
}

uint wasm_compare_opcode(uint predicate, uint type_id)
{
    uint value_class = wasm_scalar_class(type_id);
    if (value_class == WASM_CLASS_NONE) return WASM_LIR_OP_UNREACHABLE;
    if (value_class == WASM_CLASS_F32)
    {
        if (predicate == 0u) return WASM_LIR_OP_F32_EQ;
        if (predicate == 1u) return WASM_LIR_OP_F32_NE;
        if (predicate == 2u) return WASM_LIR_OP_F32_LT;
        if (predicate == 3u) return WASM_LIR_OP_F32_GT;
        if (predicate == 4u) return WASM_LIR_OP_F32_LE;
        return WASM_LIR_OP_F32_GE;
    }
    // i64 comparisons keep the i32 order, eleven opcodes later.
    uint shift = value_class == WASM_CLASS_I64 ? WASM_LIR_OP_I64_EQ - WASM_LIR_OP_I32_EQ : 0u;
    if (predicate == 0u) return WASM_LIR_OP_I32_EQ + shift;
    if (predicate == 1u) return WASM_LIR_OP_I32_NE + shift;
    uint is_unsigned = scalar_is_unsigned_value(type_id) ? 1u : 0u;
    if (predicate == 2u) return WASM_LIR_OP_I32_LT_S + is_unsigned + shift;
    if (predicate == 3u) return WASM_LIR_OP_I32_GT_S + is_unsigned + shift;
    if (predicate == 4u) return WASM_LIR_OP_I32_LE_S + is_unsigned + shift;
    return WASM_LIR_OP_I32_GE_S + is_unsigned + shift;
}

uint wasm_scalar_opcode(OptIrNodeCore core, OptIrNodeOperands operands)
{
    uint value_class = wasm_scalar_class(core.type_id);
    if (value_class == WASM_CLASS_NONE) return WASM_LIR_OP_UNREACHABLE;
    bool f32 = value_class == WASM_CLASS_F32;
    // i64 integer arithmetic keeps the i32 order (add through shr_u).
    uint wide = value_class == WASM_CLASS_I64 ? WASM_LIR_OP_I64_ADD - WASM_LIR_OP_I32_ADD : 0u;
    uint is_unsigned = scalar_is_unsigned_value(core.type_id) ? 1u : 0u;
    uint op = opt_ir_op(core);
    if (op == SEMANTIC_LIR_OP_CONST_I32) return WASM_LIR_OP_I32_CONST;
    if (op == SEMANTIC_LIR_OP_CONST_I64)
        return value_class == WASM_CLASS_I64 ? WASM_LIR_OP_I64_CONST : WASM_LIR_OP_I32_CONST;
    if (op == SEMANTIC_LIR_OP_CONST_F32) return WASM_LIR_OP_F32_CONST;
    if (op == SEMANTIC_LIR_OP_VALUE_GET) return WASM_LIR_OP_LOCAL_GET;
    if (op == SEMANTIC_LIR_OP_VALUE_SET || op == SEMANTIC_LIR_OP_STORE)
        return WASM_LIR_OP_LOCAL_SET;
    if (op == SEMANTIC_LIR_OP_ADD) return f32 ? WASM_LIR_OP_F32_ADD : WASM_LIR_OP_I32_ADD + wide;
    if (op == SEMANTIC_LIR_OP_SUB) return f32 ? WASM_LIR_OP_F32_SUB : WASM_LIR_OP_I32_SUB + wide;
    if (op == SEMANTIC_LIR_OP_MUL) return f32 ? WASM_LIR_OP_F32_MUL : WASM_LIR_OP_I32_MUL + wide;
    if (op == SEMANTIC_LIR_OP_DIV)
        return f32 ? WASM_LIR_OP_F32_DIV : WASM_LIR_OP_I32_DIV_S + is_unsigned + wide;
    if (f32 && op >= SEMANTIC_LIR_OP_REM && op <= SEMANTIC_LIR_OP_SHIFT_RIGHT)
        return WASM_LIR_OP_UNREACHABLE;
    if (op == SEMANTIC_LIR_OP_REM) return WASM_LIR_OP_I32_REM_S + is_unsigned + wide;
    if (op == SEMANTIC_LIR_OP_BIT_AND) return WASM_LIR_OP_I32_AND + wide;
    if (op == SEMANTIC_LIR_OP_BIT_OR) return WASM_LIR_OP_I32_OR + wide;
    if (op == SEMANTIC_LIR_OP_BIT_XOR) return WASM_LIR_OP_I32_XOR + wide;
    if (op == SEMANTIC_LIR_OP_SHIFT_LEFT) return WASM_LIR_OP_I32_SHL + wide;
    if (op == SEMANTIC_LIR_OP_SHIFT_RIGHT) return WASM_LIR_OP_I32_SHR_S + is_unsigned + wide;
    if (op == SEMANTIC_LIR_OP_LOGICAL_AND) return WASM_LIR_OP_I32_AND;
    if (op == SEMANTIC_LIR_OP_LOGICAL_OR) return WASM_LIR_OP_I32_OR;
    if (op == SEMANTIC_LIR_OP_COMPARE)
        return wasm_compare_opcode(operands.c, core.type_id);
    if (op == SEMANTIC_LIR_OP_LOGICAL_NOT) return WASM_LIR_OP_I32_EQZ;
    if (op == SEMANTIC_LIR_OP_NEGATE && f32) return WASM_LIR_OP_F32_NEG;
    if (op == SEMANTIC_LIR_OP_CALL) return WASM_LIR_OP_CALL;
    if (op == SEMANTIC_LIR_OP_CALL_HOST) return WASM_LIR_OP_CALL_HOST;
    if (op == SEMANTIC_LIR_OP_CALL_SYMBOL) return WASM_LIR_OP_CALL_SYMBOL;
    if (op == SEMANTIC_LIR_OP_BLOCK_BEGIN) return WASM_LIR_OP_BLOCK;
    if (op == SEMANTIC_LIR_OP_LOOP_BEGIN) return WASM_LIR_OP_LOOP;
    if (op == SEMANTIC_LIR_OP_IF_BEGIN) return WASM_LIR_OP_IF;
    if (op == SEMANTIC_LIR_OP_ELSE) return WASM_LIR_OP_ELSE;
    if (op == SEMANTIC_LIR_OP_CONTROL_END) return WASM_LIR_OP_END;
    if (op == SEMANTIC_LIR_OP_BRANCH) return WASM_LIR_OP_BRANCH;
    if (op == SEMANTIC_LIR_OP_BRANCH_IF) return WASM_LIR_OP_BRANCH_IF;
    if (op == SEMANTIC_LIR_OP_RETURN) return WASM_LIR_OP_RETURN;
    if (op == SEMANTIC_LIR_OP_TRAP) return WASM_LIR_OP_UNREACHABLE;
    if (op == SEMANTIC_LIR_OP_DROP) return WASM_LIR_OP_DROP;
    return WASM_LIR_OP_UNREACHABLE;
}


// Rows of a scalar or control operation (memory operations, constructors,
// snapshots and returns are planned below; wasm_plan_rows).
uint wasm_lir_count(OptIrNodeCore core, OptIrNodeOperands operands,
                    uint discarded_values, bool reload_short_circuit,
                    uint shift_amount_type, bool exhaustion_reload)
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
    if (false_branch && exhaustion_reload) return 3u;
    if (opt_ir_op(core) == SEMANTIC_LIR_OP_CONST_STRING) return 2u;
    if (opt_ir_op(core) == SEMANTIC_LIR_OP_CONST_I64) return wasm_const_i64_rows(core, operands);
    if (opt_ir_op(core) == SEMANTIC_LIR_OP_CONVERT) return wasm_convert_rows(core, operands);
    if (wasm_shift_amount_opcode(core, shift_amount_type) != WASM_LIR_OP_NOP) return 2u;
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
    // The language print intrinsic accepts an i32, while the stable Wasm
    // runtime boundary accepts i64. Keep that ABI choice in target lowering:
    // one row widens the checked value and one row calls import zero.
    if (opt_ir_op(core) == SEMANTIC_LIR_OP_CALL_INTRINSIC && operands.a == 1u)
        return 2u;
    return (opt_ir_op(core) == SEMANTIC_LIR_OP_NEGATE && core.type_id != TY_FLOAT) ||
        false_branch ? 2u : 1u;
}


bool wasm_lir_supported(OptIrNodeCore core)
{
    // Native f64 support does not imply a Wasm value or ABI representation.
    if (core.type_id == SCALAR_F64) return false;
    uint op = opt_ir_op(core);
    return op == SEMANTIC_LIR_OP_CONST_I32 || op == SEMANTIC_LIR_OP_CONST_F32 ||
        op == SEMANTIC_LIR_OP_CONST_I64 || op == SEMANTIC_LIR_OP_CONST_STRING ||
        op == SEMANTIC_LIR_OP_VALUE_GET || op == SEMANTIC_LIR_OP_VALUE_SET ||
        op == SEMANTIC_LIR_OP_STORE ||
        (op >= SEMANTIC_LIR_OP_ADD && op <= SEMANTIC_LIR_OP_CONVERT) ||
        op == SEMANTIC_LIR_OP_LOGICAL_AND || op == SEMANTIC_LIR_OP_LOGICAL_OR ||
        op == SEMANTIC_LIR_OP_CALL ||
        op == SEMANTIC_LIR_OP_CALL_SYMBOL ||
        op == SEMANTIC_LIR_OP_BLOCK_BEGIN || op == SEMANTIC_LIR_OP_LOOP_BEGIN ||
        op == SEMANTIC_LIR_OP_IF_BEGIN ||
        op == SEMANTIC_LIR_OP_ELSE || op == SEMANTIC_LIR_OP_CONTROL_END ||
        op == SEMANTIC_LIR_OP_AGGREGATE_NEW || op == SEMANTIC_LIR_OP_AGGREGATE_COPY ||
        op == SEMANTIC_LIR_OP_ADDRESS || op == SEMANTIC_LIR_OP_FIELD_ADDRESS ||
        op == SEMANTIC_LIR_OP_INDEX_ADDRESS || op == SEMANTIC_LIR_OP_PLACE_LOAD ||
        op == SEMANTIC_LIR_OP_PLACE_STORE ||
        (op == SEMANTIC_LIR_OP_LOAD &&
         (core.flags & (SEMANTIC_LIR_FLAG_INDEXED | SEMANTIC_LIR_FLAG_FIELD)) != 0u) ||
        ((op == SEMANTIC_LIR_OP_BRANCH || op == SEMANTIC_LIR_OP_BRANCH_IF) &&
         (core.flags & SEMANTIC_LIR_FLAG_BRANCH_DEPTH_VALID) != 0u) ||
        op == SEMANTIC_LIR_OP_RETURN || op == SEMANTIC_LIR_OP_DROP ||
        op == SEMANTIC_LIR_OP_TRAP;
}

bool wasm_intrinsic_supported(uint intrinsic)
{
    return intrinsic == WASM_INTRINSIC_PRINT || intrinsic == WASM_INTRINSIC_ASSERT ||
        intrinsic == INTRINSIC_I32_ARRAY_DATA_PTR || intrinsic == INTRINSIC_I32_SLICE_DATA_PTR ||
        intrinsic == INTRINSIC_STRING_DATA_PTR || intrinsic == INTRINSIC_SLICE_STRIDE ||
        intrinsic_slice_from_raw_parts(intrinsic);
}

// ---- Row plans ----
// A plan lists one semantic row's Wasm instructions in order. Counting runs
// it to the end and reads the row total; scattering runs it again and keeps
// the instruction at its own target row. Both therefore agree by
// construction. A plan wraps every row: the function prologue before its
// first row, the epilogue after its last row and before each return.

// Marks rows the scalar lowering in scatter.slang still produces itself.
static const uint WASM_PLAN_LEGACY = 0xffffffffu;
// Rows of one constructor element (padded with zero-byte NOPs).
static const uint WASM_PLAN_ELEMENT_ROWS = 16u;

static uint wasm_plan_target;
static uint wasm_plan_index;
static uint wasm_plan_opcode;
static uint wasm_plan_immediate;
static uint wasm_plan_component;
static bool wasm_plan_unsupported;
// The row where the semantic row's own instructions begin (after a prologue).
static uint wasm_plan_body_start;

struct WasmPlanRow
{
    OptIrNodeCore core;
    OptIrNodeOperands operands;
    // The function's frame bytes; 0 when it has none.
    uint frame_bytes;
    // Byte offset of this row's slot (its word 0) from the frame base.
    uint slot;
    // Byte offset of the referenced home's word 0, or WASM_LIR_INVALID when
    // the address is a pointer value on the stack.
    uint home;
    // Header ADDRESS of a parameter: its declaration (the incoming local)
    // and its home's storage class and words (place_mark.slang).
    uint param_declaration;
    uint param_type;
    uint home_kind;
    uint home_words;
    // semantic_lir_layout_word_offset of the row.
    uint layout;
    // Words of the row named by operands.a.
    uint operand_words;
    // A fixed array argument passed as a slice: its descriptor's slot and
    // the array length, else WASM_LIR_INVALID.
    uint view_slot;
    uint view_length;
    // Checked type of the row named by operands.b (an index).
    uint index_type;
    uint value_op;
    uint legacy_rows;
    // The function's parameters (read by its first row's prologue).
    uint param_start;
    uint param_count;
    bool first;
    bool last;
    // A literal inside a type (the length in `f<[i32; 2]>()`): its value
    // row has no consumer, so a stack machine must not push it.
    bool type_literal;
    bool call_base;
    bool discarded;
    // A compound field store (`x.f += v`, `x.a.f += v`) whose receiver the
    // compound read already consumed: the store reloads the receiver as this
    // local plus receiver_offset bytes, else receiver is INVALID.
    uint receiver;
    uint receiver_offset;
};

void wasm_emit(uint opcode, uint immediate)
{
    if (wasm_plan_index == wasm_plan_target)
    {
        wasm_plan_opcode = opcode;
        wasm_plan_immediate = immediate;
        wasm_plan_component = WASM_LIR_INVALID;
    }
    wasm_plan_index += 1u;
}

// A local access of one component of a string pair.
void wasm_emit_pair_local(uint opcode, uint declaration, uint component)
{
    if (wasm_plan_index == wasm_plan_target)
    {
        wasm_plan_opcode = opcode;
        wasm_plan_immediate = declaration;
        wasm_plan_component = component;
    }
    wasm_plan_index += 1u;
}

void wasm_emit_legacy(uint rows)
{
    if (wasm_plan_target >= wasm_plan_index && wasm_plan_target - wasm_plan_index < rows)
    {
        wasm_plan_opcode = WASM_PLAN_LEGACY;
        wasm_plan_immediate = wasm_plan_target - wasm_plan_index;
        wasm_plan_component = WASM_LIR_INVALID;
    }
    wasm_plan_index += rows;
}

// Adds a (two's-complement) byte delta to the address on the stack.
void wasm_emit_offset(uint delta)
{
    if (delta == 0u) return;
    wasm_emit(WASM_LIR_OP_I32_CONST, delta);
    wasm_emit(WASM_LIR_OP_I32_ADD, 0u);
}

// Pushes frame base + offset.
void wasm_emit_frame(uint offset)
{
    wasm_emit(WASM_LIR_OP_GLOBAL_GET, WASM_STACK_POINTER);
    wasm_emit_offset(offset);
}

uint wasm_word_delta(uint words) { return 0u - words * WASM_WORD_BYTES; }

uint wasm_load_opcode(uint type_id)
{
    if (type_id == SCALAR_I64 || type_id == SCALAR_U64) return WASM_LIR_OP_I64_LOAD;
    if (type_id == SCALAR_F32) return WASM_LIR_OP_F32_LOAD;
    if (type_id == SCALAR_I8) return WASM_LIR_OP_I32_LOAD8_S;
    if (type_id == SCALAR_U8) return WASM_LIR_OP_I32_LOAD8_U;
    if (type_id == SCALAR_I16) return WASM_LIR_OP_I32_LOAD16_S;
    if (type_id == SCALAR_U16) return WASM_LIR_OP_I32_LOAD16_U;
    return WASM_LIR_OP_I32_LOAD;
}

uint wasm_store_opcode(uint type_id)
{
    if (type_id == SCALAR_I64 || type_id == SCALAR_U64) return WASM_LIR_OP_I64_STORE;
    if (type_id == SCALAR_F32) return WASM_LIR_OP_F32_STORE;
    if (type_id == SCALAR_I8 || type_id == SCALAR_U8) return WASM_LIR_OP_I32_STORE8;
    if (type_id == SCALAR_I16 || type_id == SCALAR_U16) return WASM_LIR_OP_I32_STORE16;
    return WASM_LIR_OP_I32_STORE;
}

uint wasm_value_temp(uint type_id)
{
    uint value_class = wasm_scalar_class(type_id);
    return value_class == WASM_CLASS_I64 ? WASM_SYNTHETIC_I64_TEMP
        : value_class == WASM_CLASS_F32 ? WASM_SYNTHETIC_F32_TEMP : WASM_SYNTHETIC_I32_TEMP;
}

// Copies `words` words from the value whose address is in `source` to the
// slot whose word 0 is at frame + `slot`.
void wasm_emit_copy_to_frame(uint slot, uint words, uint source)
{
    if (words == 0u) return;
    wasm_emit_frame(slot + wasm_word_delta(words - 1u));
    wasm_emit(WASM_LIR_OP_LOCAL_GET, source);
    wasm_emit_offset(wasm_word_delta(words - 1u));
    wasm_emit(WASM_LIR_OP_I32_CONST, words * WASM_WORD_BYTES);
    wasm_emit(WASM_LIR_OP_MEMORY_COPY, 0u);
}

// Copies `words` words from the value whose address is in `source` to the
// value whose word 0 is the address on the stack.
void wasm_emit_copy_to_address(uint words, uint source)
{
    if (words == 0u)
    {
        wasm_emit(WASM_LIR_OP_DROP, 0u);
        return;
    }
    wasm_emit_offset(wasm_word_delta(words - 1u));
    wasm_emit(WASM_LIR_OP_LOCAL_GET, source);
    wasm_emit_offset(wasm_word_delta(words - 1u));
    wasm_emit(WASM_LIR_OP_I32_CONST, words * WASM_WORD_BYTES);
    wasm_emit(WASM_LIR_OP_MEMORY_COPY, 0u);
}

// Stores the scalar in `temp` (or a string pair in the two string temps) at
// frame + `offset`.
void wasm_emit_store_frame(uint offset, uint type_id, uint temp)
{
    wasm_emit_frame(offset);
    wasm_emit(WASM_LIR_OP_LOCAL_GET, temp);
    wasm_emit(wasm_store_opcode(type_id), 0u);
}

void wasm_emit_bounds_trap()
{
    wasm_emit(WASM_LIR_OP_I32_GE_U, 0u);
    wasm_emit(WASM_LIR_OP_IF, 0u);
    wasm_emit(WASM_LIR_OP_UNREACHABLE, 0u);
    wasm_emit(WASM_LIR_OP_END, 0u);
}

// The address value of a slot-producing row: frame + slot.
void wasm_emit_slot(WasmPlanRow row)
{
    if (row.slot == WASM_LIR_INVALID) wasm_plan_unsupported = true;
    wasm_emit_frame(row.slot);
}

// Every array argument crosses a call as a slice descriptor (as on x86, an
// array and a slice share the pointer/length/stride call contract). A fixed
// array parameter keeps only the descriptor's data pointer: the address of
// the caller's array.
void wasm_emit_array_params(WasmPlanRow row, StructuredBuffer<SemanticLirParam> params,
                            StructuredBuffer<uint> param_layout)
{
    uint param_rows;
    uint stride;
    params.GetDimensions(param_rows, stride);
    uint layout_rows;
    param_layout.GetDimensions(layout_rows, stride);
    for (uint ordinal = 0u; ordinal < row.param_count; ordinal += 1u)
    {
        uint index = row.param_start + ordinal;
        if (index >= param_rows || 2u * index + 1u >= layout_rows) break;
        SemanticLirParam param = params[index];
        if ((param.value_metadata & SEMANTIC_LIR_VALUE_ARRAY_PAIR) == 0u ||
            param_layout[2u * index + 1u] == 0u)
            continue;
        wasm_emit(WASM_LIR_OP_LOCAL_GET, param.declaration_id);
        wasm_emit(WASM_LIR_OP_I32_LOAD, 0u);
        wasm_emit(WASM_LIR_OP_LOCAL_SET, param.declaration_id);
    }
}

void wasm_emit_prologue(uint frame_bytes)
{
    wasm_emit(WASM_LIR_OP_GLOBAL_GET, WASM_STACK_POINTER);
    wasm_emit(WASM_LIR_OP_I32_CONST, frame_bytes);
    wasm_emit(WASM_LIR_OP_I32_SUB, 0u);
    wasm_emit(WASM_LIR_OP_GLOBAL_SET, WASM_STACK_POINTER);
}

void wasm_emit_epilogue(uint frame_bytes)
{
    wasm_emit(WASM_LIR_OP_GLOBAL_GET, WASM_STACK_POINTER);
    wasm_emit(WASM_LIR_OP_I32_CONST, frame_bytes);
    wasm_emit(WASM_LIR_OP_I32_ADD, 0u);
    wasm_emit(WASM_LIR_OP_GLOBAL_SET, WASM_STACK_POINTER);
}

// A parameter's header ADDRESS copies the incoming value into its home.
void wasm_plan_param_home(WasmPlanRow row)
{
    uint slot = row.slot;
    uint declaration = row.param_declaration;
    if (row.home_kind == 1u)
    {
        wasm_emit_frame(slot);
        wasm_emit(WASM_LIR_OP_LOCAL_GET, declaration);
        wasm_emit(wasm_store_opcode(row.param_type), 0u);
    }
    else if (row.home_kind == 2u && row.home_words == 2u)
    {
        wasm_emit_frame(slot);
        wasm_emit_pair_local(WASM_LIR_OP_LOCAL_GET, declaration, 0u);
        wasm_emit(WASM_LIR_OP_I32_STORE, 0u);
        wasm_emit_frame(slot + wasm_word_delta(1u));
        wasm_emit_pair_local(WASM_LIR_OP_LOCAL_GET, declaration, 1u);
        wasm_emit(WASM_LIR_OP_I32_STORE, 0u);
    }
    else if (row.home_kind == 2u || row.home_kind == 3u)
        wasm_emit_copy_to_frame(slot, row.home_words, declaration);
    else wasm_plan_unsupported = true;
}

void wasm_plan_place_load(WasmPlanRow row)
{
    OptIrNodeCore core = row.core;
    bool home = row.home != WASM_LIR_INVALID;
    if (wasm_type_is_aggregate(core))
    {
        if (home) wasm_emit_frame(row.home);
        return;
    }
    if (core.type_id == TY_STRING)
    {
        if (home)
        {
            wasm_emit_frame(row.home);
            wasm_emit(WASM_LIR_OP_I32_LOAD, 0u);
            wasm_emit_frame(row.home + wasm_word_delta(1u));
            wasm_emit(WASM_LIR_OP_I32_LOAD, 0u);
            return;
        }
        wasm_emit(WASM_LIR_OP_LOCAL_SET, WASM_SYNTHETIC_I32_ADDRESS_TEMP);
        wasm_emit(WASM_LIR_OP_LOCAL_GET, WASM_SYNTHETIC_I32_ADDRESS_TEMP);
        wasm_emit(WASM_LIR_OP_I32_LOAD, 0u);
        wasm_emit(WASM_LIR_OP_LOCAL_GET, WASM_SYNTHETIC_I32_ADDRESS_TEMP);
        wasm_emit_offset(wasm_word_delta(1u));
        wasm_emit(WASM_LIR_OP_I32_LOAD, 0u);
        return;
    }
    if (home) wasm_emit_frame(row.home);
    wasm_emit(wasm_load_opcode(core.type_id), 0u);
}

// The stack holds the destination address (unless the destination is a
// frame home), then the value.
void wasm_plan_place_store(WasmPlanRow row)
{
    OptIrNodeCore core = row.core;
    bool home = row.home != WASM_LIR_INVALID;
    if (wasm_type_is_aggregate(core))
    {
        uint words = core.value_word_count;
        if (words == WASM_LIR_INVALID) { wasm_plan_unsupported = true; return; }
        wasm_emit(WASM_LIR_OP_LOCAL_SET, WASM_SYNTHETIC_I32_TEMP);
        if (home) wasm_emit_copy_to_frame(row.home, words, WASM_SYNTHETIC_I32_TEMP);
        else wasm_emit_copy_to_address(words, WASM_SYNTHETIC_I32_TEMP);
        return;
    }
    if (core.type_id == TY_STRING)
    {
        wasm_emit(WASM_LIR_OP_LOCAL_SET, WASM_SYNTHETIC_I32_INDEX_TEMP);
        wasm_emit(WASM_LIR_OP_LOCAL_SET, WASM_SYNTHETIC_I32_TEMP);
        if (home)
        {
            wasm_emit_store_frame(row.home, SCALAR_PTR, WASM_SYNTHETIC_I32_TEMP);
            wasm_emit_store_frame(row.home + wasm_word_delta(1u), SCALAR_PTR,
                                  WASM_SYNTHETIC_I32_INDEX_TEMP);
            return;
        }
        wasm_emit(WASM_LIR_OP_LOCAL_SET, WASM_SYNTHETIC_I32_ADDRESS_TEMP);
        wasm_emit(WASM_LIR_OP_LOCAL_GET, WASM_SYNTHETIC_I32_ADDRESS_TEMP);
        wasm_emit(WASM_LIR_OP_LOCAL_GET, WASM_SYNTHETIC_I32_TEMP);
        wasm_emit(WASM_LIR_OP_I32_STORE, 0u);
        wasm_emit(WASM_LIR_OP_LOCAL_GET, WASM_SYNTHETIC_I32_ADDRESS_TEMP);
        wasm_emit_offset(wasm_word_delta(1u));
        wasm_emit(WASM_LIR_OP_LOCAL_GET, WASM_SYNTHETIC_I32_INDEX_TEMP);
        wasm_emit(WASM_LIR_OP_I32_STORE, 0u);
        return;
    }
    uint temp = wasm_value_temp(core.type_id);
    wasm_emit(WASM_LIR_OP_LOCAL_SET, temp);
    if (home) wasm_emit_frame(row.home);
    wasm_emit(WASM_LIR_OP_LOCAL_GET, temp);
    wasm_emit(wasm_store_opcode(core.type_id), 0u);
}

void wasm_emit_receiver(WasmPlanRow row)
{
    if (row.receiver == WASM_LIR_INVALID) return;
    wasm_emit(WASM_LIR_OP_LOCAL_GET, row.receiver);
    wasm_emit_offset(row.receiver_offset);
}

// A field projection: the base address is on the stack (and the value
// above it for a store). The field's word offset is the shared layout's.
void wasm_plan_field(WasmPlanRow row)
{
    OptIrNodeCore core = row.core;
    uint op = opt_ir_op(core);
    if (row.layout == WASM_LIR_INVALID || row.layout > 0x0fffffffu)
    {
        wasm_plan_unsupported = true;
        return;
    }
    uint delta = wasm_word_delta(row.layout);
    bool aggregate = wasm_type_is_aggregate(core);
    if (op == SEMANTIC_LIR_OP_STORE)
    {
        if (aggregate)
        {
            uint words = core.value_word_count;
            if (words == WASM_LIR_INVALID) { wasm_plan_unsupported = true; return; }
            wasm_emit(WASM_LIR_OP_LOCAL_SET, WASM_SYNTHETIC_I32_TEMP);
            wasm_emit_receiver(row);
            wasm_emit_offset(delta);
            wasm_emit_copy_to_address(words, WASM_SYNTHETIC_I32_TEMP);
            return;
        }
        if (core.type_id == TY_STRING)
        {
            wasm_emit(WASM_LIR_OP_LOCAL_SET, WASM_SYNTHETIC_I32_INDEX_TEMP);
            wasm_emit(WASM_LIR_OP_LOCAL_SET, WASM_SYNTHETIC_I32_TEMP);
            wasm_emit_receiver(row);
            wasm_emit_offset(delta);
            wasm_emit(WASM_LIR_OP_LOCAL_SET, WASM_SYNTHETIC_I32_ADDRESS_TEMP);
            wasm_emit(WASM_LIR_OP_LOCAL_GET, WASM_SYNTHETIC_I32_ADDRESS_TEMP);
            wasm_emit(WASM_LIR_OP_LOCAL_GET, WASM_SYNTHETIC_I32_TEMP);
            wasm_emit(WASM_LIR_OP_I32_STORE, 0u);
            wasm_emit(WASM_LIR_OP_LOCAL_GET, WASM_SYNTHETIC_I32_ADDRESS_TEMP);
            wasm_emit_offset(wasm_word_delta(1u));
            wasm_emit(WASM_LIR_OP_LOCAL_GET, WASM_SYNTHETIC_I32_INDEX_TEMP);
            wasm_emit(WASM_LIR_OP_I32_STORE, 0u);
            return;
        }
        uint temp = wasm_value_temp(core.type_id);
        wasm_emit(WASM_LIR_OP_LOCAL_SET, temp);
        wasm_emit_receiver(row);
        wasm_emit_offset(delta);
        wasm_emit(WASM_LIR_OP_LOCAL_GET, temp);
        wasm_emit(wasm_store_opcode(core.type_id), 0u);
        return;
    }
    wasm_emit_offset(delta);
    if (op == SEMANTIC_LIR_OP_FIELD_ADDRESS || aggregate) return;
    if (core.type_id == TY_STRING)
    {
        wasm_emit(WASM_LIR_OP_LOCAL_SET, WASM_SYNTHETIC_I32_ADDRESS_TEMP);
        wasm_emit(WASM_LIR_OP_LOCAL_GET, WASM_SYNTHETIC_I32_ADDRESS_TEMP);
        wasm_emit(WASM_LIR_OP_I32_LOAD, 0u);
        wasm_emit(WASM_LIR_OP_LOCAL_GET, WASM_SYNTHETIC_I32_ADDRESS_TEMP);
        wasm_emit_offset(wasm_word_delta(1u));
        wasm_emit(WASM_LIR_OP_I32_LOAD, 0u);
        return;
    }
    wasm_emit(wasm_load_opcode(core.type_id), 0u);
}

// An element projection. The stack holds the base and the index (the index
// first when the base is a call scheduled after it), then a stored value.
// A fixed array's length is the row's layout column; a slice's base is its
// descriptor, whose length bounds the index and whose stride scales it.
void wasm_plan_subscript(WasmPlanRow row)
{
    OptIrNodeCore core = row.core;
    uint op = opt_ir_op(core);
    bool store = op == SEMANTIC_LIR_OP_STORE;
    bool aggregate = wasm_type_is_aggregate(core);
    uint element_words = aggregate ? core.value_word_count
        : core.type_id == TY_STRING ? 2u : 1u;
    if (element_words == WASM_LIR_INVALID || element_words > 0x0fffffffu ||
        row.layout == WASM_LIR_INVALID || (store && core.type_id == TY_STRING))
    {
        wasm_plan_unsupported = true;
        return;
    }
    uint value_temp = aggregate ? WASM_SYNTHETIC_I32_TEMP : wasm_value_temp(core.type_id);
    if (store) wasm_emit(WASM_LIR_OP_LOCAL_SET, value_temp);
    bool wide_index = wasm_scalar_class(row.index_type) == WASM_CLASS_I64;
    if (row.call_base) wasm_emit(WASM_LIR_OP_LOCAL_SET, WASM_SYNTHETIC_I32_ADDRESS_TEMP);
    if (wide_index) wasm_emit(WASM_LIR_OP_I32_WRAP_I64, 0u);
    wasm_emit(WASM_LIR_OP_LOCAL_SET, WASM_SYNTHETIC_I32_INDEX_TEMP);
    if (!row.call_base) wasm_emit(WASM_LIR_OP_LOCAL_SET, WASM_SYNTHETIC_I32_ADDRESS_TEMP);
    if (row.layout == SEMANTIC_LIR_ARRAY_LENGTH_RUNTIME)
    {
        wasm_emit(WASM_LIR_OP_LOCAL_GET, WASM_SYNTHETIC_I32_INDEX_TEMP);
        wasm_emit(WASM_LIR_OP_LOCAL_GET, WASM_SYNTHETIC_I32_ADDRESS_TEMP);
        wasm_emit_offset(wasm_word_delta(NATIVE_SLICE_LENGTH));
        wasm_emit(WASM_LIR_OP_I32_LOAD, 0u);
        wasm_emit_bounds_trap();
        wasm_emit(WASM_LIR_OP_LOCAL_GET, WASM_SYNTHETIC_I32_ADDRESS_TEMP);
        wasm_emit(WASM_LIR_OP_I32_LOAD, 0u);
        wasm_emit(WASM_LIR_OP_LOCAL_GET, WASM_SYNTHETIC_I32_INDEX_TEMP);
        wasm_emit(WASM_LIR_OP_LOCAL_GET, WASM_SYNTHETIC_I32_ADDRESS_TEMP);
        wasm_emit_offset(wasm_word_delta(NATIVE_SLICE_STRIDE));
        wasm_emit(WASM_LIR_OP_I32_LOAD, 0u);
    }
    else
    {
        wasm_emit(WASM_LIR_OP_LOCAL_GET, WASM_SYNTHETIC_I32_INDEX_TEMP);
        wasm_emit(WASM_LIR_OP_I32_CONST, row.layout);
        wasm_emit_bounds_trap();
        wasm_emit(WASM_LIR_OP_LOCAL_GET, WASM_SYNTHETIC_I32_ADDRESS_TEMP);
        wasm_emit(WASM_LIR_OP_LOCAL_GET, WASM_SYNTHETIC_I32_INDEX_TEMP);
        wasm_emit(WASM_LIR_OP_I32_CONST, wasm_word_delta(element_words));
    }
    wasm_emit(WASM_LIR_OP_I32_MUL, 0u);
    wasm_emit(WASM_LIR_OP_I32_ADD, 0u);
    if (op == SEMANTIC_LIR_OP_INDEX_ADDRESS) return;
    if (store)
    {
        if (aggregate) wasm_emit_copy_to_address(element_words, value_temp);
        else
        {
            wasm_emit(WASM_LIR_OP_LOCAL_GET, value_temp);
            wasm_emit(wasm_store_opcode(core.type_id), 0u);
        }
        return;
    }
    if (aggregate) return;
    if (core.type_id == TY_STRING)
    {
        wasm_emit(WASM_LIR_OP_LOCAL_SET, WASM_SYNTHETIC_I32_ADDRESS_TEMP);
        wasm_emit(WASM_LIR_OP_LOCAL_GET, WASM_SYNTHETIC_I32_ADDRESS_TEMP);
        wasm_emit(WASM_LIR_OP_I32_LOAD, 0u);
        wasm_emit(WASM_LIR_OP_LOCAL_GET, WASM_SYNTHETIC_I32_ADDRESS_TEMP);
        wasm_emit_offset(wasm_word_delta(1u));
        wasm_emit(WASM_LIR_OP_I32_LOAD, 0u);
        return;
    }
    wasm_emit(wasm_load_opcode(core.type_id), 0u);
}

// One constructor element, popped from the top of the stack into its words
// of the slot.
void wasm_plan_element(WasmPlanRow row, SemanticLirAggregateElement element,
                       uint source_words)
{
    uint value_type = element.value_metadata & SEMANTIC_LIR_VALUE_TYPE_MASK;
    uint offset = row.slot + wasm_word_delta(element.word_offset);
    if (element.word_offset == WASM_LIR_INVALID || element.word_count == WASM_LIR_INVALID)
    {
        wasm_plan_unsupported = true;
        return;
    }
    if (element.slice_array_length != WASM_LIR_INVALID)
    {
        // A fixed array initializing a slice field: store the view's
        // descriptor (address, length, stride).
        uint length = element.slice_array_length;
        uint stride = length == 0u || source_words == WASM_LIR_INVALID
            ? 0u : wasm_word_delta(source_words / length);
        wasm_emit(WASM_LIR_OP_LOCAL_SET, WASM_SYNTHETIC_I32_TEMP);
        wasm_emit_store_frame(offset, SCALAR_PTR, WASM_SYNTHETIC_I32_TEMP);
        wasm_emit_frame(offset + wasm_word_delta(NATIVE_SLICE_LENGTH));
        wasm_emit(WASM_LIR_OP_I32_CONST, length);
        wasm_emit(WASM_LIR_OP_I32_STORE, 0u);
        wasm_emit_frame(offset + wasm_word_delta(NATIVE_SLICE_STRIDE));
        wasm_emit(WASM_LIR_OP_I32_CONST, stride);
        wasm_emit(WASM_LIR_OP_I32_STORE, 0u);
        return;
    }
    if ((element.value_metadata & SEMANTIC_LIR_VALUE_STRING) != 0u || value_type == TY_STRING)
    {
        wasm_emit(WASM_LIR_OP_LOCAL_SET, WASM_SYNTHETIC_I32_INDEX_TEMP);
        wasm_emit(WASM_LIR_OP_LOCAL_SET, WASM_SYNTHETIC_I32_TEMP);
        wasm_emit_store_frame(offset, SCALAR_PTR, WASM_SYNTHETIC_I32_TEMP);
        wasm_emit_store_frame(offset + wasm_word_delta(1u), SCALAR_PTR,
                              WASM_SYNTHETIC_I32_INDEX_TEMP);
        return;
    }
    if ((element.value_metadata &
         (SEMANTIC_LIR_VALUE_AGGREGATE | SEMANTIC_LIR_VALUE_ARRAY_PAIR)) != 0u)
    {
        wasm_emit(WASM_LIR_OP_LOCAL_SET, WASM_SYNTHETIC_I32_TEMP);
        wasm_emit_copy_to_frame(offset, element.word_count, WASM_SYNTHETIC_I32_TEMP);
        return;
    }
    if (value_type == SCALAR_F64) wasm_plan_unsupported = true;
    uint temp = wasm_value_temp(value_type);
    wasm_emit(WASM_LIR_OP_LOCAL_SET, temp);
    wasm_emit_store_frame(offset, value_type, temp);
}

void wasm_plan_aggregate_new(WasmPlanRow row,
                             StructuredBuffer<SemanticLirAggregateElement> elements,
                             StructuredBuffer<OptIrNodeCore> cores)
{
    OptIrNodeCore core = row.core;
    OptIrNodeOperands operands = row.operands;
    uint words = core.value_word_count;
    if (words == WASM_LIR_INVALID) { wasm_plan_unsupported = true; return; }
    uint element_count;
    uint stride;
    elements.GetDimensions(element_count, stride);
    uint core_count;
    cores.GetDimensions(core_count, stride);
    // Elements arrive in order, so the last is on top: pop them in reverse.
    // Each element owns a fixed group of rows; only the group holding the
    // target row is planned.
    uint base = wasm_plan_index;
    uint group_rows = operands.b * WASM_PLAN_ELEMENT_ROWS;
    if (wasm_plan_target >= base && wasm_plan_target - base < group_rows)
    {
        uint group = (wasm_plan_target - base) / WASM_PLAN_ELEMENT_ROWS;
        uint element_index = operands.a + operands.b - 1u - group;
        wasm_plan_index = base + group * WASM_PLAN_ELEMENT_ROWS;
        if (element_index < element_count)
        {
            SemanticLirAggregateElement element = elements[element_index];
            uint source_words = element.value_instruction < core_count
                ? cores[element.value_instruction].value_word_count : WASM_LIR_INVALID;
            wasm_plan_element(row, element, source_words);
        }
        else wasm_plan_unsupported = true;
    }
    wasm_plan_index = base + group_rows;
    if (operands.c == SEMANTIC_LIR_AGGREGATE_ZERO && operands.b == 0u && words != 0u)
    {
        wasm_emit_frame(row.slot + wasm_word_delta(words - 1u));
        wasm_emit(WASM_LIR_OP_I32_CONST, 0u);
        wasm_emit(WASM_LIR_OP_I32_CONST, words * WASM_WORD_BYTES);
        wasm_emit(WASM_LIR_OP_MEMORY_FILL, 0u);
    }
    if (operands.c == SEMANTIC_LIR_AGGREGATE_REPEAT)
    {
        // memory.copy(words [filled, filled + length) <- words [0, length)).
        uint element_words = wasm_repeat_element_words(core, operands, elements);
        if (element_words == WASM_LIR_INVALID) wasm_plan_unsupported = true;
        uint steps = wasm_repeat_steps(element_words, words);
        for (uint step = 0u; step < steps; step += 1u)
        {
            uint filled;
            uint length;
            wasm_repeat_step(element_words, words, step, filled, length);
            wasm_emit_frame(row.slot + wasm_word_delta(filled + length - 1u));
            wasm_emit_frame(row.slot + wasm_word_delta(length - 1u));
            wasm_emit(WASM_LIR_OP_I32_CONST, length * WASM_WORD_BYTES);
            wasm_emit(WASM_LIR_OP_MEMORY_COPY, 0u);
        }
    }
    if ((operands.c & SEMANTIC_LIR_AGGREGATE_ENUM) != 0u)
    {
        wasm_emit_frame(row.slot);
        wasm_emit(WASM_LIR_OP_I32_CONST, operands.c & SEMANTIC_LIR_AGGREGATE_TAG_MASK);
        wasm_emit(WASM_LIR_OP_I32_STORE, 0u);
    }
    wasm_emit_slot(row);
}

void wasm_plan_aggregate_copy(WasmPlanRow row)
{
    OptIrNodeCore core = row.core;
    wasm_emit(WASM_LIR_OP_LOCAL_SET, WASM_SYNTHETIC_I32_TEMP);
    bool view = (core.flags & (SEMANTIC_LIR_FLAG_ARRAY_PAIR | SEMANTIC_LIR_FLAG_PLACE_VIEW)) ==
        (SEMANTIC_LIR_FLAG_ARRAY_PAIR | SEMANTIC_LIR_FLAG_PLACE_VIEW);
    if (view)
    {
        // An array-to-slice view: the array's address, its static length
        // (the layout column) and its element stride in the native layout.
        uint length = row.layout;
        if (length == WASM_LIR_INVALID || row.operand_words == WASM_LIR_INVALID)
            wasm_plan_unsupported = true;
        uint stride = length == 0u || length == WASM_LIR_INVALID
            ? 0u : wasm_word_delta(row.operand_words / length);
        wasm_emit_store_frame(row.slot, SCALAR_PTR, WASM_SYNTHETIC_I32_TEMP);
        wasm_emit_frame(row.slot + wasm_word_delta(NATIVE_SLICE_LENGTH));
        wasm_emit(WASM_LIR_OP_I32_CONST, length);
        wasm_emit(WASM_LIR_OP_I32_STORE, 0u);
        wasm_emit_frame(row.slot + wasm_word_delta(NATIVE_SLICE_STRIDE));
        wasm_emit(WASM_LIR_OP_I32_CONST, stride);
        wasm_emit(WASM_LIR_OP_I32_STORE, 0u);
    }
    else
    {
        if (core.value_word_count == WASM_LIR_INVALID) wasm_plan_unsupported = true;
        wasm_emit_copy_to_frame(row.slot, core.value_word_count, WASM_SYNTHETIC_I32_TEMP);
    }
    wasm_emit_slot(row);
}

// Raw parts: (data, length) on the stack become a descriptor in the slot,
// with the convention's stride from the shared layout column.
void wasm_plan_raw_slice(WasmPlanRow row)
{
    if (row.layout == WASM_LIR_INVALID) wasm_plan_unsupported = true;
    wasm_emit(WASM_LIR_OP_LOCAL_SET, WASM_SYNTHETIC_I32_INDEX_TEMP);
    wasm_emit(WASM_LIR_OP_LOCAL_SET, WASM_SYNTHETIC_I32_TEMP);
    wasm_emit_store_frame(row.slot, SCALAR_PTR, WASM_SYNTHETIC_I32_TEMP);
    wasm_emit_store_frame(row.slot + wasm_word_delta(NATIVE_SLICE_LENGTH), SCALAR_PTR,
                          WASM_SYNTHETIC_I32_INDEX_TEMP);
    wasm_emit_frame(row.slot + wasm_word_delta(NATIVE_SLICE_STRIDE));
    wasm_emit(WASM_LIR_OP_I32_CONST, row.layout);
    wasm_emit(WASM_LIR_OP_I32_STORE, 0u);
    wasm_emit_slot(row);
}

// The array's address on the stack becomes the address of its view.
void wasm_plan_argument_view(WasmPlanRow row)
{
    uint length = row.view_length;
    uint words = row.core.value_word_count;
    uint stride = length == 0u || words == WASM_LIR_INVALID ? 0u : wasm_word_delta(words / length);
    uint slot = row.view_slot;
    wasm_emit(WASM_LIR_OP_LOCAL_SET, WASM_SYNTHETIC_I32_TEMP);
    wasm_emit_store_frame(slot, SCALAR_PTR, WASM_SYNTHETIC_I32_TEMP);
    wasm_emit_frame(slot + wasm_word_delta(NATIVE_SLICE_LENGTH));
    wasm_emit(WASM_LIR_OP_I32_CONST, length);
    wasm_emit(WASM_LIR_OP_I32_STORE, 0u);
    wasm_emit_frame(slot + wasm_word_delta(NATIVE_SLICE_STRIDE));
    wasm_emit(WASM_LIR_OP_I32_CONST, stride);
    wasm_emit(WASM_LIR_OP_I32_STORE, 0u);
    wasm_emit_frame(slot);
}

bool wasm_plan_index_op(OptIrNodeCore core)
{
    uint op = opt_ir_op(core);
    return op == SEMANTIC_LIR_OP_INDEX_ADDRESS ||
        ((op == SEMANTIC_LIR_OP_LOAD || op == SEMANTIC_LIR_OP_STORE) &&
         (core.flags & SEMANTIC_LIR_FLAG_INDEXED) != 0u);
}

bool wasm_plan_field_op(OptIrNodeCore core)
{
    uint op = opt_ir_op(core);
    return op == SEMANTIC_LIR_OP_FIELD_ADDRESS ||
        ((op == SEMANTIC_LIR_OP_LOAD || op == SEMANTIC_LIR_OP_STORE) &&
         (core.flags & SEMANTIC_LIR_FLAG_FIELD) != 0u);
}

void wasm_plan_body(WasmPlanRow row,
                    StructuredBuffer<SemanticLirAggregateElement> elements,
                    StructuredBuffer<OptIrNodeCore> cores)
{
    OptIrNodeCore core = row.core;
    OptIrNodeOperands operands = row.operands;
    uint op = opt_ir_op(core);
    if (row.type_literal) return;
    if (op == SEMANTIC_LIR_OP_ADDRESS)
    {
        // A header row owns its home (a parameter's is filled on entry);
        // any other ADDRESS borrows a declaration's home.
        if (row.slot != WASM_LIR_INVALID)
        {
            if (row.param_declaration != WASM_LIR_INVALID) wasm_plan_param_home(row);
            return;
        }
        if (row.home == WASM_LIR_INVALID) { wasm_plan_unsupported = true; return; }
        wasm_emit_frame(row.home);
        return;
    }
    if (op == SEMANTIC_LIR_OP_PLACE_LOAD) { wasm_plan_place_load(row); return; }
    if (op == SEMANTIC_LIR_OP_PLACE_STORE) { wasm_plan_place_store(row); return; }
    if (wasm_plan_field_op(core)) { wasm_plan_field(row); return; }
    if (wasm_plan_index_op(core)) { wasm_plan_subscript(row); return; }
    if (op == SEMANTIC_LIR_OP_AGGREGATE_NEW)
    {
        wasm_plan_aggregate_new(row, elements, cores);
        return;
    }
    if (op == SEMANTIC_LIR_OP_AGGREGATE_COPY) { wasm_plan_aggregate_copy(row); return; }
    if (wasm_set_copies_aggregate(core, row.value_op))
    {
        wasm_emit(WASM_LIR_OP_LOCAL_SET, WASM_SYNTHETIC_I32_TEMP);
        wasm_emit_copy_to_frame(row.slot, core.value_word_count, WASM_SYNTHETIC_I32_TEMP);
        wasm_emit_slot(row);
        wasm_emit(WASM_LIR_OP_LOCAL_SET, operands.a);
        return;
    }
    if ((op == SEMANTIC_LIR_OP_CALL || op == SEMANTIC_LIR_OP_CALL_SYMBOL) &&
        !row.discarded && wasm_inline_aggregate(core))
    {
        // The callee's frame is released on return: copy the result into
        // this row's slot before anything else touches the stack.
        wasm_emit_legacy(1u);
        wasm_emit(WASM_LIR_OP_LOCAL_SET, WASM_SYNTHETIC_I32_TEMP);
        wasm_emit_copy_to_frame(row.slot, core.value_word_count, WASM_SYNTHETIC_I32_TEMP);
        wasm_emit_slot(row);
        return;
    }
    if (op == SEMANTIC_LIR_OP_CALL_INTRINSIC)
    {
        if (intrinsic_slice_from_raw_parts(operands.a)) { wasm_plan_raw_slice(row); return; }
        if (operands.a == INTRINSIC_SLICE_STRIDE)
        {
            wasm_emit_offset(wasm_word_delta(NATIVE_SLICE_STRIDE));
            wasm_emit(WASM_LIR_OP_I32_LOAD, 0u);
            return;
        }
        if (operands.a == INTRINSIC_I32_SLICE_DATA_PTR)
        {
            wasm_emit(WASM_LIR_OP_I32_LOAD, 0u);
            return;
        }
        // A string's data pointer is its first ABI value.
        if (operands.a == INTRINSIC_STRING_DATA_PTR)
        {
            wasm_emit(WASM_LIR_OP_DROP, 0u);
            return;
        }
        // An array's address is its element 0.
        if (operands.a == INTRINSIC_I32_ARRAY_DATA_PTR)
        {
            wasm_emit(WASM_LIR_OP_NOP, 0u);
            return;
        }
    }
    if (op == SEMANTIC_LIR_OP_RETURN)
    {
        if (row.frame_bytes != 0u) wasm_emit_epilogue(row.frame_bytes);
        wasm_emit(WASM_LIR_OP_RETURN, 0u);
        return;
    }
    wasm_emit_legacy(row.legacy_rows);
}

// Runs a row's plan. Returns its row count; for target < count the
// instruction is in wasm_plan_opcode / wasm_plan_immediate (WASM_PLAN_LEGACY
// selects the scalar lowering's row wasm_plan_immediate).
uint wasm_plan_rows(WasmPlanRow row, uint target,
                    StructuredBuffer<SemanticLirAggregateElement> elements,
                    StructuredBuffer<OptIrNodeCore> cores,
                    StructuredBuffer<SemanticLirParam> params,
                    StructuredBuffer<uint> param_layout)
{
    wasm_plan_target = target;
    wasm_plan_index = 0u;
    wasm_plan_opcode = WASM_LIR_OP_NOP;
    wasm_plan_immediate = 0u;
    wasm_plan_component = WASM_LIR_INVALID;
    wasm_plan_unsupported = false;
    bool framed = row.frame_bytes != 0u;
    if (framed && row.first) wasm_emit_prologue(row.frame_bytes);
    if (row.first) wasm_emit_array_params(row, params, param_layout);
    wasm_plan_body_start = wasm_plan_index;
    wasm_plan_body(row, elements, cores);
    if (row.view_length != WASM_LIR_INVALID) wasm_plan_argument_view(row);
    if (framed && row.last && opt_ir_op(row.core) != SEMANTIC_LIR_OP_RETURN)
        wasm_emit_epilogue(row.frame_bytes);
    return wasm_plan_index;
}

// The byte offset of a semantic row's slot from its function's frame base.
uint wasm_slot_offset(uint semantic_row, uint frame_start, StructuredBuffer<uint> frame_slots,
                      uint component = 0u)
{
    uint slots;
    uint stride;
    frame_slots.GetDimensions(slots, stride);
    if (semantic_row >= slots / WASM_FRAME_SLOT_STRIDE) return WASM_LIR_INVALID;
    uint word = frame_slots[WASM_FRAME_SLOT_STRIDE * semantic_row + component];
    return word == WASM_LIR_INVALID || word < frame_start
        ? WASM_LIR_INVALID : (word - frame_start) * WASM_WORD_BYTES;
}

uint wasm_function_of(uint scheduled_row, StructuredBuffer<uint> order,
                      StructuredBuffer<uint> source_hir, StructuredBuffer<uint> function_ids)
{
    return function_ids[source_hir[order[scheduled_row]]];
}

// Everything a row's plan reads, gathered identically for counting and
// scattering.
WasmPlanRow wasm_plan_row_at(uint scheduled_row, uint count,
                             StructuredBuffer<SemanticLirFunction> functions,
                             StructuredBuffer<uint> order,
                             StructuredBuffer<OptIrNodeCore> cores,
                             StructuredBuffer<OptIrNodeOperands> row_operands,
                             StructuredBuffer<uint> source_hir,
                             StructuredBuffer<uint> function_ids,
                             StructuredBuffer<HirCore> hir_core,
                             StructuredBuffer<uint> layout,
                             StructuredBuffer<uint4> storage,
                             StructuredBuffer<uint> place_address,
                             StructuredBuffer<uint> frame_slots,
                             StructuredBuffer<uint> frame_bounds)
{
    uint semantic_row = order[scheduled_row];
    WasmPlanRow row;
    row.core = cores[semantic_row];
    row.operands = row_operands[semantic_row];
    OptIrNodeCore core = row.core;
    OptIrNodeOperands operands = row.operands;
    uint op = opt_ir_op(core);
    uint function_id = wasm_function_of(scheduled_row, order, source_hir, function_ids);
    uint bound_count;
    uint stride;
    frame_bounds.GetDimensions(bound_count, stride);
    bool framed_function = function_id != WASM_LIR_INVALID && 2u * function_id + 1u < bound_count;
    uint frame_start = framed_function ? frame_bounds[2u * function_id] : 0u;
    uint frame_end = framed_function ? frame_bounds[2u * function_id + 1u] : 0u;
    uint frame_words = frame_end > frame_start ? frame_end - frame_start : 0u;
    row.frame_bytes = ((frame_words * WASM_WORD_BYTES) + 15u) & ~15u;
    row.first = scheduled_row == 0u ||
        wasm_function_of(scheduled_row - 1u, order, source_hir, function_ids) != function_id;
    row.last = scheduled_row + 1u >= count ||
        wasm_function_of(scheduled_row + 1u, order, source_hir, function_ids) != function_id;
    row.slot = wasm_slot_offset(semantic_row, frame_start, frame_slots);
    uint function_rows;
    functions.GetDimensions(function_rows, stride);
    row.param_start = 0u;
    row.param_count = 0u;
    if (row.first && function_id < function_rows)
    {
        row.param_start = functions[function_id].param_start;
        row.param_count = functions[function_id].param_count;
    }
    uint token_count;
    storage.GetDimensions(token_count, stride);
    row.home = WASM_LIR_INVALID;
    if ((op == SEMANTIC_LIR_OP_PLACE_LOAD || op == SEMANTIC_LIR_OP_PLACE_STORE) &&
        wasm_home_row(operands.a, cores, source_hir, hir_core))
        row.home = wasm_slot_offset(operands.a, frame_start, frame_slots);
    if (op == SEMANTIC_LIR_OP_ADDRESS && row.slot == WASM_LIR_INVALID && operands.a < token_count)
        row.home = wasm_slot_offset(place_address[operands.a], frame_start, frame_slots);
    row.param_declaration = WASM_LIR_INVALID;
    row.param_type = WASM_LIR_INVALID;
    row.home_kind = 0u;
    row.home_words = 0u;
    if (op == SEMANTIC_LIR_OP_ADDRESS && row.slot != WASM_LIR_INVALID)
    {
        row.param_type = frame_slots[WASM_FRAME_SLOT_STRIDE * semantic_row + 1u];
        if (row.param_type != WASM_LIR_INVALID) row.param_declaration = operands.a;
        uint4 home = operands.a < token_count ? storage[operands.a] : uint4(0u, 0u, 0u, 0u);
        row.home_kind = home.x;
        row.home_words = home.y;
    }
    row.view_slot = wasm_slot_offset(semantic_row, frame_start, frame_slots, 2u);
    row.view_length = row.view_slot == WASM_LIR_INVALID
        ? WASM_LIR_INVALID : frame_slots[WASM_FRAME_SLOT_STRIDE * semantic_row + 3u];
    row.layout = layout[semantic_row];
    row.operand_words = operands.a < count ? cores[operands.a].value_word_count : WASM_LIR_INVALID;
    row.index_type = operands.b < count ? cores[operands.b].type_id : SCALAR_I32;
    row.value_op = operands.b < count ? opt_ir_op(cores[operands.b]) : SEMANTIC_LIR_OP_INVALID;
    uint previous_row = scheduled_row > 0u ? order[scheduled_row - 1u] : WASM_LIR_INVALID;
    bool indexed = (core.flags & SEMANTIC_LIR_FLAG_INDEXED) != 0u;
    row.call_base = ((op == SEMANTIC_LIR_OP_STORE && indexed) ||
                     ((op == SEMANTIC_LIR_OP_LOAD && indexed) ||
                      op == SEMANTIC_LIR_OP_INDEX_ADDRESS) && previous_row == operands.a) &&
        operands.a < count &&
        (opt_ir_op(cores[operands.a]) == SEMANTIC_LIR_OP_CALL ||
         opt_ir_op(cores[operands.a]) == SEMANTIC_LIR_OP_CALL_SYMBOL);
    uint discarded_values = wasm_discarded_result_values(core,
        wasm_statement_call(hir_core, source_hir[semantic_row]));
    row.discarded = discarded_values != 0u;
    row.receiver = WASM_LIR_INVALID;
    row.receiver_offset = 0u;
    uint compound_read = operands.c < count ? row_operands[operands.c].a : WASM_LIR_INVALID;
    if (op == SEMANTIC_LIR_OP_STORE && (core.flags & SEMANTIC_LIR_FLAG_FIELD) != 0u &&
        compound_read < count && opt_ir_op(cores[compound_read]) == SEMANTIC_LIR_OP_LOAD &&
        row_operands[compound_read].a == operands.a)
    {
        // Walk the receiver's aggregate field projections to its local.
        uint receiver = operands.a;
        uint offset = 0u;
        for (uint step = 0u; step < 64u && receiver < count; step += 1u)
        {
            OptIrNodeCore link = cores[receiver];
            if (opt_ir_op(link) == SEMANTIC_LIR_OP_VALUE_GET)
            {
                row.receiver = row_operands[receiver].a;
                row.receiver_offset = offset;
                break;
            }
            if (opt_ir_op(link) != SEMANTIC_LIR_OP_LOAD ||
                (link.flags & SEMANTIC_LIR_FLAG_FIELD) == 0u ||
                !wasm_type_is_aggregate(link) || layout[receiver] > 0x0fffffffu)
                break;
            offset += wasm_word_delta(layout[receiver]);
            receiver = row_operands[receiver].a;
        }
    }
    uint hir_count;
    hir_core.GetDimensions(hir_count, stride);
    uint node = source_hir[semantic_row];
    uint parent = node < hir_count ? hir_core[node].parent : WASM_LIR_INVALID;
    row.type_literal = (op == SEMANTIC_LIR_OP_CONST_I32 || op == SEMANTIC_LIR_OP_CONST_I64) &&
        parent < hir_count && hir_core[parent].kind == WASM_HIR_TYPE;
    bool reload_short_circuit = previous_row < count &&
        wasm_reloads_short_circuit(core, operands, cores[previous_row], row_operands[previous_row]);
    uint value_type = operands.b < count ? cores[operands.b].type_id : core.type_id;
    row.legacy_rows = wasm_lir_count(core, operands, discarded_values, reload_short_circuit,
        value_type,
        wasm_exhaustion_reload(core, operands, cores, row_operands, count) != WASM_LIR_INVALID);
    return row;
}

// A fixed array passed where the callee takes a slice crosses the call as a
// view: a descriptor of the array's address, static length and element
// stride, built in the argument row's frame. Returns the length, else
// WASM_LIR_INVALID.
uint wasm_argument_view_length(SemanticLirCallArg argument, OptIrNodeCore value,
                               StructuredBuffer<OptIrNodeCore> cores, uint count)
{
    // Intrinsics and host services take their operands as they are.
    uint call_op = argument.call_instruction < count
        ? opt_ir_op(cores[argument.call_instruction]) : SEMANTIC_LIR_OP_INVALID;
    if ((call_op != SEMANTIC_LIR_OP_CALL && call_op != SEMANTIC_LIR_OP_CALL_SYMBOL) ||
        (argument.value_metadata & SEMANTIC_LIR_VALUE_ARRAY_PAIR) == 0u ||
        (value.flags & SEMANTIC_LIR_FLAG_ARRAY_PAIR) != 0u ||
        opt_ir_op(value) == SEMANTIC_LIR_OP_CALL_INTRINSIC ||
        !wasm_inline_aggregate(value) ||
        argument.array_length == WASM_LIR_INVALID ||
        argument.array_length == SEMANTIC_LIR_ARRAY_LENGTH_RUNTIME)
        return WASM_LIR_INVALID;
    return argument.array_length;
}
