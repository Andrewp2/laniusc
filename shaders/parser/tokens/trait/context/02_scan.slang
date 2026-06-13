// Block scan for trait-body syntax context events.

import gpu_index;
import prefix_scan;

struct Params
{
    uint n_tokens;
    uint n_blocks;
    uint scan_step;
};

ConstantBuffer<Params> gParams;

StructuredBuffer<uint> trait_context_event_block;
StructuredBuffer<uint> trait_context_event_prefix_in;

RWStructuredBuffer<uint> trait_context_event_prefix_out;
RWStructuredBuffer<uint> trait_context_event_block_prefix;

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
    if (i >= gParams.n_blocks)
        return;

    if (gParams.scan_step == 0u)
    {
        trait_context_event_prefix_out[i] = trait_context_event_block[i];
        return;
    }

    if (gParams.scan_step < gParams.n_blocks)
    {
        trait_context_event_prefix_out[i] = block_prefix_scan_step<uint, PrefixScanU32Max>(
            i,
            gParams.scan_step,
            trait_context_event_block,
            trait_context_event_prefix_in);
        return;
    }

    trait_context_event_block_prefix[i] = exclusive_block_prefix<uint, PrefixScanU32Max>(
        i,
        trait_context_event_prefix_in);
}
