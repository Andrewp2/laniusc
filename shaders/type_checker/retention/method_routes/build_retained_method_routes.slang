import shared.collectives.step_program;
import type_checker.retention.retention_launch;
import type_checker.retention.method_routes.retained_method_route_workspace;
import type_checker.retention.method_routes.begin_retained_method_routing_step;
import type_checker.retention.method_routes.select_retained_method_bindings_step;
import type_checker.retention.method_routes.expand_retained_method_binding_terms_step;
import type_checker.retention.method_routes.intern_retained_method_binding_terms_step;
import type_checker.retention.method_routes.intern_retained_method_environments_step;
import type_checker.retention.method_routes.publish_retained_method_routes_step;
import type_checker.retention.method_routes.roll_back_retained_method_routes_step;

StructuredBuffer<uint> mr_gate;

bool run_levels<L : IMrLevel>(inout StepProgram program, uint base, L level)
{
    for (uint round = 0u; round < MR_LEVELS; ++round)
    {
        if (mr_state[base + (round + 2u) % 3u] == 0u) break;
        if (program.lane == 0u) mr_state[base + (round + 1u) % 3u] = 0u;
        // The word cleared here is distinct from the predecessor and from
        // the word updated in this round.
        level.run(program.lane, program.lanes, round);
        if (!step_barrier(program)) return false;
    }
    return true;
}

[shader("compute")]
[numthreads(STEP_PROGRAM_GROUP_LANES, 1, 1)]
void main(uint3 group : SV_GroupID, uint3 local : SV_GroupThreadID)
{
    if (program_launch.options != 0u && mr_gate[0u] == 0u) return;
    StepProgram program = step_program_begin(group, local, program_launch.groups, program_launch.slot);
    uint requests = mr_config[2u];
    uint nodes = mr_config[3u];
    for (uint row = program.lane; row < max(max(requests, nodes), 1u); row += program.lanes)
        begin_retained_method_routing(row);
    if (!step_barrier(program)) return;
    for (uint row = program.lane; row < requests; row += program.lanes)
        select_retained_method_bindings(row);
    if (!step_barrier(program)) return;
    if (!run_levels(program, MR_EXPAND_CHANGED, Expand())) return;
    if (!run_levels(program, MR_TERMS_CHANGED, Terms())) return;
    for (uint row = program.lane; row < requests; row += program.lanes)
        intern_retained_method_environments(row);
    if (!step_barrier(program)) return;
    if (program.lane == 0u) publish_retained_method_routes();
    if (!step_barrier(program)) return;
    if (mr_state[0u] == 3u)
    {
        uint slots; uint stride;
        rt_term_slot.GetDimensions(slots, stride);
        for (uint row = program.lane; row < slots; row += program.lanes)
            roll_back_retained_method_routes(row);
    }
    step_program_end(program);
}
