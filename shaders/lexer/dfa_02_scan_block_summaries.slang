// Multi-round inclusive scan over per-block function vectors.
// Result after last round is inclusive prefix for each block.

#define N_STATES 32
#define BLOCK_WIDTH 128u
static const uint MAX_GROUPS_PER_DIM = 65535u;

struct Params
{
    uint n;
    uint n_states;
    uint start_state;
};
ConstantBuffer<Params> gParams;

struct Scan
{
    uint stride;
    uint use_ping_as_src;
};
ConstantBuffer<Scan> gScan;

RWStructuredBuffer<uint> block_ping; // nb * N_STATES
RWStructuredBuffer<uint> block_pong; // nb * N_STATES

[shader("compute")]
[numthreads(N_STATES, 1, 1)]
void dfa_02_scan_block_summaries(uint3 local_id: SV_GroupThreadID,
                                 uint3 global_id: SV_DispatchThreadID,
                                 uint3 group_id: SV_GroupID)
{
    const uint nb = (gParams.n + (BLOCK_WIDTH - 1u)) / BLOCK_WIDTH;

    // 2D tiling support:
    // (gx, gy) = (min(nb, 65535), ceil(nb / 65535)).
    const uint groups_x = (nb < MAX_GROUPS_PER_DIM) ? nb : MAX_GROUPS_PER_DIM;

    const uint i = group_id.y * groups_x + group_id.x; // 1 group per block
    const uint s = local_id.x;                         // state lane [0..N_STATES)

    if (i >= nb || s >= N_STATES)
        return;

    const uint aBase = (i - gScan.stride) * N_STATES;
    const uint bBase = i * N_STATES;
    const uint dBase = i * N_STATES;

    if (gScan.use_ping_as_src != 0)
    {
        if (i >= gScan.stride)
        {
            const uint a = block_ping[aBase + s];
            block_pong[dBase + s] = block_ping[bBase + a];
        }
        else
        {
            block_pong[dBase + s] = block_ping[bBase + s];
        }
    }
    else
    {
        if (i >= gScan.stride)
        {
            const uint a = block_pong[aBase + s];
            block_ping[dBase + s] = block_pong[bBase + a];
        }
        else
        {
            block_ping[dBase + s] = block_pong[bBase + s];
        }
    }
}
