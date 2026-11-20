import type_checker.trait_solver.closed_obligations.closed_obligation_batch;
import type_checker.trait_solver.closed_obligations.closed_obligation_steps;
import shared.collectives.step_program;
import shared.collectives.program_prefix_scan;

struct Launch
{
    uint groups;
    uint slot;
    uint chained;
    uint reserved;
};
ConstantBuffer<Launch> program_launch;
RWStructuredBuffer<uint4> cw_scan_group_sums;

// The snapshots of a frontier are immutable until all lanes have expanded it.
bool expand_closed_terms(inout StepProgram program)
{
    for (uint level = 0u; level < 65u; ++level)
    {
        if (program.lane == 0u)
        {
            cw_state[3] = cw_state[4];
            cw_state[4] = cw_state[2];
        }
        if (!step_barrier(program)) return false;
        uint first = cw_state[3];
        uint end = cw_state[4];
        if (first == end) break;
        for (uint at = first + program.lane; at < end; at += program.lanes)
        {
            uint term = cw_front[at];
            for (uint a = 0u; a < cw_term_arity(term); ++a)
                cw_mark(cw_term_arg(term, a));
        }
        if (!step_barrier(program)) return false;
    }
    return true;
}

[shader("compute")]
[numthreads(STEP_PROGRAM_GROUP_LANES, 1, 1)]
void main(uint3 group : SV_GroupID, uint3 local : SV_GroupThreadID)
{
    if (program_launch.chained != 0u && cw_config[CW_CFG_RUN] == 0u) return;

    StepProgram program = step_program_begin(group, local, program_launch.groups, program_launch.slot);
    uint clear_rows = max(max(cw_config[6], cw_terms()), max(max(cw_config[1], cw_config[2]), CW_STATE_WORDS));
    for (uint row = program.lane; row < clear_rows; row += program.lanes)
        clear_closed_workspace(row);
    if (!step_barrier(program)) return;

    uint catalog_rows = max(cw_cat_count(1u), max(cw_cat_count(2u), cw_cat_count(4u)));
    for (uint row = program.lane; row < max(1u, catalog_rows); row += program.lanes)
        index_closed_catalog(row);
    if (!step_barrier(program)) return;

    uint instances = cw_end() - cw_first();
    for (uint row = program.lane; row < instances; row += program.lanes)
        mark_closed_roots(row);
    if (!step_barrier(program)) return;

    if (!expand_closed_terms(program)) return;
    // The last empty level only reads the frontier. The prior level's
    // barrier has already published every reached term.
    uint reached = cw_state[2];
    for (uint at = program.lane; at < reached; at += program.lanes)
        intern_closed_constants(cw_front[at]);
    if (!step_barrier(program)) return;

    uint rows = cw_lanes();
    for (uint row = program.lane; row < rows; row += program.lanes)
        count_closed_rows(row);
    if (!step_barrier(program)) return;

    if (!step_program_prefix_scan_u32x4(program, rows, cw_scan_low, cw_scan_low,
        cw_state, 8u, cw_scan_group_sums)) return;
    if (!step_barrier(program)) return;
    if (!step_program_prefix_scan_u32x4(program, rows, cw_scan_high, cw_scan_high,
        cw_state, 12u, cw_scan_group_sums)) return;
    step_program_end(program);
}
