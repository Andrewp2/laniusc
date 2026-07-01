// Local prefix scan of x86 rodata fragment byte sizes.

import gpu_index;
import prefix_scan;

struct ScanParams
{
    uint n_items;
    uint n_blocks;
    uint scan_step;
    uint inst_capacity;
};

ConstantBuffer<ScanParams> gScan;

StructuredBuffer<uint> x86_rodata_size_by_node;
StructuredBuffer<uint> x86_rodata_status;

RWStructuredBuffer<uint> x86_rodata_scan_local_prefix;
RWStructuredBuffer<uint> x86_rodata_scan_block_sum;

static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;
static const uint X86_RODATA_OK = 1u;

uint linear_group_id(uint3 gid)
{
    return linear_group_id_2d(gid, MAX_GROUPS_X);
}

bool rodata_status_ok()
{
    return x86_rodata_status[0u] == X86_RODATA_OK &&
           x86_rodata_status[1u] == 0u;
}

uint active_node_count()
{
    return rodata_status_ok() ? min(x86_rodata_status[3u], gScan.n_items) : 0u;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 gid: SV_GroupID, uint3 ltid: SV_GroupThreadID)
{
    uint count = active_node_count();
    uint active_blocks = max(1u, (count + WG_SIZE - 1u) / WG_SIZE);
    uint block_i = linear_group_id(gid);
    if (block_i >= active_blocks)
        return;

    uint lane = ltid.x;
    uint node = block_i * WG_SIZE + lane;
    uint value = node < count ? x86_rodata_size_by_node[node] : 0u;
    uint inclusive = prefix_scan_u32_256(lane, value);

    if (node < count)
        x86_rodata_scan_local_prefix[node] = inclusive - value;

    if (lane == WG_SIZE - 1u)
        x86_rodata_scan_block_sum[block_i] = inclusive;
}
