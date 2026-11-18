// Paired carry propagation for one packed parser offset hierarchy level.

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
uint linear_thread_id(uint3 dtid) { return dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE; }
uint active_pairs()
{
    uint active_tokens = token_count[0u] + 2u;
    return min(gHierarchy.n_items, active_tokens > 0u ? active_tokens - 1u : 0u);
}
uint active_blocks() { return (active_pairs() + WG_SIZE - 1u) / WG_SIZE; }
uint hierarchy_row(uint offset, uint row) { return gHierarchy.n_blocks + offset + row; }

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint row = linear_thread_id(dtid);
    uint count = (active_blocks() + gHierarchy.level_divisor - 1u) / gHierarchy.level_divisor;
    if (row >= count)
        return;
    uint group = row / WG_SIZE;
    uint2 carry = group == 0u
        ? uint2(0u, 0u)
        : uint2(
            sc_workspace[hierarchy_row(gHierarchy.parent_offset, group - 1u)],
            emit_workspace[hierarchy_row(gHierarchy.parent_offset, group - 1u)]);
    if (gHierarchy.level_divisor == 1u)
    {
        sc_block_prefix[row] += carry.x;
        emit_block_prefix[row] += carry.y;
    }
    else
    {
        sc_workspace[hierarchy_row(gHierarchy.level_offset, row)] += carry.x;
        emit_workspace[hierarchy_row(gHierarchy.level_offset, row)] += carry.y;
    }
}
