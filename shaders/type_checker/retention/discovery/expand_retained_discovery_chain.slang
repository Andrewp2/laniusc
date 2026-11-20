import shared.collectives.step_program;
import type_checker.retention.retention_launch;
import type_checker.retention.discovery.discovery_workspace;
import type_checker.retention.discovery.expand_discovery_wave;
import type_checker.retention.discovery.collect_discovery_requests_step;
import type_checker.retention.substitution.retained_substitution_workspace;

StructuredBuffer<uint> sb_chain_runs;
RWStructuredBuffer<uint> dg_wave;

void reset_substitution(StepProgram program)
{
    uint slots; uint stride;
    sb_memo.GetDimensions(slots, stride);
    SbMemoEntry empty = { 0u, 0u, 0u };
    for (uint row = program.lane; row < slots; row += program.lanes)
        sb_memo[row] = empty;
    sb_term_slots.GetDimensions(slots, stride);
    for (uint row = program.lane; row < slots; row += program.lanes)
        sb_term_slots[row] = uint2(0u);
    for (uint row = program.lane; row < SB_C_SYNC_FAILED; row += program.lanes)
        sb_counts[row] = 0u;
}

void advance_frontier(uint wave)
{
    uint lo = dg_wave[1];
    bool ready = dg_status[11] == dg_wave[3] && dg_status[12] == 0u && dg_status[3] == 0u &&
        dg_status[10] == 0u && dg_status[6] == RT_INVALID;
    uint hi = ready ? max(lo, dg_status[0]) : lo;
    dg_wave[0] = lo;
    dg_wave[1] = hi;
    dg_wave[2] = dg_status[2];
    dg_wave[4u + 2u * wave] = lo;
    dg_wave[5u + 2u * wave] = hi;
}

[shader("compute")]
[numthreads(STEP_PROGRAM_GROUP_LANES, 1, 1)]
void main(uint3 group : SV_GroupID, uint3 local : SV_GroupThreadID)
{
    StepProgram program = step_program_begin(group, local, program_launch.groups, program_launch.slot);
    uint first = dg_config[12];
    uint end = dg_config[13];
    uint wave = first;
    for (; wave < end; ++wave)
    {
        if (wave != first) reset_substitution(program);
        if (wave != 0u && program.lane == 0u) advance_frontier(wave);
        if (!step_barrier(program)) return;
        DiscoveryFrontier frontier = { dg_wave[0], dg_wave[1], dg_wave[2] };
        uint run_wave = wave;
        // Empty frontiers keep their log records and publish the chain's
        // last run number. Only one empty substitution is needed.
        if (frontier.hi == frontier.lo)
        {
            run_wave = end - 1u;
            if (program.lane == 0u)
            {
                for (uint skipped = wave + 1u; skipped < end; ++skipped)
                {
                    dg_wave[4u + 2u * skipped] = frontier.lo;
                    dg_wave[5u + 2u * skipped] = frontier.lo;
                }
            }
        }
        uint depth = dg_config[6] + run_wave;
        if (!expand_discovery_wave(program, frontier, sb_chain_runs[run_wave], depth, program_launch.options)) return;
        wave = run_wave;
        if (!step_barrier(program)) return;
    }

    uint terms = rt_counts[RT_A_TERMS];
    for (uint term = RT_FIRST_TERM + program.lane; term < terms; term += program.lanes)
    {
        if (rt_term_head[term].x == 0u || !rt_term_closed(term)) continue;
        uint height = rt_term_height(term);
        if (height != 0u && height < 128u) InterlockedAdd(dg_levels[height], 1u);
    }
    step_program_end(program);
}
