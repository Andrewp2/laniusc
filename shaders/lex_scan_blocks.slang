// shaders/lex_scan_blocks.slang
// Multi-round inclusive scan over per-block function vectors.
// Result after last round is inclusive prefix for each block.

#define N_STATES 32

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

[numthreads(1, 1, 1)]
void scan_blocks_step(uint3 tid: SV_DispatchThreadID)
{
    const uint nb = (gParams.n + 127u) / 128u;
    const uint i = tid.x;
    if (i >= nb)
        return;

    RWStructuredBuffer<uint> src = gScan.use_ping_as_src != 0 ? block_ping : block_pong;
    RWStructuredBuffer<uint> dst = gScan.use_ping_as_src != 0 ? block_pong : block_ping;

    if (i >= gScan.stride)
    {
        // compose: dst[i] = src[i] ∘ src[i - stride]
        const uint aBase = (i - gScan.stride) * N_STATES;
        const uint bBase = i * N_STATES;
        const uint dBase = i * N_STATES;

        [unroll]
        for (uint s = 0; s < N_STATES; ++s)
        {
            const uint a = src[aBase + s];
            dst[dBase + s] = src[bBase + a];
        }
    }
    else
    {
        // copy through
        const uint bBase = i * N_STATES;
        const uint dBase = i * N_STATES;
        [unroll]
        for (uint s = 0; s < N_STATES; ++s)
        {
            dst[dBase + s] = src[bBase + s];
        }
    }
}
