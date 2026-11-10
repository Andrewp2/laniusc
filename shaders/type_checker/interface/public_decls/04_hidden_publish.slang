// Give the hidden declarations (02_hidden) their interface indices: after
// the public partition, in local declaration order. Each 256-row block sums
// the counts of the blocks before it (03_hidden_count) and scans its own
// flags, so every block publishes independently.
import status;

StructuredBuffer<uint> decl_count_out;
StructuredBuffer<uint> decl_kind;
StructuredBuffer<uint> decl_hir_node;
StructuredBuffer<uint> decl_parent_type_decl;
StructuredBuffer<uint> interface_hidden_block_count;
RWStructuredBuffer<uint> interface_public_decl_count;
RWStructuredBuffer<uint> interface_public_decl_local_id;
RWStructuredBuffer<uint> interface_public_decl_index_by_local;
RWStructuredBuffer<uint> interface_public_decl_index_by_hir;
RWStructuredBuffer<uint> status;

#include "hidden_flag.slang"

static const uint ERR_NAME_LIMIT = 11u;
// "HIDE": hidden indices overflowed the interface declaration table.
static const uint HIDDEN_LIMIT_DETAIL = 0x48494445u;

groupshared uint g_before;
groupshared uint g_scan[LANES];

uint hir_capacity()
{
    uint count; uint stride;
    interface_public_decl_index_by_hir.GetDimensions(count, stride);
    return count;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 group: SV_GroupID, uint lane: SV_GroupIndex)
{
    uint block = group.x + group.y * MAX_GROUPS_X;
    uint decls = active_decls();
    if (block * LANES >= max(decls, 1u)) return;
    uint blocks = (decls + LANES - 1u) / LANES;
    uint public_count = interface_hidden_block_count[0u];
    if (lane == 0u) g_before = 0u;
    GroupMemoryBarrierWithGroupSync();
    uint before = 0u;
    for (uint prior = lane; prior < block; prior += LANES)
        before += interface_hidden_block_count[1u + prior];
    InterlockedAdd(g_before, before);

    uint local = block * LANES + lane;
    uint flag = hidden_flag(local, decls, public_count) ? 1u : 0u;
    g_scan[lane] = flag;
    GroupMemoryBarrierWithGroupSync();
    [unroll]
    for (uint step = 1u; step < LANES; step <<= 1u)
    {
        uint add = lane >= step ? g_scan[lane - step] : 0u;
        GroupMemoryBarrierWithGroupSync();
        g_scan[lane] += add;
        GroupMemoryBarrierWithGroupSync();
    }
    uint capacity = decl_capacity();
    uint next = public_count + g_before;
    if (flag != 0u)
    {
        uint persisted = next + g_scan[lane] - 1u;
        if (persisted < capacity)
        {
            interface_public_decl_local_id[persisted] = local;
            interface_public_decl_index_by_local[local] = persisted;
            uint hir = decl_hir_node[local];
            if (decl_kind[local] != KIND_ENUM_VARIANT && hir < hir_capacity())
                interface_public_decl_index_by_hir[hir] = persisted;
        }
        else
        {
            interface_public_decl_index_by_local[local] = INVALID;
            record_min_token_error(status, 0u, ERR_NAME_LIMIT, HIDDEN_LIMIT_DETAIL);
        }
    }
    if (block + 1u == blocks && lane == LANES - 1u)
        interface_public_decl_count[0u] = min(next + g_scan[LANES - 1u], capacity);
}
