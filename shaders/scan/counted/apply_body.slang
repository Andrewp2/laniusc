// Apply of a GPU-counted u32 exclusive scan, included by 02_apply.slang and
// 02_apply_dispatch.slang: adds each block's carry to the local prefixes and
// writes the total. The carry is the sum of the earlier blocks' sums
// (block_carry.slang); workgroup 0 sums every block for the total.
//
// With SCAN_TOTAL_DISPATCH defined, workgroup 0 also writes the indirect
// dispatch arguments for the total, as type_checker/conditions/write_count_dispatch_args
// would from the total buffer.

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
StructuredBuffer<uint> scan_local_prefix;
StructuredBuffer<uint> scan_block_sum;
RWStructuredBuffer<uint> scan_output_prefix;
RWStructuredBuffer<uint> scan_total;
#ifdef SCAN_TOTAL_DISPATCH
ConstantBuffer<ScanTotalDispatchParams> gTotalDispatch;
RWStructuredBuffer<uint> scan_total_dispatch_args;
#endif

static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

uint active_items()
{
    return min(max(scan_count[0], gScan.min_items), gScan.n_items);
}

void counted_apply(uint3 gid, uint3 ltid)
{
    uint block_i = gid.x + gid.y * MAX_GROUPS_X;
    uint count = active_items();
    uint blocks = (count + WG_SIZE - 1u) / WG_SIZE;
    if (block_i != 0u && block_i >= blocks)
        return;

    uint carry = block_carry_sum(ltid.x, block_i == 0u ? blocks : block_i, scan_block_sum);
    if (block_i == 0u)
    {
        if (ltid.x == 0u)
        {
            scan_total[0] = carry;
#ifdef SCAN_TOTAL_DISPATCH
            write_scan_total_dispatch(carry, gTotalDispatch, scan_total_dispatch_args);
#endif
        }
        carry = 0u;
    }
    uint i = block_i * WG_SIZE + ltid.x;
    if (i < count)
        scan_output_prefix[i] = carry + scan_local_prefix[i];
}
