// Block-prefix scan for compact virtual use-edge scatter.

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

StructuredBuffer<uint> x86_virtual_inst_status;
StructuredBuffer<uint> x86_virtual_use_scan_block_sum;
StructuredBuffer<uint> x86_virtual_use_scan_block_prefix_in;

RWStructuredBuffer<uint> x86_virtual_use_scan_block_prefix_out;

static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;
static const uint X86_VIRTUAL_INST_OK = 1u;

uint linear_thread_id(uint3 dtid)
{
    return linear_thread_id_2d(dtid, MAX_GROUPS_X, WG_SIZE);
}

uint virtual_inst_count()
{
    bool ok = x86_virtual_inst_status[0u] == X86_VIRTUAL_INST_OK &&
              x86_virtual_inst_status[1u] == 0u &&
              x86_virtual_inst_status[3u] <= gScan.inst_capacity;
    return ok ? min(x86_virtual_inst_status[3u], gScan.inst_capacity) : 0u;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint i = linear_thread_id(dtid);
    uint count = virtual_inst_count();
    uint active_blocks = max(1u, (count + WG_SIZE - 1u) / WG_SIZE);
    if (i >= active_blocks)
        return;

    if (gScan.scan_step >= active_blocks && gScan.scan_step != 0u)
    {
        x86_virtual_use_scan_block_prefix_out[i] =
            x86_virtual_use_scan_block_prefix_in[i];
        return;
    }

    x86_virtual_use_scan_block_prefix_out[i] =
        block_prefix_scan_step<uint, PrefixScanU32Add>(
            i,
            gScan.scan_step,
            x86_virtual_use_scan_block_sum,
            x86_virtual_use_scan_block_prefix_in);
}
