// Apply of two independent counted scans, included by 03_apply.slang and
// 03_apply_dispatch.slang (block_carry.slang): adds each block's carries to
// the local prefixes, which the local pass wrote into the outputs, and
// writes both totals from workgroup 0.
//
// With SCAN_TOTAL_DISPATCH defined, workgroup 0 also writes the indirect
// dispatch arguments for each total (total_dispatch.slang); both use one
// capacity.

import scan.block_carry;
#ifdef SCAN_TOTAL_DISPATCH
import scan.total_dispatch;
#endif

struct Params
{
    uint n_items;
    uint n_blocks;
    uint min_items;
};

ConstantBuffer<Params> gScan;

StructuredBuffer<uint> scan_count;
StructuredBuffer<uint> scan_block_sum_left;
StructuredBuffer<uint> scan_block_sum_right;
RWStructuredBuffer<uint> scan_output_prefix_left;
RWStructuredBuffer<uint> scan_output_prefix_right;
RWStructuredBuffer<uint> scan_total_left;
RWStructuredBuffer<uint> scan_total_right;
#ifdef SCAN_TOTAL_DISPATCH
ConstantBuffer<ScanTotalDispatchParams> gTotalDispatch;
RWStructuredBuffer<uint> scan_total_dispatch_args_left;
RWStructuredBuffer<uint> scan_total_dispatch_args_right;
#endif

static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

uint active_items()
{
    return min(max(scan_count[0], gScan.min_items), gScan.n_items);
}

void counted_pair_apply(uint3 gid, uint3 ltid)
{
    uint block_i = gid.x + gid.y * MAX_GROUPS_X;
    uint count = active_items();
    uint blocks = (count + WG_SIZE - 1u) / WG_SIZE;
    if (block_i != 0u && block_i >= blocks)
        return;

    uint2 carry = block_carry_sum2(
        ltid.x, block_i == 0u ? blocks : block_i, scan_block_sum_left, scan_block_sum_right);
    if (block_i == 0u)
    {
        if (ltid.x == 0u)
        {
            scan_total_left[0] = carry.x;
            scan_total_right[0] = carry.y;
#ifdef SCAN_TOTAL_DISPATCH
            write_scan_total_dispatch(carry.x, gTotalDispatch, scan_total_dispatch_args_left);
            write_scan_total_dispatch(carry.y, gTotalDispatch, scan_total_dispatch_args_right);
#endif
        }
        return;
    }
    uint i = block_i * WG_SIZE + ltid.x;
    if (i < count)
    {
        scan_output_prefix_left[i] += carry.x;
        scan_output_prefix_right[i] += carry.y;
    }
}
