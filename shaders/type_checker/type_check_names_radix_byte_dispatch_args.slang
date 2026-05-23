// GPU-written dispatch arguments for each fixed name-radix byte pass.
//
// The host records the fixed 64-byte schedule so command recording does not
// depend on a readback of max name length. This pass writes zero-work indirect
// dispatch records for inactive high byte offsets and keeps slot zero as the
// compact-name dispatch used by downstream dedup/id assignment passes.

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
StructuredBuffer<uint> name_max_len_in;
RWStructuredBuffer<uint> radix_dispatch_args;

static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;
static const uint MAX_RADIX_BLOCKS = 4096u;
static const uint NAME_RADIX_MAX_BYTES = 64u;
static const uint RADIX_BUCKETS = RADIX_U8_SENTINEL_BUCKETS;

uint active_name_count()
{
    return min(name_count_in[0], gParams.name_count);
}

void write_dispatch_args(uint base, uint blocks)
{
    if (blocks == 0u)
    {
        radix_dispatch_args[base + 0u] = 0u;
        radix_dispatch_args[base + 1u] = 0u;
        radix_dispatch_args[base + 2u] = 0u;
        return;
    }

    radix_dispatch_args[base + 0u] = min(blocks, MAX_GROUPS_X);
    radix_dispatch_args[base + 1u] = max(1u, (blocks + MAX_GROUPS_X - 1u) / MAX_GROUPS_X);
    radix_dispatch_args[base + 2u] = 1u;
}

[shader("compute")]
[numthreads(64, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    uint lane = tid.x;
    uint active_blocks = radix_active_block_count(
        active_name_count(),
        gParams.n_blocks,
        WG_SIZE,
        MAX_RADIX_BLOCKS);
    active_blocks = max(active_blocks, 1u);

    if (lane == 0u)
        write_dispatch_args(0u, active_blocks);

    if (lane >= NAME_RADIX_MAX_BYTES)
        return;

    uint byte_offset = (NAME_RADIX_MAX_BYTES - 1u) - lane;
    bool active = byte_offset < name_max_len_in[0u];
    write_dispatch_args((1u + lane) * 3u, active ? active_blocks : 0u);
    write_dispatch_args((1u + NAME_RADIX_MAX_BYTES + lane) * 3u, active ? RADIX_BUCKETS : 0u);
    write_dispatch_args((1u + 2u * NAME_RADIX_MAX_BYTES + lane) * 3u, active ? 1u : 0u);
}
