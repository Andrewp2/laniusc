// Exclusive prefix of the 16 per-lane counters: workgroup prefixes.
import type_checker.trait_solver.retained_catalog.retained_catalog_producer;

groupshared uint4 g_values[1024];

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 gid: SV_GroupID, uint3 tid: SV_GroupThreadID)
{
    uint group = gid.x + gid.y * 65535u;
    uint lane = group * 256u + tid.x;
    uint n = lanes();
    uint4 v0 = uint4(0u, 0u, 0u, 0u); uint4 v1 = v0; uint4 v2 = v0; uint4 v3 = v0;
    if (lane < n) { v0 = rc_flags[lane * 4u]; v1 = rc_flags[lane * 4u + 1u]; v2 = rc_flags[lane * 4u + 2u]; v3 = rc_flags[lane * 4u + 3u]; }
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
    if (lane < n)
    {
        rc_scan[lane * 4u] = g_values[tid.x] - v0;
        rc_scan[lane * 4u + 1u] = g_values[256u + tid.x] - v1;
        rc_scan[lane * 4u + 2u] = g_values[512u + tid.x] - v2;
        rc_scan[lane * 4u + 3u] = g_values[768u + tid.x] - v3;
    }
    if (tid.x == 255u && group * 256u < n)
    {
        rc_blocks[group * 4u] = g_values[255u]; rc_blocks[group * 4u + 1u] = g_values[511u];
        rc_blocks[group * 4u + 2u] = g_values[767u]; rc_blocks[group * 4u + 3u] = g_values[1023u];
    }
}
