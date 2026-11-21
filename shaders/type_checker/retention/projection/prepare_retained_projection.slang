import shared.collectives.step_program;
import shared.collectives.prefix_scan;
import type_checker.retention.retention_launch;
import type_checker.retention.projection.retained_projection_workspace;
import type_checker.retention.projection.plan_retained_instance_projection_step;

struct RankCounts
{
    uint4 first;
    uint4 second;
    uint2 last;
}

struct RankCountsAdd : IPrefixScanOp<RankCounts>
{
    static RankCounts identity() { return RankCounts(uint4(0u), uint4(0u), uint2(0u)); }
    static RankCounts combine(RankCounts a, RankCounts b)
    {
        return RankCounts(a.first + b.first, a.second + b.second, a.last + b.last);
    }
}

RankCounts load_counts(uint rank)
{
    uint b = rank * PJ_COLUMNS;
    return RankCounts(uint4(pj_base[b], pj_base[b + 1u], pj_base[b + 2u], pj_base[b + 3u]),
        uint4(pj_base[b + 4u], pj_base[b + 5u], pj_base[b + 6u], pj_base[b + 7u]),
        uint2(pj_base[b + 8u], pj_base[b + 9u]));
}

void store_counts(uint rank, RankCounts c)
{
    uint b = rank * PJ_COLUMNS;
    for (uint i = 0u; i < 4u; ++i)
    {
        pj_base[b + i] = c.first[i];
        pj_base[b + 4u + i] = c.second[i];
    }
    pj_base[b + 8u] = c.last.x;
    pj_base[b + 9u] = c.last.y;
}

void store_totals(uint ranks, RankCounts c)
{
    store_counts(ranks, c);
    for (uint i = 0u; i < 4u; ++i)
    {
        pj_status[PJ_S_TOTALS + i] = c.first[i];
        pj_status[PJ_S_TOTALS + 4u + i] = c.second[i];
    }
    pj_status[PJ_S_TOTALS + 8u] = c.last.x;
    pj_status[PJ_S_TOTALS + 9u] = c.last.y;
}

RWStructuredBuffer<RankCounts> pj_scan_sums;
groupshared RankCounts rank_sums[STEP_PROGRAM_GROUP_LANES];
groupshared RankCounts group_offset;

// Scans all columns of a rank together. The group totals are the only
// values that have to cross workgroup boundaries before writing offsets.
bool scan_ranks(inout StepProgram program, uint ranks, uint group, uint local)
{
    if (ranks == 0u)
    {
        if (program.lane == 0u) store_totals(0u, RankCountsAdd.identity());
        return true;
    }
    uint chunk = 1u + (ranks - 1u) / program.lanes;
    uint groups = 1u + (ranks - 1u) / (chunk * STEP_PROGRAM_GROUP_LANES);
    uint first = program.lane * chunk;
    uint end = min(first + chunk, ranks);
    RankCounts sum = RankCountsAdd.identity();
    RankCounts inclusive = sum;
    if (group < groups)
    {
        for (uint rank = first; rank < end; ++rank)
            sum = RankCountsAdd.combine(sum, load_counts(rank));
        inclusive = prefix_scan_inclusive<RankCounts, RankCountsAdd, STEP_PROGRAM_GROUP_LANES>(
            local, sum, rank_sums);
        if (local == STEP_PROGRAM_GROUP_LANES - 1u)
        {
            if (groups == 1u) store_totals(ranks, inclusive);
            else pj_scan_sums[group] = inclusive;
        }
    }
    RankCounts carry = RankCountsAdd.identity();
    if (groups > 1u)
    {
        if (!step_barrier(program)) return false;
        if (group >= groups) return true;
        if (group != 0u)
        {
            RankCounts prior = local < group ? pj_scan_sums[local] : RankCountsAdd.identity();
            RankCounts prefix = prefix_scan_inclusive<RankCounts, RankCountsAdd, STEP_PROGRAM_GROUP_LANES>(
                local, prior, rank_sums);
            if (local == STEP_PROGRAM_GROUP_LANES - 1u)
            {
                group_offset = prefix;
                if (group + 1u == groups) store_totals(ranks, RankCountsAdd.combine(prefix, inclusive));
            }
            GroupMemoryBarrierWithGroupSync();
            carry = group_offset;
        }
    }
    RankCounts offset = RankCountsAdd.combine(carry,
        RankCounts(inclusive.first - sum.first, inclusive.second - sum.second, inclusive.last - sum.last));
    for (uint rank = first; rank < end; ++rank)
    {
        RankCounts value = load_counts(rank);
        store_counts(rank, offset);
        offset = RankCountsAdd.combine(offset, value);
    }
    return true;
}

[shader("compute")]
[numthreads(STEP_PROGRAM_GROUP_LANES, 1, 1)]
void main(uint3 group : SV_GroupID, uint3 local : SV_GroupThreadID)
{
    StepProgram program = step_program_begin(group, local, program_launch.groups, program_launch.slot);
    uint ranks = pj_instance_count();
    for (uint row = program.lane; row < max(1u, ranks); row += program.lanes)
        plan_retained_instance_projection(row);
    if (!step_barrier(program)) return;
    if (pj_status[PJ_S_INPUT_ERROR] == 0u && !scan_ranks(program, ranks, group.x, local.x)) return;
    step_program_end(program);
}
