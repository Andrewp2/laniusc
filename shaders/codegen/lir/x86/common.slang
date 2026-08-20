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
static const uint X86_CONSTANT_DIVISOR_NONE = 0u;
static const uint X86_CONSTANT_DIVISOR_POWER_OF_TWO = 1u;
static const uint X86_CONSTANT_DIVISOR_SIGNED = 2u;

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

uint x86_caller_declaration_ordinal(uint physical_register)
{
    if (physical_register == 8u) return 4u;
    if (physical_register == 9u) return 5u;
    if (physical_register == 10u) return 2u;
    if (physical_register == 11u) return 3u;
    return X86_LOCATION_INVALID;
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
    if (type_id == X86_LIR_TY_FLOAT ||
        type_id == SEMANTIC_LIR_TY_POINTER ||
        type_id == SEMANTIC_LIR_TY_STRING)
        return false;
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
    if (type_id == X86_LIR_TY_FLOAT ||
        type_id == SEMANTIC_LIR_TY_POINTER ||
        type_id == SEMANTIC_LIR_TY_STRING)
        return false;
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
    if (type_id == X86_LIR_TY_FLOAT ||
        type_id == SEMANTIC_LIR_TY_POINTER ||
        type_id == SEMANTIC_LIR_TY_STRING)
        return false;
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
    bool power_of_two = (divisor & (divisor - 1u)) == 0u;
    bool is_unsigned = type_id == 4u || type_id == 6u;
    if (power_of_two && (is_unsigned || int(divisor) > 0))
        return X86_CONSTANT_DIVISOR_POWER_OF_TWO;
    if (!power_of_two && type_id == 3u && int(divisor) > 1)
        return X86_CONSTANT_DIVISOR_SIGNED;
    return X86_CONSTANT_DIVISOR_NONE;
}

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
