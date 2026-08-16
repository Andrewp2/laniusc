// Publish pointer-jumped generic type-argument owners, ordinals, and links.

import atomics;

struct Params
{
    uint n;
    uint uses_status_count;
    uint retain_debug_rows;
};

ConstantBuffer<Params> gHirType;

StructuredBuffer<uint> tree_count_status;
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
static const uint HIR_PATH_EXPR = 33u;

uint linear_thread_id(uint3 dtid)
{
    return dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE;
}

uint active_node_count()
{
    return gHirType.uses_status_count != 0u ? min(gHirType.n, tree_count_status[5u]) : gHirType.n;
}

bool valid_node(uint node)
{
    return node != INVALID && node < active_node_count();
}

bool valid_type_arg_owner(uint node)
{
    return valid_node(node) &&
           (hir_kind[node] == HIR_TYPE || hir_kind[node] == HIR_PATH_EXPR);
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    // Canonical HIR is produced directly from owner/rank below; this pass is
    // now only the legacy raw-table projection used by parser debug readback.
    if (gHirType.retain_debug_rows == 0u)
        return;

    uint node = linear_thread_id(dtid);
    if (node >= gHirType.n || !valid_node(node) || hir_kind[node] != HIR_TYPE)
        return;

    uint owner = hir_type_arg_owner_a[node];
    if (!valid_type_arg_owner(owner))
        return;

    uint ordinal = hir_type_arg_rank_a[node];
    uint previous = hir_type_arg_previous[node];
    atomic_u32_min(hir_type_arg_start, owner, node);
    atomic_u32_max(hir_type_arg_count, owner, ordinal + 1u);
    if (valid_node(previous) && hir_kind[previous] == HIR_TYPE)
        hir_type_arg_next[previous] = node;
}
