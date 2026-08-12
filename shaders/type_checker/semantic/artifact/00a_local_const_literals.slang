import hir_records;
import gpu_index;

struct Params { uint n_tokens; uint source_len; uint n_hir_nodes; uint n_source_files; uint parser_feature_flags; };
ConstantBuffer<Params> gParams;
StructuredBuffer<uint> compact_hir_count;
StructuredBuffer<HirCore> compact_hir_core;
StructuredBuffer<HirPayload> compact_hir_payload;
StructuredBuffer<uint> compact_hir_expr_parent;
StructuredBuffer<uint> compact_hir_nearest_fn;
StructuredBuffer<uint> compact_expr_scalar_type;
RWStructuredBuffer<uint> semantic_value_const_by_hir;
RWStructuredBuffer<uint> semantic_value_const_present_by_hir;

static const uint INVALID = 0xffffffffu;
static const uint HIR_EXPR = 14u;
static const uint HIR_BINARY_EXPR = 16u;
static const uint HIR_UNARY_EXPR = 17u;
static const uint HIR_LITERAL_EXPR = 23u;
static const uint HIR_EXPR_FORWARD = 1u;
static const uint HIR_EXPR_INT = 3u;
static const uint HIR_EXPR_TRUE = 4u;
static const uint HIR_EXPR_FALSE = 5u;
static const uint HIR_EXPR_CHAR = 29u;
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
static const uint TY_INT = 3u;
static const uint TY_FLOAT = 5u;
static const uint SCALAR_TYPE_SHIFT = 28u;
static const uint LEFT_READY = 1u;
static const uint RIGHT_READY = 2u;
static const uint BOTH_READY = 3u;
static const uint CONST_PRESENT = 0x80000000u;
static const uint DISPATCH_X_STRIDE = 16776960u;

uint scalar_type(uint node)
{
    return node < min(compact_hir_count[0u], gParams.n_hir_nodes)
        ? compact_expr_scalar_type[node] >> SCALAR_TYPE_SHIFT : 0u;
}

bool evaluate_unary(uint form, uint operand, uint operand_type, out uint result)
{
    result = 0u;
    if (form == HIR_EXPR_NOT) { result = operand == 0u ? 1u : 0u; return true; }
    if (form != HIR_EXPR_NEG) return false;
    result = operand_type == TY_FLOAT
        ? asuint(-asfloat(operand)) : uint(-int(operand));
    return true;
}

bool evaluate_binary(
    uint form, uint lhs, uint rhs, uint operand_type, out uint result)
{
    result = 0u;
    bool floating = operand_type == TY_FLOAT;
    bool signed_integer = operand_type == TY_INT;
    if (form == HIR_EXPR_ADD) result = floating ? asuint(asfloat(lhs) + asfloat(rhs)) : lhs + rhs;
    else if (form == HIR_EXPR_SUB) result = floating ? asuint(asfloat(lhs) - asfloat(rhs)) : lhs - rhs;
    else if (form == HIR_EXPR_MUL) result = floating ? asuint(asfloat(lhs) * asfloat(rhs)) : lhs * rhs;
    else if (form == HIR_EXPR_DIV)
    {
        if ((!floating && rhs == 0u) || (floating && asfloat(rhs) == 0.0f)) return false;
        result = floating ? asuint(asfloat(lhs) / asfloat(rhs))
                          : (signed_integer ? uint(int(lhs) / int(rhs)) : lhs / rhs);
    }
    else if (form == HIR_EXPR_MOD)
    {
        if (rhs == 0u || floating) return false;
        result = signed_integer ? uint(int(lhs) % int(rhs)) : lhs % rhs;
    }
    else if (form == HIR_EXPR_AND) result = lhs != 0u && rhs != 0u ? 1u : 0u;
    else if (form == HIR_EXPR_OR) result = lhs != 0u || rhs != 0u ? 1u : 0u;
    else if (form == HIR_EXPR_BIT_OR) result = lhs | rhs;
    else if (form == HIR_EXPR_BIT_XOR) result = lhs ^ rhs;
    else if (form == HIR_EXPR_BIT_AND) result = lhs & rhs;
    else if (form == HIR_EXPR_SHL) result = lhs << (rhs & 31u);
    else if (form == HIR_EXPR_SHR)
        result = signed_integer ? uint(int(lhs) >> (rhs & 31u)) : lhs >> (rhs & 31u);
    else if (form == HIR_EXPR_EQ)
        result = floating ? (asfloat(lhs) == asfloat(rhs) ? 1u : 0u) : (lhs == rhs ? 1u : 0u);
    else if (form == HIR_EXPR_NE)
        result = floating ? (asfloat(lhs) != asfloat(rhs) ? 1u : 0u) : (lhs != rhs ? 1u : 0u);
    else if (form == HIR_EXPR_LT)
        result = floating ? (asfloat(lhs) < asfloat(rhs) ? 1u : 0u)
                          : (signed_integer ? (int(lhs) < int(rhs) ? 1u : 0u) : (lhs < rhs ? 1u : 0u));
    else if (form == HIR_EXPR_GT)
        result = floating ? (asfloat(lhs) > asfloat(rhs) ? 1u : 0u)
                          : (signed_integer ? (int(lhs) > int(rhs) ? 1u : 0u) : (lhs > rhs ? 1u : 0u));
    else if (form == HIR_EXPR_LE)
        result = floating ? (asfloat(lhs) <= asfloat(rhs) ? 1u : 0u)
                          : (signed_integer ? (int(lhs) <= int(rhs) ? 1u : 0u) : (lhs <= rhs ? 1u : 0u));
    else if (form == HIR_EXPR_GE)
        result = floating ? (asfloat(lhs) >= asfloat(rhs) ? 1u : 0u)
                          : (signed_integer ? (int(lhs) >= int(rhs) ? 1u : 0u) : (lhs >= rhs ? 1u : 0u));
    else return false;
    return true;
}

void propagate_constant(uint node, uint hir_count)
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
            uint result = semantic_value_const_by_hir[current];
            if (parent_payload.a != HIR_EXPR_FORWARD &&
                !evaluate_unary(parent_payload.a, result, scalar_type(current), result))
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
        uint result;
        if (!evaluate_binary(
                parent_payload.a,
                semantic_value_const_by_hir[parent_payload.b],
                semantic_value_const_by_hir[parent_payload.c],
                scalar_type(parent_payload.b),
                result))
            return;
        semantic_value_const_by_hir[parent] = result;
        InterlockedExchange(semantic_value_const_present_by_hir[parent], CONST_PRESENT);
        current = parent;
    }
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint row = linear_dispatch_thread_id_2d(dtid, DISPATCH_X_STRIDE);
    uint hir_count = min(compact_hir_count[0u], gParams.n_hir_nodes);
    if (row >= hir_count) return;
    HirCore core = compact_hir_core[row];
    HirPayload payload = compact_hir_payload[row];
    bool present = false;
    if (core.kind == HIR_LITERAL_EXPR &&
        compact_hir_nearest_fn[row] == INVALID &&
        (payload.a == HIR_EXPR_INT || payload.a == HIR_EXPR_CHAR ||
         payload.a == HIR_EXPR_TRUE || payload.a == HIR_EXPR_FALSE))
    {
        semantic_value_const_by_hir[row] =
            payload.a == HIR_EXPR_TRUE ? 1u : payload.a == HIR_EXPR_FALSE ? 0u : payload.b;
        semantic_value_const_present_by_hir[row] = CONST_PRESENT;
        present = true;
    }
    if (present) propagate_constant(row, hir_count);
}
