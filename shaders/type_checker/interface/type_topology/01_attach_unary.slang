// Attach array, slice, and reference operands to their direct type parent.

import atomics;

struct Params { uint hir_capacity; uint decl_capacity; };
ConstantBuffer<Params> gParams;
StructuredBuffer<uint> hir_status;
StructuredBuffer<uint> hir_kind;
StructuredBuffer<uint> hir_type_form;
StructuredBuffer<uint> hir_type_value_node;
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
uint active_hir_count() { return min(hir_status[5u], gParams.hir_capacity); }
bool type_node(uint node) { return node < active_hir_count() && hir_kind[node] == HIR_TYPE; }

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint parent = linear_thread_id(dtid);
    if (!type_node(parent))
        return;
    uint form = hir_type_form[parent];
    if (form != HIR_TYPE_FORM_ARRAY && form != HIR_TYPE_FORM_SLICE && form != HIR_TYPE_FORM_REF)
        return;
    uint child = hir_type_value_node[parent];
    if (!type_node(child))
    {
        atomic_u32_or(interface_status, 0u, 128u);
        atomic_u32_min(interface_status, 1u, parent);
        return;
    }
    uint prior = atomic_u32_compare_exchange(interface_type_parent, child, INVALID, parent);
    if (prior != INVALID && prior != parent)
    {
        atomic_u32_or(interface_status, 0u, 128u);
        atomic_u32_min(interface_status, 1u, child);
    }
    else
    {
        uint prior_ordinal = atomic_u32_compare_exchange(
            interface_type_child_ordinal, child, INVALID, 0u);
        if (prior_ordinal != INVALID && prior_ordinal != 0u)
        {
            atomic_u32_or(interface_status, 0u, 128u);
            atomic_u32_min(interface_status, 1u, child);
        }
    }
}
