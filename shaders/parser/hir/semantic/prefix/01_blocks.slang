// Prefix scan over semantic-HIR block sums.

import prefix_scan;

struct Params
{
    uint n_blocks;
    uint scan_step;
};

ConstantBuffer<Params> gHirSemanticBlocks;

StructuredBuffer<uint> hir_semantic_block_sum;
StructuredBuffer<uint> hir_semantic_block_prefix_in;
RWStructuredBuffer<uint> hir_semantic_block_prefix_out;

static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

uint linear_thread_id(uint3 dtid)
{
    return dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint block_i = linear_thread_id(dtid);
    if (block_i >= gHirSemanticBlocks.n_blocks)
        return;

    hir_semantic_block_prefix_out[block_i] =
        block_prefix_scan_step<uint, PrefixScanU32Add>(
            block_i,
            gHirSemanticBlocks.scan_step,
            hir_semantic_block_sum,
            hir_semantic_block_prefix_in);
}
