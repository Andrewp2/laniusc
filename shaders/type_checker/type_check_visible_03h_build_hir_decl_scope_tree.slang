// Build internal max-scope nodes for HIR declaration range queries.
//
// Scheduling contract:
// - Dispatch one level at a time after
//   type_check_visible_03g_build_hir_decl_scope_leaves.
// - Each node stores max(left_scope_end, right_scope_end).
// - This is a GPU-resident reduction over compact HIR declaration records.

struct Params
{
    uint decl_capacity;
    uint row_block_size;
    uint leaf_base;
    uint level_start;
    uint level_count;
    uint reserved0;
    uint reserved1;
    uint reserved2;
};

ConstantBuffer<Params> gParams;

RWStructuredBuffer<uint> hir_visible_decl_scope_tree;

static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

uint linear_thread_id(uint3 dtid)
{
    return dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint i = linear_thread_id(dtid);
    if (i >= gParams.level_count)
        return;

    uint node = gParams.level_start + i;
    hir_visible_decl_scope_tree[node] = max(
        hir_visible_decl_scope_tree[node * 2u],
        hir_visible_decl_scope_tree[node * 2u + 1u]);
}
