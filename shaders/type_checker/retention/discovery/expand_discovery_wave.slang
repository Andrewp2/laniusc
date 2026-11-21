import shared.collectives.step_program;
import type_checker.retention.discovery.discovery_workspace;
import type_checker.retention.discovery.collect_discovery_requests_step;
import type_checker.retention.discovery.collect_retained_requests_program;
import type_checker.retention.discovery.resolve_discovery_requests_step;
import type_checker.retention.discovery.discovery_request_status;
import type_checker.retention.substitution.retained_substitution_workspace;
import type_checker.retention.substitution.run_retained_substitution;

struct WaveRequests : ISubstitutionRequests
{
    uint count() { return sb_request_count[0u]; }
    uint capacity()
    {
        uint rows; uint stride;
        sb_requests.GetDimensions(rows, stride);
        return rows;
    }
    uint4 request(uint row) { return sb_requests[row]; }
}


public bool expand_discovery_wave(
    inout StepProgram program, DiscoveryFrontier frontier, uint run, uint depth, uint options)
{
    if (!collect_retained_requests(program, frontier)) return false;
    if (!step_barrier(program)) return false;
    if (!run_retained_substitution(program, options, run, WaveRequests())) return false;
    if (!step_barrier(program)) return false;

    if (sb_counts[SB_C_STATE] != SB_STATE_PUBLISHED || sb_counts[SB_C_RUN] != run)
    {
        if (program.lane == 0u) note_unpublished_requests();
    }
    else if (dg_status[12] == 0u)
    {
        uint generation = sb_counts[SB_C_GENERATION];
        bool ready = run != 0u && generation != 0u &&
            generation == rt_counts[RT_C_GENERATION] && rt_counts[RT_C_READY] != 0u;
        uint requests = sb_counts[SB_C_REQUESTS];
        for (uint row = program.lane; row < requests; row += program.lanes)
        {
            uint4 provenance = sb_results[row * SB_RESULT_WORDS + 1u];
            bool current = ready && provenance.z == run && provenance.w == generation;
            resolve_discovery_request(row, sb_results[row * SB_RESULT_WORDS], current, depth);
        }
    }
    if (!step_barrier(program)) return false;
    if (program.lane == 0u) finish_discovery_requests();
    return true;
}
