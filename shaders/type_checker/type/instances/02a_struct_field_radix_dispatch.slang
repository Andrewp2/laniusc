// GPU-written dispatch covering every active struct-field key row.

import radix;

struct Params
{
    uint module_capacity;
    uint reserved;
    uint n_blocks;
    uint key_step;
};

ConstantBuffer<Params> gParams;
StructuredBuffer<uint> compact_field_count;
RWStructuredBuffer<uint> radix_dispatch_args;

static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

[shader("compute")]
[numthreads(1, 1, 1)]
void main()
{
    uint active_count = min(compact_field_count[0u], gParams.module_capacity);
    uint blocks = radix_active_block_count(
        active_count,
        gParams.n_blocks,
        WG_SIZE,
        gParams.n_blocks);
    blocks = max(blocks, 1u);
    radix_dispatch_args[0u] = min(blocks, MAX_GROUPS_X);
    radix_dispatch_args[1u] = (blocks + MAX_GROUPS_X - 1u) / MAX_GROUPS_X;
    radix_dispatch_args[2u] = 1u;
}
