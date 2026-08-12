// GPU-written dispatch arguments for a compact radix-sort domain.
//
// Histogram and scatter scale with the GPU-written active count, not with the
// allocation capacity.

import radix;

struct Params
{
    uint item_capacity;
    uint reserved;
    uint max_blocks;
    uint key_step;
};

ConstantBuffer<Params> gParams;

StructuredBuffer<uint> name_count_in;
RWStructuredBuffer<uint> radix_dispatch_args;

static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;
static const uint MAX_RADIX_BLOCKS = 4096u;

uint active_item_count()
{
    return min(name_count_in[0], gParams.item_capacity);
}

[shader("compute")]
[numthreads(1, 1, 1)]
void main()
{
    uint blocks = radix_active_block_count(
        active_item_count(),
        gParams.max_blocks,
        WG_SIZE,
        MAX_RADIX_BLOCKS);
    blocks = max(blocks, 1u);

    radix_dispatch_args[0u] = min(blocks, MAX_GROUPS_X);
    radix_dispatch_args[1u] = (blocks + MAX_GROUPS_X - 1u) / MAX_GROUPS_X;
    radix_dispatch_args[2u] = 1u;
}
