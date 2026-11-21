import shared.collectives.step_program;
import type_checker.retention.method_routes.retained_method_route_workspace;
import type_checker.retention.method_routes.begin_retained_method_routing_step;
import type_checker.retention.method_routes.select_retained_method_bindings_step;
import type_checker.retention.method_routes.expand_retained_method_binding_terms_step;
import type_checker.retention.method_routes.intern_retained_method_binding_terms_step;
import type_checker.retention.method_routes.intern_retained_method_environments_step;
import type_checker.retention.method_routes.publish_retained_method_routes_step;
import type_checker.retention.method_routes.roll_back_retained_method_routes_step;


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


public bool resolve_retained_method_routes<R : IMethodResults>(
    inout StepProgram program, uint requests, R results)
{
    uint nodes = mr_config[3u];
    // The table is sized for the request capacity. Use all lanes to clear
    // it even when the live wave has only a few requests and proof nodes.
    if (requests != 0u)
    {
        uint slots; uint stride;
        mr_env_slots.GetDimensions(slots, stride);
        for (uint slot = program.lane; slot < slots; slot += program.lanes)
            mr_env_slots[slot] = 0u;
    }
    for (uint row = program.lane; row < max(max(requests, nodes), 1u); row += program.lanes)
        begin_retained_method_routing(row, requests);
    if (!step_barrier(program)) return false;
    for (uint row = program.lane; row < requests; row += program.lanes)
        select_retained_method_bindings(row, results);
    if (!step_barrier(program)) return false;
    if (!run_levels(program, MR_EXPAND_CHANGED, Expand())) return false;
    if (!run_levels(program, MR_TERMS_CHANGED, Terms())) return false;
    for (uint row = program.lane; row < requests; row += program.lanes)
        intern_retained_method_environments(row, results.result(row).x, results.request(row));
    if (!step_barrier(program)) return false;
    if (program.lane == 0u)
    {
        uint failure = mr_state[2u];
        uint4 request = failure < requests ? results.request(failure) : uint4(0u);
        publish_retained_method_routes(requests, request);
    }
    if (!step_barrier(program)) return false;
    if (mr_state[0u] == 3u)
    {
        uint slots; uint stride;
        rt_term_slot.GetDimensions(slots, stride);
        for (uint row = program.lane; row < slots; row += program.lanes)
            roll_back_retained_method_routes(row);
    }
    return true;
}
