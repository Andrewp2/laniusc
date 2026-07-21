// Project compact constant declarations into the token-indexed x86 value table.

import gpu_index;
struct Params
{
    uint n_tokens;
    uint source_len;
    uint out_capacity;
    uint n_hir_nodes;
};

ConstantBuffer<Params> gParams;

struct HirCore { uint kind; uint parent; uint token_start; uint token_end; };
struct HirPayload { uint a; uint b; uint c; uint d; };

StructuredBuffer<uint> compact_hir_count;
StructuredBuffer<HirCore> compact_hir_core;
StructuredBuffer<HirPayload> compact_hir_payload;
StructuredBuffer<uint> compact_const_value;

RWStructuredBuffer<uint2> x86_const_value_record;
RWStructuredBuffer<uint> x86_const_value_status;

static const uint INVALID = 0xffffffffu;
static const uint DISPATCH_X_STRIDE = 16776960u;
static const uint HIR_ITEM_KIND_CONST = 3u;
static const uint HIR_EXPR_INT = 3u;
static const uint HIR_EXPR_TRUE = 4u;
static const uint HIR_EXPR_FALSE = 5u;
static const uint HIR_EXPR_FLOAT = 27u;
static const uint HIR_EXPR_NOT = 6u;
static const uint HIR_EXPR_NEG = 13u;
static const uint HIR_EXPR_EQ = 7u;
static const uint HIR_EXPR_NE = 8u;
static const uint HIR_EXPR_LT = 9u;
static const uint HIR_EXPR_GT = 10u;
static const uint HIR_EXPR_LE = 11u;
static const uint HIR_EXPR_GE = 12u;
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
static const uint X86_CONST_VALUE_LITERAL = 1u;
static const uint X86_CONST_VALUES_OK = 1u;
static const uint I32_SIGN_BIT = 0x80000000u;

uint linear_dispatch_id(uint3 tid)
{
    return linear_dispatch_thread_id_2d(tid, DISPATCH_X_STRIDE);
}

uint active_hir_count()
{
    return min(gParams.n_hir_nodes, compact_hir_count[0u]);
}

bool valid_hir(uint hir)
{
    return hir != INVALID && hir < active_hir_count();
}

bool valid_token(uint token)
{
    return token != INVALID && token < gParams.n_tokens;
}

bool literal_leaf_value(uint hir, out uint value)
{
    value = 0u;
    if (!valid_hir(hir))
        return false;

    HirPayload payload = compact_hir_payload[hir];
    if (payload.a == HIR_EXPR_INT || payload.a == HIR_EXPR_FLOAT)
    {
        value = payload.b;
        return true;
    }
    if (payload.a == HIR_EXPR_TRUE || payload.a == HIR_EXPR_FALSE)
    {
        value = payload.a == HIR_EXPR_TRUE ? 1u : 0u;
        return true;
    }
    return false;
}

bool literal_atom_value(uint hir, out uint value)
{
    value = 0u;
    if (literal_leaf_value(hir, value))
        return true;

    if (!valid_hir(hir))
        return false;

    HirPayload payload = compact_hir_payload[hir];
    uint inner = 0u;
    if (payload.a == HIR_EXPR_NEG && literal_leaf_value(payload.b, inner))
    {
        value = compact_hir_payload[payload.b].a == HIR_EXPR_FLOAT
            ? inner ^ I32_SIGN_BIT
            : 0u - inner;
        return true;
    }
    if (payload.a == HIR_EXPR_NOT && literal_leaf_value(payload.b, inner))
    {
        value = inner == 0u ? 1u : 0u;
        return true;
    }
    return false;
}

bool scalar_binary_const_form(uint form)
{
    return form == HIR_EXPR_EQ ||
           form == HIR_EXPR_NE ||
           form == HIR_EXPR_LT ||
           form == HIR_EXPR_GT ||
           form == HIR_EXPR_LE ||
           form == HIR_EXPR_GE ||
           form == HIR_EXPR_ADD ||
           form == HIR_EXPR_SUB ||
           form == HIR_EXPR_MUL ||
           form == HIR_EXPR_MOD ||
           form == HIR_EXPR_DIV ||
           form == HIR_EXPR_AND ||
           form == HIR_EXPR_OR ||
           form == HIR_EXPR_BIT_OR ||
           form == HIR_EXPR_BIT_XOR ||
           form == HIR_EXPR_BIT_AND ||
           form == HIR_EXPR_SHL ||
           form == HIR_EXPR_SHR;
}

bool scalar_relational_const_operands_supported(uint left, uint right)
{
    // This pass does not bind semantic types, so only fold the range where
    // signed and unsigned scalar ordering agree.
    return left < I32_SIGN_BIT && right < I32_SIGN_BIT;
}

bool eval_scalar_binary_const(uint form, uint left, uint right, out uint value)
{
    value = 0u;
    if (form == HIR_EXPR_EQ)
    {
        value = left == right ? 1u : 0u;
        return true;
    }
    if (form == HIR_EXPR_NE)
    {
        value = left != right ? 1u : 0u;
        return true;
    }
    if (form == HIR_EXPR_LT)
    {
        if (!scalar_relational_const_operands_supported(left, right))
            return false;
        value = left < right ? 1u : 0u;
        return true;
    }
    if (form == HIR_EXPR_GT)
    {
        if (!scalar_relational_const_operands_supported(left, right))
            return false;
        value = left > right ? 1u : 0u;
        return true;
    }
    if (form == HIR_EXPR_LE)
    {
        if (!scalar_relational_const_operands_supported(left, right))
            return false;
        value = left <= right ? 1u : 0u;
        return true;
    }
    if (form == HIR_EXPR_GE)
    {
        if (!scalar_relational_const_operands_supported(left, right))
            return false;
        value = left >= right ? 1u : 0u;
        return true;
    }
    if (form == HIR_EXPR_ADD)
    {
        value = left + right;
        return true;
    }
    if (form == HIR_EXPR_SUB)
    {
        value = left - right;
        return true;
    }
    if (form == HIR_EXPR_MUL)
    {
        value = left * right;
        return true;
    }
    if (form == HIR_EXPR_MOD)
    {
        if (right == 0u || !scalar_relational_const_operands_supported(left, right))
            return false;
        value = left % right;
        return true;
    }
    if (form == HIR_EXPR_DIV)
    {
        if (right == 0u || !scalar_relational_const_operands_supported(left, right))
            return false;
        value = left / right;
        return true;
    }
    if (form == HIR_EXPR_AND)
    {
        value = (left != 0u && right != 0u) ? 1u : 0u;
        return true;
    }
    if (form == HIR_EXPR_OR)
    {
        value = (left != 0u || right != 0u) ? 1u : 0u;
        return true;
    }
    if (form == HIR_EXPR_BIT_OR)
    {
        value = left | right;
        return true;
    }
    if (form == HIR_EXPR_BIT_XOR)
    {
        value = left ^ right;
        return true;
    }
    if (form == HIR_EXPR_BIT_AND)
    {
        value = left & right;
        return true;
    }
    if (form == HIR_EXPR_SHL && right < 32u)
    {
        value = left << right;
        return true;
    }
    if (form == HIR_EXPR_SHR && right < 32u)
    {
        value = left >> right;
        return true;
    }
    return false;
}

bool literal_binary_atom_const_value(uint hir, out uint value)
{
    value = 0u;
    if (!valid_hir(hir))
        return false;

    HirPayload payload = compact_hir_payload[hir];
    uint form = payload.a;
    if (!scalar_binary_const_form(form))
        return false;

    uint left = 0u;
    uint right = 0u;
    if (!literal_atom_value(payload.b, left) ||
        !literal_atom_value(payload.c, right))
        return false;

    return eval_scalar_binary_const(form, left, right, value);
}

bool literal_nested_const_operand_value(uint hir, out uint value)
{
    if (literal_atom_value(hir, value))
        return true;
    return literal_binary_atom_const_value(hir, value);
}

bool literal_expr_value(uint hir, out uint value)
{
    value = 0u;
    if (literal_atom_value(hir, value))
        return true;

    if (!valid_hir(hir))
        return false;

    HirPayload payload = compact_hir_payload[hir];
    uint form = payload.a;
    if (!scalar_binary_const_form(form))
        return false;

    uint left = 0u;
    uint right = 0u;
    if (!literal_nested_const_operand_value(payload.b, left) ||
        !literal_nested_const_operand_value(payload.c, right))
        return false;

    return eval_scalar_binary_const(form, left, right, value);
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    uint hir = linear_dispatch_id(tid);
    if (hir == 0u)
    {
        x86_const_value_status[0u] = X86_CONST_VALUES_OK;
        x86_const_value_status[1u] = 0u;
        x86_const_value_status[2u] = INVALID;
    }

    if (!valid_hir(hir))
        return;

    HirPayload declaration = compact_hir_payload[hir];
    if (declaration.a != HIR_ITEM_KIND_CONST || !valid_token(declaration.b))
        return;

    uint value = 0u;
    if (!literal_expr_value(compact_const_value[hir], value))
        return;

    x86_const_value_record[declaration.b] = uint2(X86_CONST_VALUE_LITERAL, value);
}
