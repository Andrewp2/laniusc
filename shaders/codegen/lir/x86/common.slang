import primitive_types;
import native_value_layout;
import codegen.lowering_ir;
import codegen.optimization_ir;

bool x86_semantic_type_is_aggregate(OptIrNodeCore core)
{
    // TYPE_REF_SCALAR means a fully concrete type reference, not necessarily
    // a scalar machine value: monomorphic arrays/structs/enums retain their
    // canonical aggregate type code in the payload. Instantiated generic
    // aggregates instead carry TYPE_REF_INSTANCE. Keep the invalid-reference
    // fallback only for partially projected producers that still have a
    // checked concrete type code.
    if (core.type_id == SEMANTIC_LIR_TY_POINTER) return false;
    uint type_ref_tag = opt_ir_type_ref_tag(core);
    return type_ref_tag == SEMANTIC_TYPE_REF_INSTANCE ||
        (type_ref_tag == SEMANTIC_TYPE_REF_SCALAR &&
         core.type_ref_payload >= 128u) ||
        (type_ref_tag == SEMANTIC_TYPE_REF_INVALID && core.type_id >= 128u);
}

uint x86_imported_call_result_words(OptIrNodeCore core)
{
    // A scalar imported call can inherit the width of a containing aggregate
    // in value_word_count. Only its checked result type may authorize an
    // aggregate result slot and the hidden sret ABI argument.
    if (!x86_semantic_type_is_aggregate(core) &&
        scalar_is_known(core.type_id))
        return 0u;
    return core.value_word_count;
}

// CALL_SYMBOL has no spare operand: a/b/c identify the imported symbol.
// Its local ordinal carries the result width and aligned outgoing stack
// word count. Scatter rejects either count above 65535 before packing.
uint x86_symbol_call_layout(uint result_words, uint stack_words)
{
    return (stack_words << 16u) | result_words;
}

uint x86_symbol_call_result_words(uint layout)
{
    return layout & 0xffffu;
}

uint x86_symbol_call_stack_bytes(uint layout)
{
    return (layout >> 16u) * 8u;
}

uint x86_aggregate_value_word_count(OptIrNodeCore core,
                                    OptIrNodeOperands operands)
{
    uint op = opt_ir_op(core);
    if (op == SEMANTIC_LIR_OP_CALL_SYMBOL)
        return x86_imported_call_result_words(core);
    if (op == SEMANTIC_LIR_OP_AGGREGATE_NEW)
        return max(core.value_word_count, operands.b);
    // Intrinsics do not have a SemanticLirFunction row from which the x86
    // lowering can recover an aggregate result width. Keep their value-shape
    // contract here so every aggregate consumer (counting, scattering, local
    // copies, and returns) sees the same three-word slice descriptor.
    if (op == SEMANTIC_LIR_OP_CALL_INTRINSIC &&
        intrinsic_slice_from_raw_parts(operands.a))
        return NATIVE_SLICE_WORDS;
    return core.value_word_count;
}

bool x86_direct_array_pair(OptIrNodeCore core)
{
    return (opt_ir_op(core) == SEMANTIC_LIR_OP_VALUE_GET ||
            opt_ir_op(core) == SEMANTIC_LIR_OP_PLACE_LOAD) &&
        (core.flags & SEMANTIC_LIR_FLAG_ARRAY_PAIR) != 0u;
}

static const uint X86_LIR_TY_FLOAT = 5u;
static const uint X86_CONSTANT_DIVISOR_NONE = 0u;
static const uint X86_CONSTANT_DIVISOR_POWER_OF_TWO = 1u;
static const uint X86_CONSTANT_DIVISOR_SIGNED = 2u;

bool x86_scalar_float(uint metadata)
{
    // Nominal aggregate type IDs can have the same low byte as the scalar
    // float code. Their values are addresses, not values in an XMM register.
    uint non_scalar = X86_LIR_METADATA_AGGREGATE |
        X86_LIR_METADATA_WIDE | X86_LIR_METADATA_STRING_PAIR |
        X86_LIR_METADATA_ARRAY_PAIR | X86_LIR_METADATA_PACKED_I32_ARRAY;
    return (metadata & non_scalar) == 0u &&
        scalar_is_float(metadata & 0xffu);
}

bool x86_scalar_f64(uint metadata)
{
    return x86_scalar_float(metadata) && (metadata & 0xffu) == SCALAR_F64;
}

bool x86_scalar_immediate_type(uint type_id)
{
    return type_id == 1u || type_id == 2u || type_id == 3u ||
        type_id == 4u || type_id == 6u;
}

bool x86_declaration_needs_home(X86DeclarationAnalysis analysis,
                                uint definition_live)
{
    if (analysis.definition == X86_DECLARATION_MULTIPLE_DEFINITIONS)
        return true;
    if (analysis.definition == X86_LOCATION_INVALID)
        return analysis.read_count != 0u;
    return definition_live != 0u;
}

uint x86_caller_declaration_register(uint ordinal)
{
    // Preserve the fifth and sixth SysV integer arguments in their incoming
    // R8/R9 registers. RDX/RCX remain fixed emitter scratch registers for now;
    // declarations two and three use the otherwise-free R10/R11 lanes.
    static const uint registers[6] = {7u, 6u, 10u, 11u, 8u, 9u};
    return registers[min(ordinal, 5u)];
}

uint x86_abi_argument_register(uint ordinal)
{
    static const uint registers[6] = {7u, 6u, 2u, 1u, 8u, 9u};
    return registers[min(ordinal, 5u)];
}

uint x86_parameter_abi_ordinal(SemanticLirFunction function, uint ordinal)
{
    return ordinal + (function.result_word_count > 2u ? 1u : 0u);
}

bool x86_integer_immediate_operation(uint semantic_op, uint type_id,
                                     uint immediate)
{
    if (!x86_scalar_immediate_type(type_id)) return false;
    if (semantic_op == SEMANTIC_LIR_OP_SHIFT_LEFT ||
        semantic_op == SEMANTIC_LIR_OP_SHIFT_RIGHT)
        return immediate <= 31u;
    return semantic_op == SEMANTIC_LIR_OP_ADD ||
        semantic_op == SEMANTIC_LIR_OP_SUB ||
        semantic_op == SEMANTIC_LIR_OP_MUL ||
        semantic_op == SEMANTIC_LIR_OP_BIT_AND ||
        semantic_op == SEMANTIC_LIR_OP_BIT_OR ||
        semantic_op == SEMANTIC_LIR_OP_BIT_XOR ||
        semantic_op == SEMANTIC_LIR_OP_LOGICAL_AND ||
        semantic_op == SEMANTIC_LIR_OP_LOGICAL_OR ||
        semantic_op == SEMANTIC_LIR_OP_COMPARE;
}

bool x86_integer_immediate_commutative(uint semantic_op)
{
    return semantic_op == SEMANTIC_LIR_OP_ADD ||
        semantic_op == SEMANTIC_LIR_OP_MUL ||
        semantic_op == SEMANTIC_LIR_OP_BIT_AND ||
        semantic_op == SEMANTIC_LIR_OP_BIT_OR ||
        semantic_op == SEMANTIC_LIR_OP_BIT_XOR ||
        semantic_op == SEMANTIC_LIR_OP_LOGICAL_AND ||
        semantic_op == SEMANTIC_LIR_OP_LOGICAL_OR;
}

uint x86_swapped_compare_predicate(uint predicate)
{
    if (predicate == 2u) return 3u;
    if (predicate == 3u) return 2u;
    if (predicate == 4u) return 5u;
    if (predicate == 5u) return 4u;
    return predicate;
}

bool x86_fold_integer_binary(uint semantic_op, uint type_id, uint predicate,
                             uint left, uint right, out uint value)
{
    value = 0u;
    if (!x86_scalar_immediate_type(type_id)) return false;
    bool is_unsigned = type_id == 4u || type_id == 6u;
    if (semantic_op == SEMANTIC_LIR_OP_ADD) value = left + right;
    else if (semantic_op == SEMANTIC_LIR_OP_SUB) value = left - right;
    else if (semantic_op == SEMANTIC_LIR_OP_MUL) value = left * right;
    else if (semantic_op == SEMANTIC_LIR_OP_DIV)
    {
        if (right == 0u || (!is_unsigned && left == 0x80000000u &&
                            right == 0xffffffffu))
            return false;
        value = is_unsigned ? left / right : uint(int(left) / int(right));
    }
    else if (semantic_op == SEMANTIC_LIR_OP_REM)
    {
        if (right == 0u || (!is_unsigned && left == 0x80000000u &&
                            right == 0xffffffffu))
            return false;
        if (is_unsigned) value = left % right;
        else
        {
            // Define signed remainder from the already-required truncating
            // quotient. This matches x86/C semantics even on shader compilers
            // whose constant `%` handling chooses modulo for negative values.
            int signed_left = int(left);
            int signed_right = int(right);
            int quotient = signed_left / signed_right;
            value = uint(signed_left - quotient * signed_right);
        }
    }
    else if (semantic_op == SEMANTIC_LIR_OP_BIT_AND) value = left & right;
    else if (semantic_op == SEMANTIC_LIR_OP_BIT_OR) value = left | right;
    else if (semantic_op == SEMANTIC_LIR_OP_BIT_XOR) value = left ^ right;
    else if (semantic_op == SEMANTIC_LIR_OP_SHIFT_LEFT)
    {
        if (right > 31u) return false;
        value = left << right;
    }
    else if (semantic_op == SEMANTIC_LIR_OP_SHIFT_RIGHT)
    {
        if (right > 31u) return false;
        value = is_unsigned ? left >> right : uint(int(left) >> right);
    }
    else if (semantic_op == SEMANTIC_LIR_OP_LOGICAL_AND)
        value = left != 0u && right != 0u ? 1u : 0u;
    else if (semantic_op == SEMANTIC_LIR_OP_LOGICAL_OR)
        value = left != 0u || right != 0u ? 1u : 0u;
    else if (semantic_op == SEMANTIC_LIR_OP_COMPARE)
    {
        if (predicate == 0u) value = left == right ? 1u : 0u;
        else if (predicate == 1u) value = left != right ? 1u : 0u;
        else if (is_unsigned)
            value = predicate == 2u ? (left < right ? 1u : 0u) :
                predicate == 3u ? (left > right ? 1u : 0u) :
                predicate == 4u ? (left <= right ? 1u : 0u) :
                (left >= right ? 1u : 0u);
        else
            value = predicate == 2u ? (int(left) < int(right) ? 1u : 0u) :
                predicate == 3u ? (int(left) > int(right) ? 1u : 0u) :
                predicate == 4u ? (int(left) <= int(right) ? 1u : 0u) :
                (int(left) >= int(right) ? 1u : 0u);
    }
    else return false;
    return true;
}

bool x86_fold_integer_unary(uint semantic_op, uint type_id, uint input,
                            out uint value)
{
    value = 0u;
    if (!x86_scalar_immediate_type(type_id)) return false;
    if (semantic_op == SEMANTIC_LIR_OP_NEGATE)
        value = 0u - input;
    else if (semantic_op == SEMANTIC_LIR_OP_LOGICAL_NOT)
        value = input == 0u ? 1u : 0u;
    else return false;
    return true;
}

uint x86_constant_divisor_kind(uint semantic_op, uint type_id, uint divisor)
{
    if ((semantic_op != SEMANTIC_LIR_OP_DIV &&
         semantic_op != SEMANTIC_LIR_OP_REM) || divisor == 0u)
        return X86_CONSTANT_DIVISOR_NONE;
    if (!x86_scalar_immediate_type(type_id)) return X86_CONSTANT_DIVISOR_NONE;
    bool power_of_two = (divisor & (divisor - 1u)) == 0u;
    bool is_unsigned = type_id == 4u || type_id == 6u;
    if (power_of_two && (is_unsigned || int(divisor) > 0))
        return X86_CONSTANT_DIVISOR_POWER_OF_TWO;
    if (!power_of_two && type_id == 3u && int(divisor) > 1)
        return X86_CONSTANT_DIVISOR_SIGNED;
    return X86_CONSTANT_DIVISOR_NONE;
}

uint x86_lir_count(OptIrNodeCore core, OptIrNodeOperands operands)
{
    if (opt_ir_op(core) == SEMANTIC_LIR_OP_NOP) return 0u;
    // Native strings are a pointer/length pair. Every value-producing string
    // row has the same two-row target representation, whether its source is
    // rodata or a declaration read.
    if (opt_ir_op(core) == SEMANTIC_LIR_OP_CONST_STRING ||
        ((opt_ir_op(core) == SEMANTIC_LIR_OP_VALUE_GET ||
          (opt_ir_op(core) == SEMANTIC_LIR_OP_LOAD &&
           (core.flags & SEMANTIC_LIR_FLAG_FIELD) != 0u)) &&
         core.type_id == SEMANTIC_LIR_TY_STRING))
        return 2u;
    if (opt_ir_op(core) == SEMANTIC_LIR_OP_VALUE_GET &&
        (core.flags & SEMANTIC_LIR_FLAG_ARRAY_PAIR) != 0u)
        return NATIVE_SLICE_WORDS;
    return opt_ir_op(core) == SEMANTIC_LIR_OP_AGGREGATE_NEW
        ? 1u + core.value_word_count
        : 1u;
}

uint x86_abi_type_width(uint type_id)
{
    return type_id == SEMANTIC_LIR_TY_STRING ? 2u : 1u;
}

uint x86_abi_argument_width(uint metadata)
{
    return (metadata & SEMANTIC_LIR_VALUE_ARRAY_PAIR) != 0u ? NATIVE_SLICE_WORDS
        : (metadata & SEMANTIC_LIR_VALUE_STRING) != 0u ? 2u : 1u;
}

uint x86_abi_param_width(SemanticLirParam param)
{
    return (param.value_metadata & SEMANTIC_LIR_VALUE_ARRAY_PAIR) != 0u
        ? NATIVE_SLICE_WORDS : x86_abi_type_width(param.type_id);
}

// Declarations use a fixed three-word home. This keeps component locations a
// pure arithmetic projection and avoids a per-function prefix table. Scalar
// declarations use the first word; strings use two and slices use all three.
uint x86_declaration_slot_offset(uint logical_ordinal)
{
    return logical_ordinal * NATIVE_SLICE_WORDS;
}

uint x86_declaration_slot_count(uint param_count, uint local_count)
{
    return x86_declaration_slot_offset(param_count + local_count);
}

// Floating arithmetic tags identify operations; checked scalar metadata
// selects single or double precision in their emitter.
uint x86_binary_payload(OptIrNodeCore core)
{
    bool floating = scalar_is_float(core.type_id);
    if (opt_ir_op(core) == SEMANTIC_LIR_OP_ADD) return floating ? X86_LIR_BINARY_ADD_FLOAT : X86_LIR_BINARY_ADD_I32;
    if (opt_ir_op(core) == SEMANTIC_LIR_OP_SUB) return floating ? X86_LIR_BINARY_SUB_FLOAT : X86_LIR_BINARY_SUB_I32;
    if (opt_ir_op(core) == SEMANTIC_LIR_OP_MUL) return floating ? X86_LIR_BINARY_MUL_FLOAT : X86_LIR_BINARY_MUL_I32;
    if (opt_ir_op(core) == SEMANTIC_LIR_OP_DIV) return floating ? X86_LIR_BINARY_DIV_FLOAT : X86_LIR_BINARY_DIV_I32;
    if (opt_ir_op(core) == SEMANTIC_LIR_OP_REM) return X86_LIR_BINARY_REM_I32;
    if (opt_ir_op(core) == SEMANTIC_LIR_OP_BIT_AND) return X86_LIR_BINARY_BIT_AND_I32;
    if (opt_ir_op(core) == SEMANTIC_LIR_OP_BIT_OR) return X86_LIR_BINARY_BIT_OR_I32;
    if (opt_ir_op(core) == SEMANTIC_LIR_OP_BIT_XOR) return X86_LIR_BINARY_BIT_XOR_I32;
    if (opt_ir_op(core) == SEMANTIC_LIR_OP_SHIFT_LEFT) return X86_LIR_BINARY_SHL_I32;
    if (opt_ir_op(core) == SEMANTIC_LIR_OP_SHIFT_RIGHT) return X86_LIR_BINARY_SHR_I32;
    if (opt_ir_op(core) == SEMANTIC_LIR_OP_LOGICAL_AND) return X86_LIR_BINARY_AND_BOOL;
    if (opt_ir_op(core) == SEMANTIC_LIR_OP_LOGICAL_OR) return X86_LIR_BINARY_OR_BOOL;
    return 0u;
}

uint x86_lir_opcode(OptIrNodeCore core)
{
    // Floating arithmetic has no integer fallback. Remainder and bitwise
    // operations require their own checked semantics and lowering. An
    // explicit conversion (`as`) lowers through plan_convert.
    uint semantic_op = opt_ir_op(core);
    // Literal payload format is owned by its semantic opcode. A type change
    // cannot reinterpret integer bits or a rounded f32 payload as f64.
    if ((semantic_op == SEMANTIC_LIR_OP_CONST_F32 && core.type_id != SCALAR_F32) ||
        (semantic_op == SEMANTIC_LIR_OP_CONST_F64 && core.type_id != SCALAR_F64) ||
        ((semantic_op == SEMANTIC_LIR_OP_CONST_I32 || semantic_op == SEMANTIC_LIR_OP_CONST_I64) &&
         scalar_is_float(core.type_id))) return 0u;
    if (scalar_is_float(core.type_id) &&
        (semantic_op == SEMANTIC_LIR_OP_REM ||
         (semantic_op >= SEMANTIC_LIR_OP_BIT_AND && semantic_op <= SEMANTIC_LIR_OP_SHIFT_RIGHT) ||
         semantic_op == SEMANTIC_LIR_OP_LOGICAL_NOT ||
         semantic_op == SEMANTIC_LIR_OP_LOGICAL_AND || semantic_op == SEMANTIC_LIR_OP_LOGICAL_OR))
        return 0u;
    if (semantic_op == SEMANTIC_LIR_OP_CONST_I64 || semantic_op == SEMANTIC_LIR_OP_CONST_F64)
        return X86_LIR_OP_IMM_I64;
    if (opt_ir_op(core) == SEMANTIC_LIR_OP_ADDRESS) return X86_LIR_OP_DECL_ADDRESS;
    if (opt_ir_op(core) == SEMANTIC_LIR_OP_FIELD_ADDRESS) return X86_LIR_OP_FIELD_ADDRESS;
    if (opt_ir_op(core) == SEMANTIC_LIR_OP_INDEX_ADDRESS) return X86_LIR_OP_INDEX_ADDRESS;
    if (opt_ir_op(core) == SEMANTIC_LIR_OP_PLACE_LOAD) return X86_LIR_OP_PLACE_LOAD;
    if (opt_ir_op(core) == SEMANTIC_LIR_OP_PLACE_STORE) return X86_LIR_OP_PLACE_STORE;
    if (opt_ir_op(core) == SEMANTIC_LIR_OP_CONST_I32 || opt_ir_op(core) == SEMANTIC_LIR_OP_CONST_F32)
        return X86_LIR_OP_IMM_I32;
    if (opt_ir_op(core) == SEMANTIC_LIR_OP_VALUE_GET) return X86_LIR_OP_ALIAS;
    if (opt_ir_op(core) == SEMANTIC_LIR_OP_STORE &&
        (core.flags & SEMANTIC_LIR_FLAG_INDEXED) != 0u)
        return X86_LIR_OP_INDEX_STORE;
    if (opt_ir_op(core) == SEMANTIC_LIR_OP_STORE &&
        (core.flags & SEMANTIC_LIR_FLAG_FIELD) != 0u)
        return X86_LIR_OP_FIELD_STORE;
    if (opt_ir_op(core) == SEMANTIC_LIR_OP_VALUE_SET || opt_ir_op(core) == SEMANTIC_LIR_OP_STORE)
        return X86_LIR_OP_STORE_LOCAL;
    if ((opt_ir_op(core) >= SEMANTIC_LIR_OP_ADD && opt_ir_op(core) <= SEMANTIC_LIR_OP_SHIFT_RIGHT) ||
        opt_ir_op(core) == SEMANTIC_LIR_OP_LOGICAL_AND || opt_ir_op(core) == SEMANTIC_LIR_OP_LOGICAL_OR)
        return X86_LIR_OP_BINARY;
    if (opt_ir_op(core) == SEMANTIC_LIR_OP_COMPARE) return X86_LIR_OP_COMPARE;
    if (opt_ir_op(core) == SEMANTIC_LIR_OP_NEGATE || opt_ir_op(core) == SEMANTIC_LIR_OP_LOGICAL_NOT ||
        opt_ir_op(core) == SEMANTIC_LIR_OP_CONVERT)
        return X86_LIR_OP_UNARY;
    if (opt_ir_op(core) == SEMANTIC_LIR_OP_CALL_HOST) return X86_LIR_OP_CALL_HOST;
    if (opt_ir_op(core) == SEMANTIC_LIR_OP_CALL_SYMBOL) return X86_LIR_OP_CALL_SYMBOL;
    if (opt_ir_op(core) == SEMANTIC_LIR_OP_CALL_INTRINSIC) return X86_LIR_OP_PRINT_I32;
    if (opt_ir_op(core) == SEMANTIC_LIR_OP_AGGREGATE_NEW ||
        opt_ir_op(core) == SEMANTIC_LIR_OP_AGGREGATE_COPY)
        return X86_LIR_OP_AGGREGATE_ADDR;
    if (opt_ir_op(core) == SEMANTIC_LIR_OP_LOAD &&
        (core.flags & SEMANTIC_LIR_FLAG_INDEXED) != 0u)
        return X86_LIR_OP_INDEX_LOAD;
    if (opt_ir_op(core) == SEMANTIC_LIR_OP_LOAD &&
        (core.flags & SEMANTIC_LIR_FLAG_FIELD) != 0u)
        return X86_LIR_OP_FIELD_LOAD;
    if (opt_ir_op(core) == SEMANTIC_LIR_OP_CALL)
        return X86_LIR_OP_CALL;
    if (opt_ir_op(core) == SEMANTIC_LIR_OP_IF_BEGIN || opt_ir_op(core) == SEMANTIC_LIR_OP_ELSE ||
        opt_ir_op(core) == SEMANTIC_LIR_OP_BRANCH || opt_ir_op(core) == SEMANTIC_LIR_OP_BRANCH_IF)
        return X86_LIR_OP_BRANCH;
    if (opt_ir_op(core) == SEMANTIC_LIR_OP_BLOCK_BEGIN ||
        opt_ir_op(core) == SEMANTIC_LIR_OP_LOOP_BEGIN ||
        opt_ir_op(core) == SEMANTIC_LIR_OP_CONTROL_END)
        return X86_LIR_OP_LABEL;
    if (opt_ir_op(core) == SEMANTIC_LIR_OP_RETURN) return X86_LIR_OP_RETURN;
    if (opt_ir_op(core) == SEMANTIC_LIR_OP_TRAP) return X86_LIR_OP_TRAP;
    return 0u;
}

// `as` converts a numeric, bool or char source to a numeric target, u8 to
// char, and bool or char to itself. A char is its 32-bit code point, so none
// of these needs extra code.
bool x86_convert_supported(uint source, uint target)
{
    uint numeric = SCALAR_INTEGER_SET | SCALAR_FLOAT_SET;
    uint bool_char = (1u << SCALAR_BOOL) | (1u << SCALAR_CHAR);
    return (scalar_in_set(source, numeric | bool_char) && scalar_in_set(target, numeric)) ||
        (source == SCALAR_U8 && target == SCALAR_CHAR) ||
        (source == target && scalar_in_set(source, bool_char));
}

bool x86_lir_supported(OptIrNodeCore core)
{
    // Semantic branch targets are stable LIR control-row identities. They
    // become x86 relative targets only in the control-label resolver.
    // Host calls require service-specific ABI validation in scatter. Compiler
    // intrinsics likewise validate their stable tag there.
    return x86_lir_opcode(core) != 0u &&
        opt_ir_op(core) != SEMANTIC_LIR_OP_CALL_HOST;
}

// Scalar bodies selected here have one emitter and one count owner. Prologues,
// guards and footers retain their independent byte ranges; the existing
// ordered count pass combines body bytes with independently emitted guards.
bool x86_is_specialized_integer_instruction(X86LirCore core, X86LirOperands operands)
{
    // Conversions have one body for every scalar pair; see plan_convert.
    if (core.op == X86_LIR_OP_UNARY && operands.a == X86_LIR_UNARY_CONVERT) return true;
    uint type = operands.metadata & 0xffu;
    if ((operands.metadata & (X86_LIR_METADATA_AGGREGATE |
        X86_LIR_METADATA_STRING_PAIR | X86_LIR_METADATA_ARRAY_PAIR |
        X86_LIR_METADATA_PACKED_I32_ARRAY)) != 0u) return false;
    if (core.op == X86_LIR_OP_IMM_I64) return scalar_is_wide_integer(type);
    if ((core.op == X86_LIR_OP_COMPARE || core.op == X86_LIR_OP_COMPARE_BRANCH_FALSE) &&
        scalar_uses_64bit_gpr(type)) return true;
    if (core.op == X86_LIR_OP_BINARY && type == SCALAR_PTR)
        return operands.a == X86_LIR_BINARY_ADD_I32 || operands.a == X86_LIR_BINARY_SUB_I32;
    if (!scalar_is_wide_integer(type) && !scalar_is_narrow_integer(type)) return false;
    if (core.op == X86_LIR_OP_UNARY) return operands.a == X86_LIR_UNARY_NEG_I32;
    return core.op == X86_LIR_OP_BINARY &&
        ((operands.a >= X86_LIR_BINARY_ADD_I32 && operands.a <= X86_LIR_BINARY_MUL_I32) ||
         (operands.a >= X86_LIR_BINARY_REM_I32 && operands.a <= X86_LIR_BINARY_SHR_I32));
}

// Scalar float bodies share the existing specialized pass so the main emitter
// does not grow another arithmetic family. Copies, calls and storage remain in
// their existing owners; this predicate never classifies aggregate addresses.
bool x86_is_specialized_float_instruction(X86LirCore core, X86LirOperands operands)
{
    if (!x86_scalar_float(operands.metadata)) return false;
    if (core.op == X86_LIR_OP_IMM_I64) return x86_scalar_f64(operands.metadata);
    if (core.op == X86_LIR_OP_COMPARE || core.op == X86_LIR_OP_COMPARE_BRANCH_FALSE) return true;
    if (core.op == X86_LIR_OP_UNARY) return operands.a == X86_LIR_UNARY_NEG_FLOAT;
    return core.op == X86_LIR_OP_BINARY &&
        operands.a >= X86_LIR_BINARY_ADD_FLOAT && operands.a <= X86_LIR_BINARY_DIV_FLOAT;
}

bool x86_is_specialized_scalar_instruction(X86LirCore core, X86LirOperands operands)
{
    return x86_is_specialized_integer_instruction(core, operands) ||
        x86_is_specialized_float_instruction(core, operands);
}

// Both emitters must agree on the sole writer of each instruction.
bool x86_is_specialized_instruction(X86LirCore core,
                                   X86LirOperands operands)
{
    if (x86_is_specialized_scalar_instruction(core, operands)) return true;
    if (core.op == X86_LIR_OP_DECL_ADDRESS || core.op == X86_LIR_OP_FIELD_ADDRESS ||
        core.op == X86_LIR_OP_INDEX_ADDRESS || core.op == X86_LIR_OP_PLACE_LOAD ||
        core.op == X86_LIR_OP_PLACE_STORE) return true;
    return core.op == X86_LIR_OP_INDEX_LOAD || core.op == X86_LIR_OP_INDEX_STORE ||
        core.op == X86_LIR_OP_PRINT_I32 ||
        core.op == X86_LIR_OP_INTRINSIC_IDENTITY ||
        (core.op == X86_LIR_OP_AGGREGATE_RETURN_WORD &&
         (operands.metadata & X86_LIR_METADATA_ARRAY_PAIR) != 0u) ||
        ((operands.metadata & 0xffu) == SEMANTIC_LIR_TY_STRING &&
         (core.op == X86_LIR_OP_CALL ||
          core.op == X86_LIR_OP_CALL_SYMBOL ||
          core.op == X86_LIR_OP_AGGREGATE_RETURN_WORD)) ||
        (operands.metadata & X86_LIR_METADATA_INDEX_AGGREGATE_COPY) != 0u ||
        ((operands.metadata & X86_LIR_METADATA_AGGREGATE) != 0u &&
         (core.op == X86_LIR_OP_COMPARE ||
          core.op == X86_LIR_OP_COMPARE_BRANCH_FALSE ||
          core.op == X86_LIR_OP_SELECT_STORE)) ||
        (operands.metadata & X86_LIR_METADATA_PACKED_I32_ARRAY) != 0u ||
        (core.op == X86_LIR_OP_CALL_ARG &&
         (operands.metadata & X86_LIR_METADATA_INDIRECT_ARRAY_PAIR) != 0u) ||
        (core.op == X86_LIR_OP_FIELD_STORE &&
         (operands.metadata & (X86_LIR_METADATA_FIELD_AGGREGATE_WORD |
             X86_LIR_METADATA_STRING_PAIR | X86_LIR_METADATA_ARRAY_PAIR)) != 0u) ||
        (core.op == X86_LIR_OP_STORE_LOCAL &&
         (operands.metadata & X86_LIR_METADATA_ARRAY_PAIR) != 0u) ||
        core.op == X86_LIR_OP_INTRINSIC_SLICE_FROM_RAW_PARTS;
}

bool float_binary_commutative(uint operation)
{
    return operation == X86_LIR_BINARY_ADD_FLOAT ||
        operation == X86_LIR_BINARY_MUL_FLOAT;
}
