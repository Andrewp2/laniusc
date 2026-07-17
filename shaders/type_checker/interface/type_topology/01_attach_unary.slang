// Attach compact type arguments and unary operands to their dense HIR parents.

import atomics;
struct Params { uint hir_capacity; uint decl_capacity; };
struct HirCore { uint kind; uint parent; uint token_start; uint token_end; };
struct HirPayload { uint a; uint b; uint c; uint d; };
struct HirTypeArg { uint owner; uint value; uint ordinal; uint file_id; };
ConstantBuffer<Params> gParams;
StructuredBuffer<uint> compact_hir_count;
StructuredBuffer<HirCore> compact_hir_core;
StructuredBuffer<HirPayload> compact_hir_payload;
StructuredBuffer<uint> compact_type_arg_count;
StructuredBuffer<HirTypeArg> compact_type_args;
RWStructuredBuffer<uint> interface_type_parent;
RWStructuredBuffer<uint> interface_type_child_ordinal;
RWStructuredBuffer<uint> interface_status;

static const uint INVALID = 0xffffffffu;
static const uint HIR_TYPE = 5u;
static const uint HIR_TYPE_FORM_ARRAY = 2u;
static const uint HIR_TYPE_FORM_SLICE = 3u;
static const uint HIR_TYPE_FORM_REF = 4u;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;
uint linear_thread_id(uint3 dtid) { return dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE; }
uint active_hir_count() { return min(compact_hir_count[0u], gParams.hir_capacity); }
bool type_node(uint node) { return node < active_hir_count() && compact_hir_core[node].kind == HIR_TYPE; }
void attach(uint child, uint parent, uint ordinal, uint detail)
{
    if (!type_node(parent) || !type_node(child))
    {
        atomic_u32_or(interface_status, 0u, 128u);
        atomic_u32_min(interface_status, 1u, detail);
        return;
    }
    uint prior = atomic_u32_compare_exchange(interface_type_parent, child, INVALID, parent);
    uint prior_ordinal = atomic_u32_compare_exchange(
        interface_type_child_ordinal, child, INVALID, ordinal);
    if ((prior != INVALID && prior != parent) ||
        (prior_ordinal != INVALID && prior_ordinal != ordinal))
    {
        atomic_u32_or(interface_status, 0u, 128u);
        atomic_u32_min(interface_status, 1u, detail);
    }
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint row = linear_thread_id(dtid);
    if (row < min(compact_type_arg_count[0u], gParams.hir_capacity))
    {
        HirTypeArg arg = compact_type_args[row];
        attach(arg.value, arg.owner, arg.ordinal, row);
    }
    if (!type_node(row)) return;
    HirPayload payload = compact_hir_payload[row];
    if (payload.a == HIR_TYPE_FORM_ARRAY || payload.a == HIR_TYPE_FORM_SLICE ||
        payload.a == HIR_TYPE_FORM_REF)
        attach(payload.b, row, 0u, row);
}
