// Count the hidden declarations (02_hidden) of each 256-row block of local
// declarations. interface_hidden_block_count[0] keeps the public count that
// 04_hidden_publish places them after, and [1 + block] the block's count.

StructuredBuffer<uint> decl_count_out;
StructuredBuffer<uint> decl_kind;
StructuredBuffer<uint> decl_parent_type_decl;
StructuredBuffer<uint> interface_public_decl_count;
StructuredBuffer<uint> interface_public_decl_index_by_local;
RWStructuredBuffer<uint> interface_hidden_block_count;

#include "hidden_flag.slang"

groupshared uint g_count;

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 group: SV_GroupID, uint lane: SV_GroupIndex)
{
    uint block = group.x + group.y * MAX_GROUPS_X;
    uint decls = active_decls();
    if (block * LANES >= max(decls, 1u)) return;
    uint public_count = interface_public_decl_count[0u];
    if (lane == 0u) g_count = 0u;
    GroupMemoryBarrierWithGroupSync();
    if (hidden_flag(block * LANES + lane, decls, public_count)) InterlockedAdd(g_count, 1u);
    GroupMemoryBarrierWithGroupSync();
    if (lane == 0u)
    {
        interface_hidden_block_count[1u + block] = g_count;
        if (block == 0u) interface_hidden_block_count[0u] = public_count;
    }
}
