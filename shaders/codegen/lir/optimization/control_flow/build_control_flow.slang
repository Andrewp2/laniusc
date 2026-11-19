import codegen.lir.optimization.control_flow.control_flow_steps;
import shared.collectives.step_program;
import shared.collectives.program_prefix_scan;

struct Launch
{
    uint groups;
    uint slot;
    uint validate;
    uint reserved;
};

ConstantBuffer<Launch> program_launch;
RWStructuredBuffer<uint> scan_group_sums;
RWStructuredBuffer<uint> opt_ir_edge_scan_dispatch_args;

[shader("compute")]
[numthreads(STEP_PROGRAM_GROUP_LANES, 1, 1)]
void main(uint3 group : SV_GroupID, uint3 local : SV_GroupThreadID)
{
    StepProgram program = step_program_begin(group, local, program_launch.groups, program_launch.slot);
    uint semantic_total = semantic_lir_total[0u];
    uint nodes = min(semantic_capacity(), semantic_total);
    for (uint row = program.lane; row < max(1u, nodes); row += program.lanes)
    {
        project_optimization_nodes(row, nodes, semantic_total);
        if (row < nodes) mark_control_flow_blocks(row, nodes);
    }
    if (!step_barrier(program)) return;

    if (!step_program_prefix_scan(program, nodes, opt_ir_block_start_flag,
            opt_ir_block_prefix, opt_ir_block_total, scan_group_sums)) return;
    if (!step_barrier(program)) return;

    uint block_total = opt_ir_block_total[0u];
    uint blocks = min(block_capacity(), block_total);
    // The separate dominator child scan still consumes an indirect grid.
    if (program.lane == 0u)
    {
        uint child_scan_groups = max(1u, (blocks + 255u) / 256u);
        opt_ir_edge_scan_dispatch_args[0u] = min(child_scan_groups, 65535u);
        opt_ir_edge_scan_dispatch_args[1u] = (child_scan_groups + 65534u) / 65535u;
        opt_ir_edge_scan_dispatch_args[2u] = 1u;
    }
    for (uint row = program.lane; row < max(1u, nodes); row += program.lanes)
        scatter_control_flow_blocks(row, nodes, block_total);
    if (!step_barrier(program)) return;

    // Edge counting reads the terminator of the same block. The neighboring
    // block fields it reads were published before this step.
    for (uint row = program.lane; row < blocks; row += program.lanes)
    {
        finalize_control_flow_blocks(row, blocks, nodes);
        mark_control_flow_edges(row, blocks);
    }
    if (!step_barrier(program)) return;

    if (!step_program_prefix_scan(program, blocks, opt_ir_edge_count_by_block,
            opt_ir_edge_prefix, opt_ir_edge_total, scan_group_sums)) return;
    if (!step_barrier(program)) return;

    uint edge_total = opt_ir_edge_total[0u];
    uint edges = min(edge_capacity(), edge_total);
    for (uint row = program.lane; row < max(1u, blocks); row += program.lanes)
    {
        scatter_control_flow_edges(row, blocks, edge_total);
        if (row < blocks) clear_control_flow_predecessors(row);
    }
    if (!step_barrier(program)) return;

    for (uint row = program.lane; row < edges; row += program.lanes)
        count_control_flow_predecessors(row);
    if (!step_barrier(program)) return;

    if (!step_program_prefix_scan(program, blocks, opt_ir_edge_count_by_block,
            opt_ir_edge_prefix, opt_ir_predecessor_total, scan_group_sums)) return;
    if (!step_barrier(program)) return;

    for (uint row = program.lane; row < blocks; row += program.lanes)
        prepare_control_flow_predecessor_ranges(row);
    if (!step_barrier(program)) return;

    for (uint row = program.lane; row < edges; row += program.lanes)
        scatter_control_flow_predecessors(row);

    if (program_launch.validate != 0u)
    {
        if (!step_barrier(program)) return;
        uint predecessor_total = opt_ir_predecessor_total[0u];
        for (uint row = program.lane; row < blocks; row += program.lanes)
            validate_control_flow_predecessors(row, edges, predecessor_total);
    }
    step_program_end(program);
}
