// x86_64 function instruction-count local scan.
//
// One workgroup scans one 256-slot window of the ordered instruction-count
// input. This mirrors the reusable GPU scan shape used by name/module passes.

struct ScanParams
{
    uint n_items;
    uint n_blocks;
    uint scan_step;
};

ConstantBuffer<ScanParams> gScan;

StructuredBuffer<uint> x86_func_inst_scan_input;
RWStructuredBuffer<uint> x86_func_inst_scan_local_prefix;
RWStructuredBuffer<uint> x86_func_inst_scan_block_sum;

static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

groupshared uint scan_values[256];

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
    uint value = i < gScan.n_items ? x86_func_inst_scan_input[i] : 0u;

    scan_values[lane] = value;
    GroupMemoryBarrierWithGroupSync();

    [unroll]
    for (uint offset = 1u; offset < WG_SIZE; offset <<= 1u)
    {
        uint addend = lane >= offset ? scan_values[lane - offset] : 0u;
        GroupMemoryBarrierWithGroupSync();
        scan_values[lane] += addend;
        GroupMemoryBarrierWithGroupSync();
    }

    if (i < gScan.n_items)
        x86_func_inst_scan_local_prefix[i] = scan_values[lane] - value;

    if (lane == WG_SIZE - 1u)
        x86_func_inst_scan_block_sum[block_i] = scan_values[lane];
}
