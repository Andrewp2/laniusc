import shared.collectives.step_program;
import type_checker.retention.discovery.discovery_workspace;
import type_checker.retention.discovery.collect_discovery_requests_step;
import type_checker.retention.discovery.discovery_request_status;
import type_checker.retention.discovery.discovery_admission;

public StructuredBuffer<uint> dg_receipt;

public void collect_frontier_requests(StepProgram program, DiscoveryFrontier frontier)
{
    uint group = program.lane / STEP_PROGRAM_GROUP_LANES;
    uint lane = program.lane % STEP_PROGRAM_GROUP_LANES;
    for (uint owner = frontier.lo + group; owner < frontier.hi; owner += program.groups)
        collect_instance_requests(owner, lane);
}

public bool collect_retained_requests(inout StepProgram program, DiscoveryFrontier frontier)
{
    if (dg_status[29] != 0u)
    {
        if (program.leader)
            InterlockedOr(step_program_sync[program.sync_base + STEP_SYNC_FAILED], 1u);
        return false;
    }

    if (program.lane == 0u)
    {
        sb_request_count[0u] = 0u;
        dg_status[7u] = 0u;
        if (dg_proof_identity[0u] != 0u && !dg_proofs_current()) dg_status[10u] = 8u;
    }
    if (!step_barrier(program)) return false;

    if (dg_config[4u] != 0u)
    {
        // The source catalog's receipt was copied before the root wave.
        if (dg_config[10u] == 0u || (dg_receipt[0u] == 1u && dg_receipt[1u] == 0u))
        {
            uint uses = rt_counts[RT_A_USES];
            for (uint row = program.lane; row < uses; row += program.lanes)
                collect_root_request(row);
        }
    }
    else
    {
        collect_frontier_requests(program, frontier);
    }
    if (!step_barrier(program)) return false;
    if (program.lane == 0u)
    {
        dg_status[7u] = sb_request_count[0u];
        finish_discovery_requests();
    }
    return true;
}
