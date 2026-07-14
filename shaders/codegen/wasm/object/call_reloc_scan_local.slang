// Compact marked Wasm call immediates with a workgroup-local prefix scan.

import gpu_index;
import prefix_scan;

struct ScanParams
{
    uint n_items;
    uint n_blocks;
    uint scan_step;
    uint out_capacity;
};

ConstantBuffer<ScanParams> gScan;

StructuredBuffer<uint> body_words;
RWStructuredBuffer<uint> call_reloc_local_prefix;
RWStructuredBuffer<uint> call_reloc_block_sum;

static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;
static const uint CALL_RELOC_MARKER = 0x100u;

uint linear_group_id(uint3 gid)
{
    return gid.x + gid.y * MAX_GROUPS_X;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 gid: SV_GroupID, uint3 ltid: SV_GroupThreadID)
{
    uint block_i = linear_group_id(gid);
    if (block_i >= gScan.n_blocks)
        return;

    uint lane = ltid.x;
    uint i = block_i * WG_SIZE + lane;
    uint marked = i < gScan.n_items && (body_words[i] & CALL_RELOC_MARKER) != 0u
        ? 1u
        : 0u;
    uint inclusive = prefix_scan_u32_256(lane, marked);

    if (i < gScan.n_items)
        call_reloc_local_prefix[i] = inclusive - marked;

    if (lane == WG_SIZE - 1u)
        call_reloc_block_sum[block_i] = inclusive;
}
