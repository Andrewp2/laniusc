// Parallel scan over preorder tree prefix block sums.

import gpu_index;
import prefix_scan;

struct Params
{
    uint n;
    uint uses_ll1;
    uint n_node_blocks;
    uint n_prefix_blocks;
    uint scan_step;
};
ConstantBuffer<Params> gTree;

StructuredBuffer<int> block_sum;
StructuredBuffer<int> prefix_in;
RWStructuredBuffer<int> prefix_out;
RWStructuredBuffer<int> block_prefix;

static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

uint linear_thread_id(uint3 dtid)
{
    return linear_thread_id_2d(dtid, MAX_GROUPS_X, WG_SIZE);
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint i = linear_thread_id(dtid);
    uint n_blocks = gTree.n_node_blocks;
    if (i >= n_blocks)
        return;

    if (gTree.scan_step == 0u)
    {
        prefix_out[i] = block_sum[i];
        return;
    }

    if (gTree.scan_step < n_blocks)
    {
        prefix_out[i] = block_prefix_scan_step<int, PrefixScanI32Add>(
            i,
            gTree.scan_step,
            block_sum,
            prefix_in);
        return;
    }

    block_prefix[i] = exclusive_block_prefix<int, PrefixScanI32Add>(i, prefix_in);
}
