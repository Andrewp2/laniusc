import shared.collectives.step_program;
import type_checker.retention.retention_launch;
import type_checker.retention.discovery.discovery_workspace;
import type_checker.retention.discovery.discovery_frontier;
import type_checker.retention.discovery.expand_discovery_wave;
import type_checker.retention.discovery.collect_discovery_requests_step;
import type_checker.retention.discovery.collect_retained_requests_program;
import type_checker.retention.discovery.attach_discovered_method_route_step;
import type_checker.retention.discovery.discovery_request_status;
import type_checker.retention.method_routes.retained_method_route_workspace;
import type_checker.retention.method_routes.resolve_retained_method_routes;
import type_checker.retention.substitution.retained_substitution_workspace;

struct CurrentMethods : IMethodResults
{
    uint4 request(uint row) { return dg_req_meta[row]; }
    uint instance_decl(uint instance) { return dg_instances[2u * instance].x; }
    uint4 result(uint row) { return sb_results[row * SB_RESULT_WORDS]; }
    bool current(uint row)
    {
        uint run = mr_config[0u];
        uint generation = sb_counts[SB_C_GENERATION];
        if (run == 0u || sb_counts[SB_C_STATE] != SB_STATE_PUBLISHED ||
            sb_counts[SB_C_RUN] != run || generation == 0u ||
            generation != rt_counts[RT_C_GENERATION] || rt_counts[RT_C_READY] == 0u ||
            row >= sb_counts[SB_C_REQUESTS]) return false;
        uint4 provenance = sb_results[row * SB_RESULT_WORDS + 1u];
        return provenance.z == run && provenance.w == generation;
    }
}

[shader("compute")]
[numthreads(STEP_PROGRAM_GROUP_LANES, 1, 1)]
void main(uint3 group : SV_GroupID, uint3 local : SV_GroupThreadID)
{
    StepProgram program = step_program_begin(group, local, program_launch.groups, program_launch.slot);
    uint producer = dg_receipt[31u];
    bool solved = producer == 0u && dg_receipt[64u] == 2u;
    bool route_methods = solved && dg_status[10u] == 0u && dg_status[12u] == 0u;
    if (program.lane == 0u && producer != 16u && !solved && dg_status[10u] == 0u)
        dg_status[10u] = 12u;
    if (!step_barrier(program)) return;

    uint depth = dg_config[6u];
    if (!expand_discovery_wave(program, discovery_frontier(), dg_config[5u], depth, program_launch.options)) return;
    if (!step_barrier(program)) return;
    if (route_methods)
    {
        uint requests = sb_counts[SB_C_REQUESTS];
        if (!resolve_retained_method_routes(program, requests, CurrentMethods())) return;
        if (!step_barrier(program)) return;
        if (mr_state[0u] != 2u || mr_state[MR_PENDING] != 0u)
        {
            if (program.lane == 0u) note_unpublished_method_routes();
        }
        else if (dg_status[12u] == 0u)
        {
            uint rows = dg_status[7u];
            for (uint row = program.lane; row < rows; row += program.lanes)
            {
                uint4 route = mr_out[row];
                uint environment = route.y;
                if (route.w == 1u && dg_req_meta[row].x == 0u && (environment & RT_PARAM_BIT) != 0u)
                    environment = mr_out[environment & ~RT_PARAM_BIT].y;
                attach_discovered_method_route(row, route, environment, depth);
            }
        }
        if (!step_barrier(program)) return;
    }
    if (program.lane == 0u)
    {
        finish_discovery_requests();
        if (dg_config[12u] != 0u)
            advance_discovery_frontier(dg_config[8u], true);
    }
    step_program_end(program);
}
