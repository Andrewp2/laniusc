import codegen.lir.optimization.structure_tables;
import codegen.lir.optimization.control_flow.control_flow_steps;
import codegen.lir.optimization.control_flow.reachability_steps;
import codegen.lir.optimization.dominance_steps;
import codegen.lir.optimization.regions_steps;
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

bool construct_control_flow(inout StepProgram program, bool validate)
{
    uint semantic_total = semantic_lir_total[0u];
    uint nodes = min(semantic_capacity(), semantic_total);
    for (uint row = program.lane; row < max(1u, nodes); row += program.lanes)
    {
        project_optimization_nodes(row, nodes, semantic_total);
        if (row < nodes) mark_control_flow_blocks(row, nodes);
    }
    if (!step_barrier(program)) return false;

    if (!step_program_prefix_scan(program, nodes, opt_ir_block_start_flag,
            opt_ir_block_prefix, opt_ir_block_total, scan_group_sums)) return false;
    if (!step_barrier(program)) return false;

    uint block_total = opt_ir_block_total[0u];
    uint blocks = min(block_capacity(), block_total);
    for (uint row = program.lane; row < max(1u, nodes); row += program.lanes)
        scatter_control_flow_blocks(row, nodes, block_total);
    if (!step_barrier(program)) return false;

    // Edge counting reads the terminator of the same block. The neighboring
    // block fields it reads were published before this step.
    for (uint row = program.lane; row < blocks; row += program.lanes)
    {
        finalize_control_flow_blocks(row, blocks, nodes);
        mark_control_flow_edges(row, blocks);
    }
    if (!step_barrier(program)) return false;

    if (!step_program_prefix_scan(program, blocks, opt_ir_edge_count_by_block,
            opt_ir_edge_prefix, opt_ir_edge_total, scan_group_sums)) return false;
    if (!step_barrier(program)) return false;

    uint edge_total = opt_ir_edge_total[0u];
    uint edges = min(edge_capacity(), edge_total);
    for (uint row = program.lane; row < max(1u, blocks); row += program.lanes)
    {
        scatter_control_flow_edges(row, blocks, edge_total);
        if (row < blocks) clear_control_flow_predecessors(row);
    }
    if (!step_barrier(program)) return false;

    for (uint row = program.lane; row < edges; row += program.lanes)
        count_control_flow_predecessors(row);
    if (!step_barrier(program)) return false;

    if (!step_program_prefix_scan(program, blocks, opt_ir_edge_count_by_block,
            opt_ir_edge_prefix, opt_ir_predecessor_total, scan_group_sums)) return false;
    if (!step_barrier(program)) return false;

    for (uint row = program.lane; row < blocks; row += program.lanes)
        prepare_control_flow_predecessor_ranges(row);
    if (!step_barrier(program)) return false;

    for (uint row = program.lane; row < edges; row += program.lanes)
        scatter_control_flow_predecessors(row);

    if (validate)
    {
        if (!step_barrier(program)) return false;
        uint predecessor_total = opt_ir_predecessor_total[0u];
        for (uint row = program.lane; row < blocks; row += program.lanes)
            validate_control_flow_predecessors(row, edges, predecessor_total);
    }
    return true;
}

uint jump_hop_pairs(uint rows)
{
    return uint(firstbithigh(max(1u, rows)) + 12) / 12u;
}

bool analyze_control_flow(inout StepProgram program, bool validate)
{
    uint functions = min(semantic_function_total[0u], gParams.hir_capacity);
    uint blocks = min(opt_ir_block_total[0u], gParams.block_capacity);
    uint edges = min(opt_ir_edge_total[0u], gParams.edge_capacity);
    uint nodes = min(opt_ir_total[0u], gParams.semantic_capacity);

    for (uint row = program.lane; row < functions; row += program.lanes)
        seed_control_flow_functions(row, functions);
    if (!step_barrier(program)) return false;

    for (uint row = program.lane; row < blocks; row += program.lanes)
        summarize_control_flow_functions(row, blocks, functions, nodes);
    if (!step_barrier(program)) return false;

    for (uint row = program.lane; row < functions; row += program.lanes)
        finalize_control_flow_functions(row, functions);
    if (!step_barrier(program)) return false;

    for (uint row = program.lane; row < blocks; row += program.lanes)
        seed_control_flow_reachability(row, blocks, edges, functions);
    if (!step_barrier(program)) return false;

    for (uint row = program.lane; row < blocks; row += program.lanes)
        close_control_flow_reachability(row, blocks, edges);
    if (validate)
    {
        if (!step_barrier(program)) return false;
        for (uint row = program.lane; row < blocks; row += program.lanes)
            validate_control_flow_reachability(row, blocks, edges, functions);
        for (uint row = program.lane; row < edges; row += program.lanes)
            validate_dominator_edges(row, edges, blocks);
        for (uint row = program.lane; row < blocks; row += program.lanes)
            seed_immediate_dominators(row, blocks, functions);
        if (!step_barrier(program)) return false;

        for (uint row = program.lane; row < blocks; row += program.lanes)
            resolve_immediate_dominators(row, blocks, edges);
        if (!step_barrier(program)) return false;

        for (uint row = program.lane; row < blocks; row += program.lanes)
            validate_immediate_dominators(row, blocks, functions);
        if (!step_barrier(program)) return false;

        for (uint row = program.lane; row < blocks; row += program.lanes)
            count_dominator_children(row, blocks);
        if (!step_barrier(program)) return false;

        if (!step_program_prefix_scan(program, blocks, opt_ir_edge_count_by_block,
                opt_ir_predecessor_cursor, opt_ir_predecessor_total, scan_group_sums)) return false;
        if (!step_barrier(program)) return false;

        uint children = min(opt_ir_predecessor_total[0u], blocks);
        for (uint row = program.lane; row < blocks; row += program.lanes)
            prepare_dominator_child_ranges(row, blocks);
        if (!step_barrier(program)) return false;

        for (uint row = program.lane; row < blocks; row += program.lanes)
            scatter_dominator_children(row, blocks);
        if (!step_barrier(program)) return false;

        for (uint row = program.lane; row < blocks; row += program.lanes)
            validate_dominator_child_ranges(row, blocks, children);
        if (!step_barrier(program)) return false;

        for (uint row = program.lane; row < children; row += program.lanes)
            index_dominator_tour_child_rows(row, blocks, children);
        if (!step_barrier(program)) return false;

        uint arcs = blocks * 2u;
        for (uint row = program.lane; row < arcs; row += program.lanes)
            seed_dominator_tour(row, blocks, children);
        if (!step_barrier(program)) return false;

        uint tour_pairs = jump_hop_pairs(arcs);
        for (uint pair = 0u; pair < tour_pairs; ++pair)
        {
            for (uint row = program.lane; row < arcs; row += program.lanes)
                propagate_dominator_tour_ranks(row, arcs,
                    opt_ir_dominator_tour_link_a, opt_ir_dominator_tour_link_b);
            if (!step_barrier(program)) return false;
            for (uint row = program.lane; row < arcs; row += program.lanes)
                propagate_dominator_tour_ranks(row, arcs,
                    opt_ir_dominator_tour_link_b, opt_ir_dominator_tour_link_a);
            if (!step_barrier(program)) return false;
        }

        for (uint row = program.lane; row < blocks; row += program.lanes)
            publish_dominator_tour(row, blocks, functions);
        if (!step_barrier(program)) return false;

        for (uint row = program.lane; row < blocks; row += program.lanes)
            invert_dominator_preorder(row, blocks);
        if (!step_barrier(program)) return false;

        for (uint row = program.lane; row < blocks; row += program.lanes)
            validate_dominator_preorder(row, blocks, functions);
        if (!step_barrier(program)) return false;

        uint depth_pairs = jump_hop_pairs(blocks);
        for (uint pair = 0u; pair < depth_pairs; ++pair)
        {
            for (uint row = program.lane; row < blocks; row += program.lanes)
                propagate_dominator_depths(row, blocks,
                    opt_ir_dominator_depth_link_a, opt_ir_dominator_depth_link_b);
            if (!step_barrier(program)) return false;
            for (uint row = program.lane; row < blocks; row += program.lanes)
                propagate_dominator_depths(row, blocks,
                    opt_ir_dominator_depth_link_b, opt_ir_dominator_depth_link_a);
            if (!step_barrier(program)) return false;
        }

        for (uint row = program.lane; row < blocks; row += program.lanes)
            publish_dominator_depths(row, blocks);
        if (!step_barrier(program)) return false;
        for (uint row = program.lane; row < blocks; row += program.lanes)
            validate_dominator_depths(row, blocks);
        for (uint row = program.lane; row < nodes; row += program.lanes)
            mark_control_flow_regions(row, nodes);
        for (uint row = program.lane; row < functions; row += program.lanes)
            clear_function_region_ranges(row, functions);
        // Leaves start at nodes. Clear only the part of the tree this job uses.
        for (uint row = program.lane; row < nodes * 2u; row += program.lanes)
            opt_ir_region_ownership_tree[row] = 0u;
        if (!step_barrier(program)) return false;

        if (!step_program_prefix_scan(program, nodes, opt_ir_block_start_flag,
                opt_ir_block_prefix, opt_ir_region_total, scan_group_sums)) return false;
        if (!step_barrier(program)) return false;

        uint regions = min(opt_ir_region_total[0u], gParams.block_capacity);
        for (uint row = program.lane; row < nodes; row += program.lanes)
            scatter_control_flow_regions(row, nodes, regions, blocks);
        if (!step_barrier(program)) return false;

        for (uint row = program.lane; row < regions; row += program.lanes)
            seed_region_parents(row, regions);
        if (!step_barrier(program)) return false;

        // Use the same capacity bound as the previous fixed schedule.
        uint region_pairs = uint(firstbithigh(max(1u, gParams.block_capacity)) + 2) / 2u;
        for (uint pair = 0u; pair < region_pairs; ++pair)
        {
            for (uint row = program.lane; row < regions; row += program.lanes)
                propagate_region_parents(row, regions,
                    opt_ir_region_parent_link_a, opt_ir_region_parent_link_b);
            if (!step_barrier(program)) return false;
            for (uint row = program.lane; row < regions; row += program.lanes)
                propagate_region_parents(row, regions,
                    opt_ir_region_parent_link_b, opt_ir_region_parent_link_a);
            if (!step_barrier(program)) return false;
        }

        for (uint row = program.lane; row < regions; row += program.lanes)
        {
            finalize_control_flow_regions(row, regions, functions);
            write_region_ownership_ranges(row, regions, nodes);
        }
        if (!step_barrier(program)) return false;

        for (uint row = program.lane; row < functions; row += program.lanes)
            finalize_function_region_ranges(row, functions, regions);
        for (uint row = program.lane; row < nodes; row += program.lanes)
            assign_nodes_to_regions(row, nodes, blocks, regions);
        for (uint row = program.lane; row < blocks; row += program.lanes)
            assign_blocks_to_regions(row, blocks, regions, nodes);
        if (!step_barrier(program)) return false;

        for (uint row = program.lane; row < edges; row += program.lanes)
            validate_region_edges(row, edges, blocks, functions);
    }
    return true;
}

[shader("compute")]
[numthreads(STEP_PROGRAM_GROUP_LANES, 1, 1)]
void main(uint3 group : SV_GroupID, uint3 local : SV_GroupThreadID)
{
    StepProgram program = step_program_begin(group, local, program_launch.groups, program_launch.slot);
    bool validate = program_launch.validate != 0u;
    if (!construct_control_flow(program, validate)) return;
    if (!step_barrier(program)) return;
    if (!analyze_control_flow(program, validate)) return;
    step_program_end(program);
}
