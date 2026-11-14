// Exclusive prefix of the block sums in one workgroup; the totals go to
// rc_state. Blocks are few (lanes / 256), and a 256-block chunk loop keeps
// this one workgroup's span at lanes / 65536 steps.
import type_checker.trait_solver.retained.producer;

groupshared uint4 g_values[1024];
groupshared uint4 g_carry[4];

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_GroupThreadID)
{
    uint blocks = (lanes() + 255u) / 256u;
    if (tid.x < 4u) g_carry[tid.x] = uint4(0u, 0u, 0u, 0u);
    GroupMemoryBarrierWithGroupSync();
    for (uint chunk = 0u; chunk < blocks; chunk += 256u)
    {
        uint index = chunk + tid.x;
        bool live = index < blocks;
        uint4 v0 = live ? rc_blocks[index * 4u] : uint4(0u, 0u, 0u, 0u);
        uint4 v1 = live ? rc_blocks[index * 4u + 1u] : uint4(0u, 0u, 0u, 0u);
        uint4 v2 = live ? rc_blocks[index * 4u + 2u] : uint4(0u, 0u, 0u, 0u);
        uint4 v3 = live ? rc_blocks[index * 4u + 3u] : uint4(0u, 0u, 0u, 0u);
        g_values[tid.x] = v0; g_values[256u + tid.x] = v1; g_values[512u + tid.x] = v2; g_values[768u + tid.x] = v3;
        GroupMemoryBarrierWithGroupSync();
        for (uint offset = 1u; offset < 256u; offset <<= 1u)
        {
            bool take = tid.x >= offset;
            uint from = take ? tid.x - offset : tid.x;
            uint4 a0 = take ? g_values[from] : uint4(0u, 0u, 0u, 0u);
            uint4 a1 = take ? g_values[256u + from] : uint4(0u, 0u, 0u, 0u);
            uint4 a2 = take ? g_values[512u + from] : uint4(0u, 0u, 0u, 0u);
            uint4 a3 = take ? g_values[768u + from] : uint4(0u, 0u, 0u, 0u);
            GroupMemoryBarrierWithGroupSync();
            g_values[tid.x] += a0; g_values[256u + tid.x] += a1; g_values[512u + tid.x] += a2; g_values[768u + tid.x] += a3;
            GroupMemoryBarrierWithGroupSync();
        }
        uint4 c0 = g_carry[0]; uint4 c1 = g_carry[1]; uint4 c2 = g_carry[2]; uint4 c3 = g_carry[3];
        if (live)
        {
            rc_blocks[index * 4u] = c0 + g_values[tid.x] - v0;
            rc_blocks[index * 4u + 1u] = c1 + g_values[256u + tid.x] - v1;
            rc_blocks[index * 4u + 2u] = c2 + g_values[512u + tid.x] - v2;
            rc_blocks[index * 4u + 3u] = c3 + g_values[768u + tid.x] - v3;
        }
        GroupMemoryBarrierWithGroupSync();
        if (tid.x == 0u)
        {
            g_carry[0] = c0 + g_values[255u]; g_carry[1] = c1 + g_values[511u];
            g_carry[2] = c2 + g_values[767u]; g_carry[3] = c3 + g_values[1023u];
        }
        GroupMemoryBarrierWithGroupSync();
    }
    if (tid.x < RC_COUNTERS)
    {
        uint4 carry = g_carry[tid.x / 4u];
        rc_state[RC_S_TOTALS + tid.x] = carry[tid.x & 3u];
    }
}
