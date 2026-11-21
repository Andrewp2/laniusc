import shared.collectives.step_program;
import type_checker.retention.retention_launch;
import type_checker.retention.discovery.discovery_workspace;
import type_checker.retention.discovery.discovery_rank_order;
import type_checker.retention.discovery.discovery_publication;

[shader("compute")]
[numthreads(STEP_PROGRAM_GROUP_LANES, 1, 1)]
void main(uint3 group : SV_GroupID, uint3 local : SV_GroupThreadID)
{
    StepProgram program = step_program_begin(group, local, program_launch.groups, program_launch.slot);
    uint end = dg_config[14];
    uint terms = rt_counts[RT_A_TERMS];
    for (uint row = program.lane; row < end; row += program.lanes)
        dg_term_order[row] = RT_INVALID;
    if (!step_barrier(program)) return;

    for (uint term = RT_FIRST_TERM + program.lane; term < terms; term += program.lanes)
    {
        if (rt_term_head[term].x == 0u || !rt_term_closed(term)) continue;
        uint height = rt_term_height(term);
        if (height == 0u || height >= 128u)
        {
            dg_status[10] = 8u;
            continue;
        }
        uint ordinal;
        InterlockedAdd(dg_levels[256u + height], 1u, ordinal);
        dg_term_order[dg_levels[128u + height] + ordinal] = term;
    }
    if (!step_barrier(program)) return;

    for (uint height = 1u; height < 128u; ++height)
    {
        uint start = dg_levels[128u + height];
        uint next = height == 127u ? end : dg_levels[129u + height];
        uint rows = next - start;
        if (rows == 0u) continue;
        TermOrder order;
        order.base = start;
        if (!sort_discovery_order(program, order, rows)) return;
        for (uint row = program.lane; row < rows; row += program.lanes)
        {
            uint term = order.load(row);
            if (term != RT_INVALID) dg_term_rank[term] = RT_FIRST_TERM + start + row;
        }
        if (!step_barrier(program)) return;
    }

    uint rows = dg_config[13];
    uint instances = dg_status[0];
    for (uint row = program.lane; row < rows; row += program.lanes)
        dg_order[row] = row < instances && dg_instances[2u * row].x != 0u ? row : RT_INVALID;
    if (!step_barrier(program)) return;
    if (!sort_discovery_order(program, InstanceOrder(), rows)) return;

    uint live = dg_status[1];
    for (uint row = program.lane; row < live; row += program.lanes)
        dg_rank[dg_order[row]] = row;
    if (!step_barrier(program)) return;
    uint uses = rt_counts[RT_A_USES];
    uint edges = dg_status[2];
    for (uint row = program.lane; row < max(uses, max(live, edges)); row += program.lanes)
        publish_discovered_instances(row, 1u);
    if (!step_barrier(program)) return;
    if (program.lane == 0u) publish_discovered_instances(0u, 2u);
    step_program_end(program);
}
