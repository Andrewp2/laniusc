import codegen.lir.optimization_ir;
import codegen.lir.optimization.demands.demand_steps;
import radix.radix_digits;
import shared.collectives.step_program;
import shared.collectives.program_prefix_scan;
import shared.collectives.program_radix_sort;

struct Launch
{
    uint groups;
    uint slot;
    uint validate;
    uint reserved;
};

ConstantBuffer<Launch> program_launch;
RWStructuredBuffer<uint> scan_group_sums;

uint width(uint capacity)
{
    return uint(firstbithigh(max(1u, capacity - 1u)) + 1);
}

struct DemandKey : IStepProgramRadixKey
{
    static uint digit(uint row, uint step)
    {
        OptIrSsaDemand demand = opt_ir_ssa_demands[row];
        return radix_packed_u32x2_variable_bit_key(demand.block, demand.declaration,
            width(gParams.block_capacity), width(gParams.declaration_capacity), step);
    }
};

[shader("compute")]
[numthreads(STEP_PROGRAM_GROUP_LANES, 1, 1)]
void main(uint3 group : SV_GroupID, uint3 local : SV_GroupThreadID)
{
    StepProgram program = step_program_begin(group, local, program_launch.groups, program_launch.slot);
    bool validate = program_launch.validate != 0u;
    uint raw_declaration_blocks = opt_ir_declaration_block_total[0u];
    uint declaration_rows = min(raw_declaration_blocks, gParams.access_capacity);
    uint declaration_blocks = min(raw_declaration_blocks, gParams.declaration_block_capacity);
    uint blocks = min(opt_ir_block_total[0u], gParams.block_capacity);
    uint edges = min(opt_ir_edge_total[0u], gParams.edge_capacity);
    uint accesses = min(opt_ir_access_total[0u], gParams.access_capacity);
    for (uint row = program.lane; row < declaration_rows; row += program.lanes)
        mark_value_demand_seeds(row, declaration_rows);
    if (!step_barrier(program)) return;

    if (!step_program_prefix_scan(program, declaration_rows, opt_ir_ssa_demand_seed_flag,
            opt_ir_ssa_demand_seed_prefix, opt_ir_ssa_demand_total, scan_group_sums)) return;
    if (!step_barrier(program)) return;

    uint raw_seeds = opt_ir_ssa_demand_total[0u];
    uint seeds = min(raw_seeds, gParams.demand_capacity);
    for (uint row = program.lane; row < declaration_rows; row += program.lanes)
        scatter_value_demand_seeds(row, declaration_rows, accesses);
    uint sparse_capacity = gParams.demand_capacity * 2u + 1u;
    for (uint row = program.lane; row < sparse_capacity; row += program.lanes)
    {
        opt_ir_ssa_sparse_declaration[row] = 0u;
        opt_ir_ssa_sparse_block[row] = 0u;
    }
    if (program.lane == 0u) opt_ir_ssa_demand_seed_total[0u] = raw_seeds;
    if (!step_barrier(program)) return;

    if (validate)
    {
        for (uint row = program.lane; row < declaration_rows; row += program.lanes)
            validate_value_demand_seeds(row, declaration_rows, min(raw_seeds, gParams.access_capacity));
    }
    for (uint row = program.lane; row < seeds; row += program.lanes)
        publish_value_demand_seeds(row, seeds);
    if (!step_barrier(program)) return;

    for (uint row = program.lane; row < seeds; row += program.lanes)
        close_value_demands(row, seeds, blocks, edges, accesses, declaration_blocks);
    if (!step_barrier(program)) return;

    uint demands = min(opt_ir_ssa_demand_total[0u], gParams.demand_capacity);
    uint digits = (width(gParams.block_capacity) + width(gParams.declaration_capacity) + 7u) / 8u;
    if (!step_program_radix_sort<DemandKey>(program, demands, digits, opt_ir_ssa_demand_order,
            demand_order_temporary, demand_histogram, demand_bucket_total)) return;
    if (!step_barrier(program)) return;

    for (uint row = program.lane; row < demands; row += program.lanes)
    {
        if (validate)
            validate_value_demands(row, demands, min(seeds, demands), blocks, edges,
                accesses, declaration_blocks);
        materialize_value_demands(row, demands);
    }
    if (!step_barrier(program)) return;

    // Marking the block argument reads only the demand just committed by
    // this lane. The predecessor lists are inputs of this program.
    for (uint row = program.lane; row < demands; row += program.lanes)
    {
        commit_value_demands(row, demands);
        mark_block_arguments(row, demands, blocks, edges);
    }
    if (!step_barrier(program)) return;

    if (!step_program_prefix_scan(program, demands, opt_ir_ssa_block_argument_flag,
            opt_ir_ssa_block_argument_flag, opt_ir_ssa_block_argument_total, scan_group_sums)) return;
    if (!step_barrier(program)) return;
    if (!step_program_prefix_scan(program, demands, opt_ir_ssa_block_argument_incoming_count,
            opt_ir_ssa_block_argument_incoming_count, opt_ir_ssa_block_argument_incoming_total,
            scan_group_sums)) return;
    if (!step_barrier(program)) return;

    uint raw_arguments = opt_ir_ssa_block_argument_total[0u];
    uint raw_incoming = opt_ir_ssa_block_argument_incoming_total[0u];
    uint arguments = min(raw_arguments, gParams.demand_capacity);
    uint incoming = min(raw_incoming, gParams.incoming_capacity);
    for (uint row = program.lane; row < demands; row += program.lanes)
        scatter_block_arguments(row, demands, raw_arguments, raw_incoming, blocks,
            edges, accesses, declaration_blocks);
    if (!step_barrier(program)) return;

    for (uint row = program.lane; row < demands; row += program.lanes)
    {
        if (validate)
            validate_block_arguments(row, demands, blocks, edges, accesses,
                declaration_blocks, arguments, incoming);
        resolve_value_demand_aliases(row, demands, opt_ir_ssa_block_argument_incoming_count,
            opt_ir_ssa_demand_resolution_tmp, false);
    }
    if (!step_barrier(program)) return;

    for (uint row = program.lane; row < demands; row += program.lanes)
        resolve_value_demand_aliases(row, demands, opt_ir_ssa_demand_resolution_tmp,
            opt_ir_ssa_block_argument_incoming_count, true);
    for (uint row = program.lane; row < arguments; row += program.lanes)
        opt_ir_ssa_block_argument_user_count[row] = 0u;
    if (!step_barrier(program)) return;

    if (validate)
    {
        for (uint row = program.lane; row < demands; row += program.lanes)
            validate_value_demand_aliases(row, demands, blocks, edges, accesses, arguments);
    }
    for (uint row = program.lane; row < arguments; row += program.lanes)
        count_block_argument_users(row, arguments, incoming, accesses, demands);
    if (!step_barrier(program)) return;

    if (!step_program_prefix_scan(program, arguments, opt_ir_ssa_block_argument_user_count,
            opt_ir_ssa_block_argument_user_prefix, opt_ir_ssa_block_argument_user_total,
            scan_group_sums)) return;
    if (!step_barrier(program)) return;

    uint raw_users = opt_ir_ssa_block_argument_user_total[0u];
    uint users = min(raw_users, gParams.demand_capacity * 2u);
    for (uint row = program.lane; row < arguments; row += program.lanes)
        opt_ir_ssa_block_argument_user_count[row] = 0u;
    if (!step_barrier(program)) return;

    for (uint row = program.lane; row < arguments; row += program.lanes)
    {
        scatter_block_argument_users(row, arguments, incoming, raw_users);
        seed_trivial_block_arguments(row, arguments, incoming);
    }
    if (!step_barrier(program)) return;

    for (uint row = program.lane; row < arguments; row += program.lanes)
        propagate_trivial_block_arguments(row, arguments, users);
    if (!step_barrier(program)) return;

    for (uint row = program.lane; row < arguments; row += program.lanes)
        finalize_trivial_block_arguments(row, arguments);
    if (validate)
    {
        if (!step_barrier(program)) return;
        for (uint row = program.lane; row < arguments; row += program.lanes)
            validate_trivial_block_arguments(row, arguments, accesses, incoming, users);
    }
    step_program_end(program);
}
