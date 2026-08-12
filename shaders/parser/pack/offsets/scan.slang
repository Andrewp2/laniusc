// Local paired exclusive scan for packed parser stream offsets.

import prefix_scan;

struct ActionHeader
{
    uint push_len;
    uint emit_len;
    uint pop_tag;
    uint pop_count;
};

struct Params { uint n_pairs; uint n_blocks; };
ConstantBuffer<Params> gParams;
StructuredBuffer<uint> token_count;
StructuredBuffer<ActionHeader> out_headers;
RWStructuredBuffer<uint> sc_offsets;
RWStructuredBuffer<uint> emit_offsets;
RWStructuredBuffer<uint> sc_workspace;
RWStructuredBuffer<uint> emit_workspace;

static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

uint linear_group_id(uint3 gid) { return gid.x + gid.y * MAX_GROUPS_X; }
uint active_pairs()
{
    uint active_tokens = token_count[0u] + 2u;
    return min(gParams.n_pairs, active_tokens > 0u ? active_tokens - 1u : 0u);
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 gid: SV_GroupID, uint3 ltid: SV_GroupThreadID)
{
    uint block = linear_group_id(gid);
    uint row = block * WG_SIZE + ltid.x;
    uint count = active_pairs();
    if (block >= (count + WG_SIZE - 1u) / WG_SIZE)
        return;

    uint2 value = uint2(0u, 0u);
    if (row < count)
    {
        ActionHeader header = out_headers[row];
        value = uint2(header.push_len + header.pop_count, header.emit_len);
    }
    uint2 inclusive = prefix_scan_u32x2_256(ltid.x, value);
    if (row < count)
    {
        uint2 exclusive = inclusive - value;
        sc_offsets[row] = exclusive.x;
        emit_offsets[row] = exclusive.y;
    }
    if (ltid.x == WG_SIZE - 1u)
    {
        sc_workspace[block] = inclusive.x;
        emit_workspace[block] = inclusive.y;
    }
}
