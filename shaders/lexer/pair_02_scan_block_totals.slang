// Multi-round inclusive scan over per-block uint2 totals (ALL, KEPT).
// Ping/pong buffers are provided; after the final round the host copies
// the last writer (ping or pong) into block_prefix_pair.

static const uint MAX_GROUPS_PER_DIM = 65535u;
static const uint PAIR_BLOCK_WIDTH = 256u; // must match pair_01

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

RWStructuredBuffer<uint2> block_pair_ping; // length nb
RWStructuredBuffer<uint2> block_pair_pong; // length nb

[shader("compute")]
[numthreads(1, 1, 1)]
void pair_02_scan_block_totals(uint3 tid: SV_DispatchThreadID,
                               uint3 gid: SV_GroupID)
{
    const uint nb = (gParams.n + (PAIR_BLOCK_WIDTH - 1u)) / PAIR_BLOCK_WIDTH;
    const uint groups_x = (nb < MAX_GROUPS_PER_DIM) ? nb : MAX_GROUPS_PER_DIM;
    const uint i = gid.y * groups_x + gid.x; // 1 thread per block element

    if (i >= nb)
        return;

    // TODO: the shader should not be responsible for picking ping/pong
    // instead that should happen in the binding
    // because now we've added extra work to the shader
    if (gScan.use_ping_as_src != 0u)
    {
        uint2 val = block_pair_ping[i];
        if (i >= gScan.stride)
        {
            val += block_pair_ping[i - gScan.stride];
        }
        block_pair_pong[i] = val;
    }
    else
    {
        uint2 val = block_pair_pong[i];
        if (i >= gScan.stride)
        {
            val += block_pair_pong[i - gScan.stride];
        }
        block_pair_ping[i] = val;
    }
}
