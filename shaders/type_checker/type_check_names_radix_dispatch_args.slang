// GPU-written dispatch arguments for compact-name radix passes.
//
// The name extractor writes name_count_out[0] after compacting token lexemes and
// language symbols. Radix histogram/scatter should scale with that compact count,
// not with the source-byte-sized token buffer capacity.

import radix;

struct Params
{
    uint name_count;
    uint source_len;
    uint n_blocks;
    uint radix_byte_offset;
};

ConstantBuffer<Params> gParams;

StructuredBuffer<uint> name_count_in;
RWStructuredBuffer<uint> radix_dispatch_args;

static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;
static const uint MAX_RADIX_BLOCKS = 1024u;

uint active_name_count()
{
    return min(name_count_in[0], gParams.name_count);
}

[shader("compute")]
[numthreads(1, 1, 1)]
void main()
{
    uint blocks = radix_active_block_count(
        active_name_count(),
        gParams.n_blocks,
        WG_SIZE,
        MAX_RADIX_BLOCKS);
    blocks = max(blocks, 1u);

    radix_dispatch_args[0u] = min(blocks, MAX_GROUPS_X);
    radix_dispatch_args[1u] = (blocks + MAX_GROUPS_X - 1u) / MAX_GROUPS_X;
    radix_dispatch_args[2u] = 1u;
}
