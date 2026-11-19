import codegen.lir.optimization.structure_tables;
import codegen.lir.optimization.control_flow.reachability_steps;
import codegen.lir.optimization.dominance.dominance_steps;
import codegen.lir.optimization.regions.regions_steps;
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

uint jump_hop_pairs(uint rows)
{
    return uint(firstbithigh(max(1u, rows)) + 12) / 12u;
}

[shader("compute")]
[numthreads(STEP_PROGRAM_GROUP_LANES, 1, 1)]
void main(uint3 group : SV_GroupID, uint3 local : SV_GroupThreadID)
{
    StepProgram program = step_program_begin(group, local, program_launch.groups, program_launch.slot);
    uint functions = min(semantic_function_total[0u], gParams.hir_capacity);
    uint blocks = min(opt_ir_block_total[0u], gParams.block_capacity);
    uint edges = min(opt_ir_edge_total[0u], gParams.edge_capacity);
    uint nodes = min(opt_ir_total[0u], gParams.semantic_capacity);

    for (uint row = program.lane; row < functions; row += program.lanes)
        seed_control_flow_functions(row, functions);
    if (!step_barrier(program)) return;

    for (uint row = program.lane; row < blocks; row += program.lanes)
        summarize_control_flow_functions(row, blocks, functions, nodes);
    if (!step_barrier(program)) return;

    for (uint row = program.lane; row < functions; row += program.lanes)
        finalize_control_flow_functions(row, functions);
    if (!step_barrier(program)) return;

    for (uint row = program.lane; row < blocks; row += program.lanes)
        seed_control_flow_reachability(row, blocks, edges, functions);
    if (!step_barrier(program)) return;

    for (uint row = program.lane; row < blocks; row += program.lanes)
        close_control_flow_reachability(row, blocks, edges);
    if (program_launch.validate != 0u)
    {
        if (!step_barrier(program)) return;
        for (uint row = program.lane; row < blocks; row += program.lanes)
            validate_control_flow_reachability(row, blocks, edges, functions);
        for (uint row = program.lane; row < edges; row += program.lanes)
            validate_dominator_edges(row, edges, blocks);
        for (uint row = program.lane; row < blocks; row += program.lanes)
            seed_immediate_dominators(row, blocks, functions);
        if (!step_barrier(program)) return;

        for (uint row = program.lane; row < blocks; row += program.lanes)
            resolve_immediate_dominators(row, blocks, edges);
        if (!step_barrier(program)) return;

        for (uint row = program.lane; row < blocks; row += program.lanes)
            validate_immediate_dominators(row, blocks, functions);
        if (!step_barrier(program)) return;

        for (uint row = program.lane; row < blocks; row += program.lanes)
            count_dominator_children(row, blocks);
        if (!step_barrier(program)) return;

        if (!step_program_prefix_scan(program, blocks, opt_ir_live_predecessor_count_by_block,
                opt_ir_dominator_child_prefix, opt_ir_dominator_child_total, scan_group_sums)) return;
        if (!step_barrier(program)) return;

        uint children = min(opt_ir_dominator_child_total[0u], blocks);
        for (uint row = program.lane; row < blocks; row += program.lanes)
            prepare_dominator_child_ranges(row, blocks);
        if (!step_barrier(program)) return;

        for (uint row = program.lane; row < blocks; row += program.lanes)
            scatter_dominator_children(row, blocks);
        if (!step_barrier(program)) return;

        for (uint row = program.lane; row < blocks; row += program.lanes)
            validate_dominator_child_ranges(row, blocks, children);
        if (!step_barrier(program)) return;

        for (uint row = program.lane; row < children; row += program.lanes)
            index_dominator_tour_child_rows(row, blocks, children);
        if (!step_barrier(program)) return;

        uint arcs = blocks * 2u;
        for (uint row = program.lane; row < arcs; row += program.lanes)
            seed_dominator_tour(row, blocks, children);
        if (!step_barrier(program)) return;

        uint tour_pairs = jump_hop_pairs(arcs);
        for (uint pair = 0u; pair < tour_pairs; ++pair)
        {
            for (uint row = program.lane; row < arcs; row += program.lanes)
                propagate_dominator_tour_ranks(row, arcs,
                    opt_ir_dominator_tour_link_a, opt_ir_dominator_tour_link_b);
            if (!step_barrier(program)) return;
            for (uint row = program.lane; row < arcs; row += program.lanes)
                propagate_dominator_tour_ranks(row, arcs,
                    opt_ir_dominator_tour_link_b, opt_ir_dominator_tour_link_a);
            if (!step_barrier(program)) return;
        }

        for (uint row = program.lane; row < blocks; row += program.lanes)
            publish_dominator_tour(row, blocks, functions);
        if (!step_barrier(program)) return;

        for (uint row = program.lane; row < blocks; row += program.lanes)
            invert_dominator_preorder(row, blocks);
        if (!step_barrier(program)) return;

        for (uint row = program.lane; row < blocks; row += program.lanes)
            validate_dominator_preorder(row, blocks, functions);
        if (!step_barrier(program)) return;

        uint depth_pairs = jump_hop_pairs(blocks);
        for (uint pair = 0u; pair < depth_pairs; ++pair)
        {
            for (uint row = program.lane; row < blocks; row += program.lanes)
                propagate_dominator_depths(row, blocks,
                    opt_ir_dominator_depth_link_a, opt_ir_dominator_depth_link_b);
            if (!step_barrier(program)) return;
            for (uint row = program.lane; row < blocks; row += program.lanes)
                propagate_dominator_depths(row, blocks,
                    opt_ir_dominator_depth_link_b, opt_ir_dominator_depth_link_a);
            if (!step_barrier(program)) return;
        }

        for (uint row = program.lane; row < blocks; row += program.lanes)
            publish_dominator_depths(row, blocks);
        if (!step_barrier(program)) return;
        for (uint row = program.lane; row < blocks; row += program.lanes)
            validate_dominator_depths(row, blocks);
        for (uint row = program.lane; row < nodes; row += program.lanes)
            mark_control_flow_regions(row, nodes);
        for (uint row = program.lane; row < functions; row += program.lanes)
            clear_function_region_ranges(row, functions);
        for (uint row = program.lane; row < gParams.semantic_capacity * 2u; row += program.lanes)
            clear_region_owners(row);
        if (!step_barrier(program)) return;

        if (!step_program_prefix_scan(program, nodes, opt_ir_region_start_flag,
                opt_ir_region_prefix, opt_ir_region_total, scan_group_sums)) return;
        if (!step_barrier(program)) return;

        uint regions = min(opt_ir_region_total[0u], gParams.block_capacity);
        for (uint row = program.lane; row < nodes; row += program.lanes)
            scatter_control_flow_regions(row, nodes, regions, blocks);
        if (!step_barrier(program)) return;

        for (uint row = program.lane; row < regions; row += program.lanes)
            seed_region_parents(row, regions);
        if (!step_barrier(program)) return;

        // Use the same capacity bound as the previous fixed schedule.
        uint region_pairs = uint(firstbithigh(max(1u, gParams.block_capacity)) + 2) / 2u;
        for (uint pair = 0u; pair < region_pairs; ++pair)
        {
            for (uint row = program.lane; row < regions; row += program.lanes)
                propagate_region_parents(row, regions,
                    opt_ir_region_parent_link_a, opt_ir_region_parent_link_b);
            if (!step_barrier(program)) return;
            for (uint row = program.lane; row < regions; row += program.lanes)
                propagate_region_parents(row, regions,
                    opt_ir_region_parent_link_b, opt_ir_region_parent_link_a);
            if (!step_barrier(program)) return;
        }

        for (uint row = program.lane; row < regions; row += program.lanes)
        {
            finalize_control_flow_regions(row, regions, functions);
            write_region_ownership_ranges(row, regions);
        }
        if (!step_barrier(program)) return;

        for (uint row = program.lane; row < functions; row += program.lanes)
            finalize_function_region_ranges(row, functions, regions);
        for (uint row = program.lane; row < nodes; row += program.lanes)
            assign_nodes_to_regions(row, nodes, blocks, regions);
        for (uint row = program.lane; row < blocks; row += program.lanes)
            assign_blocks_to_regions(row, blocks, regions);
        if (!step_barrier(program)) return;

        for (uint row = program.lane; row < edges; row += program.lanes)
            validate_region_edges(row, edges, blocks, functions);
    }
    step_program_end(program);
}
