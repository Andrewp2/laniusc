// Build leaf aggregates for HIR declaration scope-end range queries.
//
// Scheduling contract:
// - Dispatch after HIR declaration key radix sorting is complete.
// - Each leaf stores the maximum scope_end for a small sorted-row block.
// - The resulting tree lets HIR name resolution find the latest same-name
//   declaration whose scope still contains the use without scanning all HIR
//   declaration records.

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

StructuredBuffer<uint> hir_visible_decl_count_out;
StructuredBuffer<uint> hir_visible_decl_scope_end;
StructuredBuffer<uint> hir_visible_decl_key_order;

RWStructuredBuffer<uint> hir_visible_decl_scope_tree;

static const uint INVALID = 0xffffffffu;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

uint linear_thread_id(uint3 dtid)
{
    return dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE;
}

uint active_decl_count()
{
    return min(hir_visible_decl_count_out[0], gParams.decl_capacity);
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint leaf = linear_thread_id(dtid);
    if (leaf >= gParams.leaf_base || gParams.row_block_size == 0u)
        return;

    uint active_count = active_decl_count();
    uint start = leaf * gParams.row_block_size;
    uint end = min(active_count, start + gParams.row_block_size);
    uint max_scope_end = 0u;

    [loop]
    for (uint row = start; row < end; row += 1u)
    {
        uint decl_i = hir_visible_decl_key_order[row];
        if (decl_i != INVALID && decl_i < gParams.decl_capacity)
            max_scope_end = max(max_scope_end, hir_visible_decl_scope_end[decl_i]);
    }

    hir_visible_decl_scope_tree[gParams.leaf_base + leaf] = max_scope_end;
}
