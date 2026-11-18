// Paired 256-way upsweep over packed parser offset block sums.

import prefix_scan;

struct Params
{
    uint n_items;
    uint n_blocks;
    uint level_divisor;
    uint level_offset;
    uint parent_divisor;
    uint parent_offset;
};
ConstantBuffer<Params> gHierarchy;
StructuredBuffer<uint> token_count;
RWStructuredBuffer<uint> sc_workspace;
RWStructuredBuffer<uint> emit_workspace;
RWStructuredBuffer<uint> sc_block_prefix;
RWStructuredBuffer<uint> emit_block_prefix;

static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;
uint linear_group_id(uint3 gid) { return gid.x + gid.y * MAX_GROUPS_X; }
uint active_pairs()
{
    uint active_tokens = token_count[0u] + 2u;
    return min(gHierarchy.n_items, active_tokens > 0u ? active_tokens - 1u : 0u);
}
uint active_blocks() { return (active_pairs() + WG_SIZE - 1u) / WG_SIZE; }
uint level_count()
{
    return (active_blocks() + gHierarchy.level_divisor - 1u) / gHierarchy.level_divisor;
}
uint hierarchy_row(uint offset, uint row) { return gHierarchy.n_blocks + offset + row; }

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 gid: SV_GroupID, uint3 ltid: SV_GroupThreadID)
{
    uint group = linear_group_id(gid);
    uint count = level_count();
    uint row = group * WG_SIZE + ltid.x;
    uint2 value = uint2(0u, 0u);
    if (row < count)
    {
        if (gHierarchy.level_divisor == 1u)
            value = uint2(sc_workspace[row], emit_workspace[row]);
        else
            value = uint2(
                sc_workspace[hierarchy_row(gHierarchy.level_offset, row)],
                emit_workspace[hierarchy_row(gHierarchy.level_offset, row)]);
    }
    uint2 inclusive = prefix_scan_u32x2_256(ltid.x, value);
    if (row < count)
    {
        if (gHierarchy.level_divisor == 1u)
        {
            sc_block_prefix[row] = inclusive.x;
            emit_block_prefix[row] = inclusive.y;
        }
        else
        {
            sc_workspace[hierarchy_row(gHierarchy.level_offset, row)] = inclusive.x;
            emit_workspace[hierarchy_row(gHierarchy.level_offset, row)] = inclusive.y;
        }
    }
    if (gHierarchy.parent_divisor != 0u && ltid.x + 1u == WG_SIZE)
    {
        sc_workspace[hierarchy_row(gHierarchy.parent_offset, group)] = inclusive.x;
        emit_workspace[hierarchy_row(gHierarchy.parent_offset, group)] = inclusive.y;
    }
}
