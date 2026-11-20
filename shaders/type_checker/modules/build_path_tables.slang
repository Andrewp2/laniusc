import type_checker.modules.paths.path_steps;
import shared.collectives.step_program;

struct Launch
{
    uint groups;
    uint slot;
    uint options;
    uint reserved;
};
ConstantBuffer<Launch> program_launch;

[shader("compute")]
[numthreads(STEP_PROGRAM_GROUP_LANES, 1, 1)]
void main(uint3 group : SV_GroupID, uint3 local : SV_GroupThreadID)
{
    StepProgram program = step_program_begin(group, local, program_launch.groups, program_launch.slot);
    uint tokens = gParams.n_tokens;
    uint hir = min(compact_hir_count[0u], gParams.n_hir_nodes);
    uint raw_paths = compact_path_count[0u];
    uint paths = min(raw_paths, gParams.n_hir_nodes);
    uint segments = min(compact_path_segment_count[0u], tokens);
    uint qualifier_capacity;
    uint stride;
    resolved_value_type_qualifier_token.GetDimensions(qualifier_capacity, stride);
    uint clear_rows = max(qualifier_capacity, max(tokens, gParams.n_hir_nodes));
    for (uint row = program.lane; row < clear_rows; row += program.lanes)
        clear_path_state(row, qualifier_capacity);
    for (uint row = program.lane; row < hir; row += program.lanes)
        mark_module_record_candidates(row);
    for (uint row = program.lane; row < segments; row += program.lanes)
    {
        scatter_path_segments(row, hir, raw_paths);
        clear_path_prefix_table(row, segments);
    }
    if (!step_barrier(program)) return;

    if (program.lane == 0u) publish_path_dispatch(paths);
    for (uint row = program.lane; row < max(1u, paths); row += program.lanes)
    {
        scatter_paths(row, hir, paths);
        count_path_segments(row, paths, segments);
    }
    if (!step_barrier(program)) return;

    uint depth = min(path_max_segment_count[0u], tokens);
    uint round = 0u;
    for (uint step = 1u; step < depth; step <<= 1u, ++round)
    {
        for (uint row = program.lane; row < segments; row += program.lanes)
        {
            if ((round & 1u) == 0u)
                intern_path_prefix_pairs(row, segments, step, round + 1u, path_prefix_id_a, path_prefix_id_b);
            else
                intern_path_prefix_pairs(row, segments, step, round + 1u, path_prefix_id_b, path_prefix_id_a);
        }
        if (!step_barrier(program)) return;
    }
    if ((round & 1u) != 0u)
    {
        for (uint row = program.lane; row < segments; row += program.lanes)
            path_prefix_id_a[row] = path_prefix_id_b[row];
    }
    step_program_end(program);
}
