// Publish pointer-jumped generic type-argument owners, ordinals, and links.

import atomics;

struct Params
{
    uint n;
    uint uses_ll1;
};

ConstantBuffer<Params> gHirType;

StructuredBuffer<uint> ll1_status;
StructuredBuffer<uint> hir_kind;
StructuredBuffer<uint> hir_type_arg_owner_a;
StructuredBuffer<uint> hir_type_arg_rank_a;
StructuredBuffer<uint> hir_type_arg_previous;

RWStructuredBuffer<uint> hir_type_arg_start;
RWStructuredBuffer<uint> hir_type_arg_count;
RWStructuredBuffer<uint> hir_type_arg_next;

static const uint INVALID = 0xffffffffu;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

static const uint HIR_TYPE = 5u;

uint linear_thread_id(uint3 dtid)
{
    return dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE;
}

uint active_node_count()
{
    return gHirType.uses_ll1 != 0u ? min(gHirType.n, ll1_status[5u]) : gHirType.n;
}

bool valid_node(uint node)
{
    return node != INVALID && node < active_node_count();
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint node = linear_thread_id(dtid);
    if (node >= gHirType.n || !valid_node(node) || hir_kind[node] != HIR_TYPE)
        return;

    uint owner = hir_type_arg_owner_a[node];
    if (!valid_node(owner))
        return;

    uint ordinal = hir_type_arg_rank_a[node];
    uint previous = hir_type_arg_previous[node];
    atomic_u32_min(hir_type_arg_start, owner, node);
    atomic_u32_max(hir_type_arg_count, owner, ordinal + 1u);
    if (valid_node(previous))
        hir_type_arg_next[previous] = node;
}
