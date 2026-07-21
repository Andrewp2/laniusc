// Project compact constant declarations into the token-indexed value table.

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

RWStructuredBuffer<uint2> wasm_const_value_record;

static const uint INVALID = 0xffffffffu;
static const uint DISPATCH_X_STRIDE = 16776960u;
static const uint HIR_ITEM_KIND_CONST = 3u;
static const uint HIR_EXPR_INT = 3u;
static const uint HIR_EXPR_TRUE = 4u;
static const uint HIR_EXPR_FALSE = 5u;
static const uint HIR_EXPR_NOT = 6u;
static const uint HIR_EXPR_NEG = 13u;
static const uint HIR_EXPR_FLOAT = 27u;
static const uint WASM_CONST_VALUE_LITERAL = 1u;

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

bool literal_expr_value(uint hir, out uint value)
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
            ? inner ^ 0x80000000u
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

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    uint hir = linear_dispatch_id(tid);
    if (!valid_hir(hir))
        return;

    HirPayload declaration = compact_hir_payload[hir];
    if (declaration.a != HIR_ITEM_KIND_CONST || !valid_token(declaration.b))
        return;

    uint value = 0u;
    if (!literal_expr_value(compact_const_value[hir], value))
        return;
    wasm_const_value_record[declaration.b] = uint2(WASM_CONST_VALUE_LITERAL, value);
}
