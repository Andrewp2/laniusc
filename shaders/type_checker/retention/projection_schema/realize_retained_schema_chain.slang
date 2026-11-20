import shared.collectives.step_program;
import type_checker.retention.retention_launch;
import type_checker.retention.projection_schema.retained_schema_workspace;
import type_checker.retention.projection_schema.advance_retained_schema_round_step;
import type_checker.retention.projection_schema.prepare_schema_round_requests;
import type_checker.retention.projection_schema.emit_retained_schema_requests_step;
import type_checker.retention.projection_schema.reserve_retained_schema_requests_step;
import type_checker.retention.projection_schema.publish_projected_schema_field_types_step;
import type_checker.retention.substitution.retained_substitution_workspace;
import type_checker.retention.substitution.run_retained_substitution;
import type_checker.retention.substitution.reset_retained_substitution;

StructuredBuffer<uint> sb_chain_runs;

struct SchemaRequests : ISubstitutionRequests
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

bool schema_publication_current(uint run)
{
    uint generation = sb_counts[SB_C_GENERATION];
    return run != 0u && sb_counts[SB_C_STATE] == SB_STATE_PUBLISHED &&
        sb_counts[SB_C_RUN] == run && generation != 0u &&
        generation == rt_counts[RT_C_GENERATION] && rt_counts[RT_C_READY] != 0u;
}

[shader("compute")]
[numthreads(STEP_PROGRAM_GROUP_LANES, 1, 1)]
void main(uint3 group : SV_GroupID, uint3 local : SV_GroupThreadID)
{
    StepProgram program = step_program_begin(group, local, program_launch.groups, program_launch.slot);
    uint rounds = ps_config[6u];
    uint gate = 0u;
    for (uint round = 0u; round < rounds; ++round)
    {
        if (program.lane == 0u)
            advance_retained_schema_round(0u, gate,
                schema_publication_current(gate), sb_counts[SB_C_SYNC_FAILED] != 0u);
        if (!step_barrier(program)) return;
        if (ps_status[PS_STOP] != PS_STOP_RUNNING) break;
        if (!prepare_schema_round_requests(program, false)) return;
        if (!step_barrier(program)) return;
        if (ps_status[PS_STOP] != PS_STOP_RUNNING) break;

        if (round != 0u)
        {
            reset_retained_substitution(program);
            if (!step_barrier(program)) return;
        }
        gate = sb_chain_runs[round];
        if (!run_retained_substitution(program, program_launch.options, gate, SchemaRequests())) return;
        if (!step_barrier(program)) return;

        uint requests = sb_request_count[0u];
        uint generation = sb_counts[SB_C_GENERATION];
        bool published = schema_publication_current(gate);
        for (uint row = program.lane; row < requests; row += program.lanes)
        {
            uint4 provenance = sb_results[row * SB_RESULT_WORDS + 1u];
            bool current = published && row < sb_counts[SB_C_REQUESTS] &&
                provenance.z == gate && provenance.w == generation;
            publish_projected_schema_field_types(row, sb_results[row * SB_RESULT_WORDS], current);
        }
        if (!step_barrier(program)) return;
    }

    if (program.lane == 0u)
        advance_retained_schema_round(1u, gate, schema_publication_current(gate),
            sb_counts[SB_C_SYNC_FAILED] != 0u);
    step_program_end(program);
}
