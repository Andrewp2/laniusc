// Inclusive scan over per-block uint2 totals (ALL, KEPT), in one workgroup.
// pair_01 seeds the totals in ping. The scan writes the prefix where the
// earlier ping/pong doubling rounds left it: in ping after an even number of
// rounds, in pong after an odd number (pair_03's block_prefix_is_ping).

static const uint PAIR_BLOCK_WIDTH = 256u; // must match pair_01
static const uint WG_SIZE = 256u;
static const uint ROWS_PER_LANE = 8u;
static const uint CHUNK_ROWS = WG_SIZE * ROWS_PER_LANE;

struct Params
{
    uint n;
    uint n_states;
    uint start_state;
};
ConstantBuffer<Params> gParams;

RWStructuredBuffer<uint2> block_pair_ping; // length nb
RWStructuredBuffer<uint2> block_pair_pong; // length nb

groupshared uint2 g_lanes[WG_SIZE];

bool prefix_is_ping(uint block_count)
{
    uint rounds = 0u;
    for (uint stride = 1u; stride < block_count; stride <<= 1u)
        rounds += 1u;
    return (rounds & 1u) == 0u;
}

// The sum of the values of the lanes before `lane`; `total` is the sum of
// every lane's value. Every lane of the workgroup calls it.
uint2 workgroup_exclusive(uint lane, uint2 value, out uint2 total)
{
    g_lanes[lane] = value;
    GroupMemoryBarrierWithGroupSync();
    for (uint offset = 1u; offset < WG_SIZE; offset <<= 1u)
    {
        uint2 add = lane >= offset ? g_lanes[lane - offset] : uint2(0u, 0u);
        GroupMemoryBarrierWithGroupSync();
        g_lanes[lane] += add;
        GroupMemoryBarrierWithGroupSync();
    }
    total = g_lanes[WG_SIZE - 1u];
    uint2 inclusive = g_lanes[lane];
    GroupMemoryBarrierWithGroupSync();
    return inclusive - value;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void pair_02_scan_block_totals(uint3 group_id: SV_GroupID, uint3 local_id: SV_GroupThreadID)
{
    if (group_id.x != 0u || group_id.y != 0u)
        return;
    const uint nb = (gParams.n + (PAIR_BLOCK_WIDTH - 1u)) / PAIR_BLOCK_WIDTH;
    const bool to_ping = prefix_is_ping(nb);
    const uint lane = local_id.x;
    uint2 carry = uint2(0u, 0u);
    for (uint chunk = 0u; chunk < nb; chunk += CHUNK_ROWS)
    {
        uint first = chunk + lane * ROWS_PER_LANE;
        uint2 sum = uint2(0u, 0u);
        for (uint row = 0u; row < ROWS_PER_LANE; ++row)
        {
            if (first + row < nb)
                sum += block_pair_ping[first + row];
        }
        uint2 total;
        uint2 running = carry + workgroup_exclusive(lane, sum, total);
        for (uint row = 0u; row < ROWS_PER_LANE; ++row)
        {
            uint index = first + row;
            if (index < nb)
            {
                running += block_pair_ping[index];
                if (to_ping)
                    block_pair_ping[index] = running;
                else
                    block_pair_pong[index] = running;
            }
        }
        carry += total;
    }
}
