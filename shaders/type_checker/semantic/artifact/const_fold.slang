// Constant folding of expressions outside function bodies: const and static
// initializers, including constants computed from other constants.
//
// semantic_value_const_present_by_hir is a tagged fact per HIR node.
// CONST_PRESENT means semantic_value_const_by_hir holds the node's value. A
// binary node collects LEFT_READY and RIGHT_READY from its operands, and the
// lane that completes both evaluates it (const_fold_propagate). Each operand
// contributes its bit once, when it becomes present.
//
// Folding runs in rounds: 00a, then per round 00a1 (size), 00b (resolve)
// and 00b2 (publish). 00a folds literal leaves and imported constant paths
// outside function bodies. A name or path reference to a local constant
// whose initializer root is present is CONST_STAGED by 00b, and 00b2 turns
// it into CONST_PRESENT and folds its parents. A staged node is not present
// within its round, so round k resolves exactly the constants whose roots
// were present after round k - 1, whatever the workgroup order: a chain of d
// constants that refer to each other folds in d rounds. The host records
// LOCAL_CONST_FOLD_ROUNDS rounds (type_checker/mod.rs); a deeper constant
// stays unevaluated and a public one fails the interface export by name.
import integer_words;
import primitive_types;
import hir_records;

public StructuredBuffer<uint> compact_hir_count;
public StructuredBuffer<HirCore> compact_hir_core;
public StructuredBuffer<HirPayload> compact_hir_payload;
public StructuredBuffer<uint> compact_hir_expr_parent;
public StructuredBuffer<uint> compact_expr_scalar_type;
public RWStructuredBuffer<uint2> semantic_value_const_by_hir;
public RWStructuredBuffer<uint> semantic_value_const_present_by_hir;

public static const uint CONST_PRESENT = 0x80000000u;
// A constant reference resolved in the current round (00b); present from
// the next round on (00b2).
public static const uint CONST_STAGED = 0x08000000u;

static const uint HIR_EXPR = 14u;
static const uint HIR_BINARY_EXPR = 16u;
static const uint HIR_UNARY_EXPR = 17u;
static const uint HIR_EXPR_FORWARD = 1u;
static const uint HIR_EXPR_NOT = 6u;
static const uint HIR_EXPR_EQ = 7u;
static const uint HIR_EXPR_NE = 8u;
static const uint HIR_EXPR_LT = 9u;
static const uint HIR_EXPR_GT = 10u;
static const uint HIR_EXPR_LE = 11u;
static const uint HIR_EXPR_GE = 12u;
static const uint HIR_EXPR_NEG = 13u;
static const uint HIR_EXPR_ADD = 14u;
static const uint HIR_EXPR_SUB = 15u;
static const uint HIR_EXPR_MUL = 16u;
static const uint HIR_EXPR_AND = 17u;
static const uint HIR_EXPR_OR = 18u;
static const uint HIR_EXPR_MOD = 19u;
static const uint HIR_EXPR_DIV = 20u;
static const uint HIR_EXPR_BIT_OR = 21u;
static const uint HIR_EXPR_BIT_XOR = 22u;
static const uint HIR_EXPR_BIT_AND = 23u;
static const uint HIR_EXPR_SHL = 24u;
static const uint HIR_EXPR_SHR = 25u;
static const uint LEFT_READY = 1u;
static const uint RIGHT_READY = 2u;
static const uint BOTH_READY = 3u;

// Active HIR rows of the job.
public uint const_fold_hir_count(uint n_hir_nodes)
{
    return min(compact_hir_count[0u], n_hir_nodes);
}

uint scalar_type(uint node, uint hir_count)
{
    return node < hir_count ? compact_expr_scalar_type[node] >> SCALAR_TYPE_SHIFT : 0u;
}

bool evaluate_unary(uint form, uint2 operand, uint operand_type, out uint2 result)
{
    result = uint2(0u, 0u);
    if (form == HIR_EXPR_NOT) { result.x = integer_words_zero(operand) ? 1u : 0u; return true; }
    if (form != HIR_EXPR_NEG) return false;
    if (scalar_is_float(operand_type))
    {
        result = operand;
        if (operand_type == SCALAR_F64) result.y ^= 0x80000000u;
        else result.x ^= 0x80000000u;
        return true;
    }
    uint bits = scalar_integer_bits(operand_type);
    if (bits == 0u) return false;
    result = integer_words_normalize(integer_words_negate(operand), bits);
    return true;
}

bool evaluate_binary(uint form, uint2 lhs, uint2 rhs, uint operand_type, out uint2 result)
{
    result = uint2(0u, 0u);
    // Native GPU floats do not establish portable IEEE constant semantics.
    // Admission rejects this pending evaluator explicitly; never publish zero.
    if (scalar_is_float(operand_type)) return false;
    uint bits = scalar_integer_bits(operand_type);
    if (bits == 0u && (operand_type == SCALAR_BOOL || operand_type == SCALAR_CHAR)) bits = 32u;
    if (bits == 0u) return false;
    bool signed_integer = scalar_is_signed_integer(operand_type);
    lhs = integer_words_normalize(lhs, bits);
    // Shift counts have their own checked integer width; never truncate one
    // to the operation width before its full-value range check.
    bool shift = form == HIR_EXPR_SHL || form == HIR_EXPR_SHR;
    if (!shift) rhs = integer_words_normalize(rhs, bits);
    if (form == HIR_EXPR_ADD) result = integer_words_add(lhs, rhs);
    else if (form == HIR_EXPR_SUB) result = integer_words_sub(lhs, rhs);
    else if (form == HIR_EXPR_MUL) result = integer_words_multiply(lhs, rhs);
    else if (form == HIR_EXPR_DIV || form == HIR_EXPR_MOD)
    {
        uint2 quotient; uint2 remainder;
        if (integer_words_divide(lhs, rhs, operand_type, quotient, remainder) != 0u) return false;
        result = form == HIR_EXPR_DIV ? quotient : remainder;
    }
    else if (form == HIR_EXPR_AND) result.x = uint(!integer_words_zero(lhs) && !integer_words_zero(rhs));
    else if (form == HIR_EXPR_OR) result.x = uint(!integer_words_zero(lhs) || !integer_words_zero(rhs));
    else if (form == HIR_EXPR_BIT_OR) result = lhs | rhs;
    else if (form == HIR_EXPR_BIT_XOR) result = lhs ^ rhs;
    else if (form == HIR_EXPR_BIT_AND) result = lhs & rhs;
    else if (shift)
    {
        if (rhs.y != 0u || rhs.x >= bits) return false;
        result = form == HIR_EXPR_SHL ? integer_words_shift_left(lhs, rhs.x)
            : signed_integer ? integer_words_arithmetic_shift_right(lhs, rhs.x, bits)
            : integer_words_shift_right(lhs, rhs.x);
    }
    else if (form >= HIR_EXPR_EQ && form <= HIR_EXPR_GE)
    {
        bool equal = all(lhs == rhs);
        bool less = signed_integer ? integer_words_less_signed(lhs, rhs, bits) : integer_words_less(lhs, rhs);
        result.x = form == HIR_EXPR_EQ ? uint(equal) : form == HIR_EXPR_NE ? uint(!equal) :
            form == HIR_EXPR_LT ? uint(less) : form == HIR_EXPR_GT ? uint(!less && !equal) :
            form == HIR_EXPR_LE ? uint(less || equal) : uint(!less);
        return true;
    }
    else return false;
    result = integer_words_normalize(result, bits);
    return true;
}

// Folds the parents of `node`, which just became present: forwards and
// unary operators directly, a binary operator once both operands are
// present (the lane that sets the second ready bit evaluates it).
public void const_fold_propagate(uint node, uint hir_count)
{
    uint current = node;
    while (current < hir_count)
    {
        uint parent = compact_hir_expr_parent[current];
        if (parent >= hir_count) return;
        HirCore parent_core = compact_hir_core[parent];
        HirPayload parent_payload = compact_hir_payload[parent];
        if ((parent_core.kind == HIR_UNARY_EXPR ||
             (parent_core.kind == HIR_EXPR && parent_payload.a == HIR_EXPR_FORWARD)) &&
            parent_payload.b == current)
        {
            uint2 result = semantic_value_const_by_hir[current];
            if (parent_payload.a != HIR_EXPR_FORWARD &&
                !evaluate_unary(parent_payload.a, result, scalar_type(current, hir_count), result))
                return;
            semantic_value_const_by_hir[parent] = result;
            InterlockedExchange(semantic_value_const_present_by_hir[parent], CONST_PRESENT);
            current = parent;
            continue;
        }
        if (parent_core.kind != HIR_BINARY_EXPR) return;
        uint ready = parent_payload.b == current ? LEFT_READY
                   : parent_payload.c == current ? RIGHT_READY : 0u;
        if (ready == 0u) return;
        DeviceMemoryBarrier();
        uint prior;
        InterlockedOr(semantic_value_const_present_by_hir[parent], ready, prior);
        if ((prior & ready) != 0u || (prior | ready) != BOTH_READY) return;
        uint2 result;
        if (!evaluate_binary(
                parent_payload.a,
                semantic_value_const_by_hir[parent_payload.b],
                semantic_value_const_by_hir[parent_payload.c],
                scalar_type(parent_payload.b, hir_count),
                result))
            return;
        semantic_value_const_by_hir[parent] = result;
        InterlockedExchange(semantic_value_const_present_by_hir[parent], CONST_PRESENT);
        current = parent;
    }
}
