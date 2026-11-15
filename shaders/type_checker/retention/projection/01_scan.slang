// Projection step 1: one workgroup. Exclusive scan of every pj_base column
// over the ranks, in place, with the totals after the last rank (and in
// pj_status PJ_S_TOTALS). Each lane owns a contiguous chunk of ranks.
import type_checker.retention.projection.pj_common;

static const uint LANES = 256u;
groupshared uint sums[LANES];

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 gtid: SV_GroupThreadID)
{
    if (pj_status[PJ_S_INPUT_ERROR] != 0u) return;
    uint lane = gtid.x;
    uint n = pj_instance_count();
    uint chunk = (n + LANES - 1u) / LANES;
    uint lo = min(lane * chunk, n);
    uint hi = min(lo + chunk, n);
    for (uint c = 0u; c < PJ_COLUMNS; c++)
    {
        uint sum = 0u;
        for (uint r = lo; r < hi; r++) sum += pj_base[r * PJ_COLUMNS + c];
        sums[lane] = sum;
        GroupMemoryBarrierWithGroupSync();
        for (uint step = 1u; step < LANES; step <<= 1u)
        {
            uint add = lane >= step ? sums[lane - step] : 0u;
            GroupMemoryBarrierWithGroupSync();
            sums[lane] += add;
            GroupMemoryBarrierWithGroupSync();
        }
        uint running = sums[lane] - sum;
        for (uint r = lo; r < hi; r++)
        {
            uint v = pj_base[r * PJ_COLUMNS + c];
            pj_base[r * PJ_COLUMNS + c] = running;
            running += v;
        }
        if (lane == LANES - 1u)
        {
            pj_base[n * PJ_COLUMNS + c] = sums[lane];
            pj_status[PJ_S_TOTALS + c] = sums[lane];
        }
        GroupMemoryBarrierWithGroupSync();
    }
}
