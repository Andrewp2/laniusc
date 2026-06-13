// Local prefix scan of selected x86 instruction byte sizes.
//
// This mirrors the node instruction local scan, but bounds the final block by
// the GPU-produced selected instruction count so tail lanes read zero without a
// capacity-wide clear of the reused x86_inst_size buffer.

import prefix_scan;

struct ScanParams
{
    uint n_items;
    uint n_blocks;
    uint scan_step;
    uint inst_capacity;
};

ConstantBuffer<ScanParams> gScan;

StructuredBuffer<uint> select_status;
StructuredBuffer<uint> x86_inst_size;

RWStructuredBuffer<uint> x86_text_scan_local_prefix;
RWStructuredBuffer<uint> x86_text_scan_block_sum;

static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;
static const uint X86_SELECT_OK = 1u;

uint linear_group_id(uint3 gid)
{
    return gid.x + gid.y * MAX_GROUPS_X;
}

uint selected_inst_count()
{
    bool ok = select_status[0u] == X86_SELECT_OK &&
              select_status[1u] == 0u &&
              select_status[3u] <= gScan.inst_capacity;
    return ok ? min(select_status[3u], gScan.inst_capacity) : 0u;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 gid: SV_GroupID, uint3 ltid: SV_GroupThreadID)
{
    uint count = selected_inst_count();
    uint active_blocks = max(1u, (count + WG_SIZE - 1u) / WG_SIZE);
    uint block_i = linear_group_id(gid);
    if (block_i >= active_blocks)
        return;

    uint lane = ltid.x;
    uint i = block_i * WG_SIZE + lane;
    uint value = i < count ? x86_inst_size[i] : 0u;
    uint inclusive = prefix_scan_u32_256(lane, value);

    if (i < count)
        x86_text_scan_local_prefix[i] = inclusive - value;

    if (lane == WG_SIZE - 1u)
        x86_text_scan_block_sum[block_i] = inclusive;
}
