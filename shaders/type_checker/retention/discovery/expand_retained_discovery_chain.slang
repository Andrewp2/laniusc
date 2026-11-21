import shared.collectives.step_program;
import type_checker.retention.retention_launch;
import type_checker.retention.discovery.discovery_workspace;
import type_checker.retention.discovery.discovery_term_counts;
import type_checker.retention.discovery.expand_discovery_wave;
import type_checker.retention.discovery.collect_discovery_requests_step;
import type_checker.retention.substitution.retained_substitution_workspace;
import type_checker.retention.substitution.reset_retained_substitution;

StructuredBuffer<uint> sb_chain_runs;
import type_checker.retention.discovery.discovery_frontier;

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
        if (wave != first) reset_retained_substitution(program);
        if (wave != 0u && program.lane == 0u) advance_discovery_frontier(wave, false);
        if (!step_barrier(program)) return;
        DiscoveryFrontier frontier = discovery_frontier();
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
        count_discovered_term(term, false);
    step_program_end(program);
}
