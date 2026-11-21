import shared.collectives.step_program;
import type_checker.retention.discovery.discovery_workspace;
import type_checker.retention.discovery.collect_discovery_requests_step;
import type_checker.retention.discovery.resolve_discovery_requests_step;
import type_checker.retention.discovery.discovery_request_status;
import type_checker.retention.substitution.retained_substitution_workspace;
import type_checker.retention.substitution.run_retained_substitution;
import type_checker.retention.substitution.begin_retained_substitution_step;
import type_checker.retention.substitution.finalize_retained_substitution_step;

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


// Each request can produce several substitution tasks. Size the working
// grid from the live requests and proof nodes instead of their capacities.
public uint discovery_wave_groups(uint bound, uint nodes)
{
    uint rows = max(sb_request_count[0u], nodes);
    return rows == 0u ? 1u : min(bound, max(4u, (rows - 1u) / 64u + 1u));
}

public bool substitute_discovery_requests(
    inout StepProgram program, uint run, uint depth, uint options)
{
    uint requests = sb_request_count[0u];
    if (program.lane == 0u)
    {
        dg_status[7u] = requests;
        finish_discovery_requests();
    }

    if (requests == 0u && sb_counts[SB_C_SYNC_FAILED] == 0u)
    {
        if (program.lane == 0u)
        {
            begin_retained_substitution(0u, WaveRequests().capacity(), run);
            sb_counts[SB_C_PHASE] = SB_PHASE_DONE;
            finalize_retained_substitution();
            if (sb_counts[SB_C_STATE] != SB_STATE_PUBLISHED) note_unpublished_requests();
        }
        return step_barrier(program);
    }
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
