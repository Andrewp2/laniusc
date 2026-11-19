import codegen.lir.optimization_ir;
import codegen.lir.optimization.argument_tables;
import codegen.lir.optimization.access_steps;
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

struct AccessKey : IStepProgramRadixKey
{
    static uint digit(uint row, uint step)
    {
        uint subject_capacity = max(access_params.declaration_capacity, access_params.semantic_capacity);
        uint bits = uint(firstbithigh(max(1u, subject_capacity - 1u)) + 1);
        return radix_packed_u32x2_variable_bit_key(
            opt_ir_accesses[row].subject, opt_ir_access_domain(opt_ir_access_kinds[row]),
            bits, 1u, step);
    }
};

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
            width(demand_params.block_capacity), width(demand_params.declaration_capacity), step);
    }
};

bool construct_declaration_accesses(inout StepProgram program, bool validate)
{
    uint nodes = min(opt_ir_total[0u], access_params.semantic_capacity);
    for (uint row = program.lane; row < nodes; row += program.lanes)
        mark_local_accesses(row, nodes);
    if (!step_barrier(program)) return false;

    if (!step_program_prefix_scan(program, nodes, opt_ir_access_flag, opt_ir_access_prefix,
            opt_ir_instruction_access_total, scan_group_sums)) return false;
    if (!step_barrier(program)) return false;

    uint instruction_accesses = opt_ir_instruction_access_total[0u];
    uint parameters = min(access_params.parameter_capacity, semantic_param_total[0u]);
    uint locals = min(access_params.local_capacity, semantic_local_total[0u]);
    uint functions = min(access_params.hir_capacity, semantic_function_total[0u]);
    for (uint row = program.lane; row < max(1u, max(parameters, locals)); row += program.lanes)
        local_access_layout(row, instruction_accesses, parameters, locals, functions);
    if (!step_barrier(program)) return false;

    uint metadata = min(opt_ir_metadata_access_total[0u], access_params.access_capacity);
    uint accesses = min(opt_ir_access_total[0u], access_params.access_capacity);
    for (uint row = program.lane; row < max(1u, nodes); row += program.lanes)
        scatter_local_accesses(row, nodes, metadata);
    if (!step_barrier(program)) return false;

    if (validate)
    {
        uint blocks = min(access_params.block_capacity, opt_ir_block_total[0u]);
        for (uint row = program.lane; row < accesses; row += program.lanes)
            validate_local_accesses(row, accesses, nodes, blocks, functions, parameters, locals);
    }

    uint subjects = max(access_params.declaration_capacity, access_params.semantic_capacity);
    uint bits = uint(firstbithigh(max(1u, subjects - 1u)) + 1);
    uint digits = (bits + 8u) / 8u;
    if (!step_program_radix_sort<AccessKey>(program, accesses, digits, opt_ir_access_order,
            access_order_temporary, access_histogram, access_bucket_total)) return false;
    if (!step_barrier(program)) return false;

    for (uint row = program.lane; row < accesses; row += program.lanes)
    {
        if (validate) validate_sorted_accesses(row, accesses);
        mark_access_groups(row, accesses);
    }
    if (!step_barrier(program)) return false;

    uint declarations = min(opt_ir_declaration_access_total[0u], accesses);
    if (!step_program_prefix_scan(program, accesses, opt_ir_access_group_start_flag,
            opt_ir_access_group_prefix, opt_ir_access_group_total, scan_group_sums)) return false;
    if (!step_barrier(program)) return false;

    uint groups = min(opt_ir_access_group_total[0u], access_params.declaration_capacity);
    for (uint row = program.lane; row < accesses; row += program.lanes)
        scatter_access_groups(row, accesses);
    if (!step_barrier(program)) return false;

    for (uint row = program.lane; row < groups; row += program.lanes)
        finalize_access_groups(row, groups, accesses, declarations);
    for (uint row = program.lane; row < declarations; row += program.lanes)
        mark_access_declaration_blocks(row, declarations);
    if (!step_barrier(program)) return false;

    for (uint row = program.lane; row < groups; row += program.lanes)
        find_short_access_local_definitions(row, accesses);
    for (uint row = (program.lane / STEP_PROGRAM_GROUP_LANES); row < groups; row += program.groups)
    {
        find_access_local_definitions(row, (program.lane % STEP_PROGRAM_GROUP_LANES), groups, accesses);
        GroupMemoryBarrierWithGroupSync();
    }
    if (!step_program_prefix_scan(program, declarations, opt_ir_access_group_start_flag,
            opt_ir_access_group_prefix, opt_ir_declaration_block_total, scan_group_sums)) return false;
    if (!step_barrier(program)) return false;

    uint declaration_blocks = min(opt_ir_declaration_block_total[0u], access_params.access_capacity);
    if (validate)
    {
        for (uint row = program.lane; row < accesses; row += program.lanes)
            validate_access_local_definitions(row, accesses);
    }
    for (uint row = program.lane; row < declarations; row += program.lanes)
        scatter_access_declaration_blocks(row, declarations, accesses);
    if (!step_barrier(program)) return false;

    for (uint row = program.lane; row < declaration_blocks; row += program.lanes)
    {
        finalize_access_declaration_blocks(row, declaration_blocks, declarations, accesses);
        if (validate)
            validate_access_declaration_blocks(row, declaration_blocks, declarations, accesses);
    }
    return true;
}

bool construct_block_arguments(inout StepProgram program, bool validate)
{
    uint raw_declaration_blocks = opt_ir_declaration_block_total[0u];
    uint declaration_rows = min(raw_declaration_blocks, demand_params.access_capacity);
    uint declaration_blocks = min(raw_declaration_blocks, demand_params.declaration_block_capacity);
    uint blocks = min(opt_ir_block_total[0u], demand_params.block_capacity);
    uint edges = min(opt_ir_edge_total[0u], demand_params.edge_capacity);
    uint accesses = min(opt_ir_access_total[0u], demand_params.access_capacity);
    for (uint row = program.lane; row < declaration_rows; row += program.lanes)
        mark_value_demand_seeds(row, declaration_rows);
    if (!step_barrier(program)) return false;

    if (!step_program_prefix_scan(program, declaration_rows, opt_ir_ssa_demand_seed_flag,
            opt_ir_ssa_demand_seed_prefix, opt_ir_ssa_demand_total, scan_group_sums)) return false;
    if (!step_barrier(program)) return false;

    uint raw_seeds = opt_ir_ssa_demand_total[0u];
    uint seeds = min(raw_seeds, demand_params.demand_capacity);
    for (uint row = program.lane; row < declaration_rows; row += program.lanes)
        scatter_value_demand_seeds(row, declaration_rows, accesses);
    if (!step_barrier(program)) return false;

    if (validate)
    {
        for (uint row = program.lane; row < declaration_rows; row += program.lanes)
            validate_value_demand_seeds(row, declaration_rows, min(raw_seeds, demand_params.access_capacity));
    }
    for (uint row = program.lane; row < seeds; row += program.lanes)
        publish_value_demand_seeds(row, seeds);
    if (!step_barrier(program)) return false;

    for (uint row = program.lane; row < seeds; row += program.lanes)
        close_value_demands(row, seeds, blocks, edges, accesses, declaration_blocks);
    if (!step_barrier(program)) return false;

    uint demands = min(opt_ir_ssa_demand_total[0u], demand_params.demand_capacity);
    uint digits = (width(demand_params.block_capacity) + width(demand_params.declaration_capacity) + 7u) / 8u;
    if (!step_program_radix_sort<DemandKey>(program, demands, digits, opt_ir_ssa_demand_order,
            demand_order_temporary, demand_histogram, demand_bucket_total)) return false;
    if (!step_barrier(program)) return false;

    for (uint row = program.lane; row < demands; row += program.lanes)
    {
        if (validate)
            validate_value_demands(row, demands, min(seeds, demands), blocks, edges,
                accesses, declaration_blocks);
        materialize_value_demands(row, demands);
    }
    if (!step_barrier(program)) return false;

    // Marking the block argument reads only the demand just committed by
    // this lane. The predecessor lists are inputs of this program.
    for (uint row = program.lane; row < demands; row += program.lanes)
    {
        commit_value_demands(row, demands);
        mark_block_arguments(row, demands, blocks, edges);
    }
    if (!step_barrier(program)) return false;

    if (!step_program_prefix_scan(program, demands, opt_ir_ssa_block_argument_flag,
            opt_ir_ssa_block_argument_flag, opt_ir_ssa_block_argument_total, scan_group_sums)) return false;
    if (!step_barrier(program)) return false;
    if (!step_program_prefix_scan(program, demands, opt_ir_ssa_block_argument_incoming_count,
            opt_ir_ssa_block_argument_incoming_count, opt_ir_ssa_block_argument_incoming_total,
            scan_group_sums)) return false;
    if (!step_barrier(program)) return false;

    uint raw_arguments = opt_ir_ssa_block_argument_total[0u];
    uint raw_incoming = opt_ir_ssa_block_argument_incoming_total[0u];
    uint arguments = min(raw_arguments, demand_params.demand_capacity);
    uint incoming = min(raw_incoming, demand_params.incoming_capacity);
    for (uint row = program.lane; row < demands; row += program.lanes)
        scatter_block_arguments(row, demands, raw_arguments, raw_incoming, blocks,
            edges, accesses, declaration_blocks);
    if (!step_barrier(program)) return false;

    for (uint row = program.lane; row < demands; row += program.lanes)
    {
        if (validate)
            validate_block_arguments(row, demands, blocks, edges, accesses,
                declaration_blocks, arguments, incoming);
        resolve_value_demand_aliases(row, demands, opt_ir_ssa_block_argument_incoming_count,
            opt_ir_ssa_demand_resolution_tmp, false);
    }
    if (!step_barrier(program)) return false;

    for (uint row = program.lane; row < demands; row += program.lanes)
        resolve_value_demand_aliases(row, demands, opt_ir_ssa_demand_resolution_tmp,
            opt_ir_ssa_block_argument_incoming_count, true);
    for (uint row = program.lane; row < arguments; row += program.lanes)
        opt_ir_ssa_block_argument_user_count[row] = 0u;
    if (!step_barrier(program)) return false;

    if (validate)
    {
        for (uint row = program.lane; row < demands; row += program.lanes)
            validate_value_demand_aliases(row, demands, blocks, edges, accesses, arguments);
    }
    for (uint row = program.lane; row < arguments; row += program.lanes)
        count_block_argument_users(row, arguments, incoming, accesses, demands);
    if (!step_barrier(program)) return false;

    if (!step_program_prefix_scan(program, arguments, opt_ir_ssa_block_argument_user_count,
            opt_ir_ssa_block_argument_user_prefix, opt_ir_ssa_block_argument_user_total,
            scan_group_sums)) return false;
    if (!step_barrier(program)) return false;

    uint raw_users = opt_ir_ssa_block_argument_user_total[0u];
    uint users = min(raw_users, demand_params.demand_capacity * 2u);
    for (uint row = program.lane; row < arguments; row += program.lanes)
        opt_ir_ssa_block_argument_user_count[row] = 0u;
    if (!step_barrier(program)) return false;

    for (uint row = program.lane; row < arguments; row += program.lanes)
    {
        scatter_block_argument_users(row, arguments, incoming, raw_users);
        seed_trivial_block_arguments(row, arguments, incoming);
    }
    if (!step_barrier(program)) return false;

    for (uint row = program.lane; row < arguments; row += program.lanes)
        propagate_trivial_block_arguments(row, arguments, users);
    if (!step_barrier(program)) return false;

    for (uint row = program.lane; row < arguments; row += program.lanes)
        finalize_trivial_block_arguments(row, arguments);
    if (validate)
    {
        if (!step_barrier(program)) return false;
        for (uint row = program.lane; row < arguments; row += program.lanes)
            validate_trivial_block_arguments(row, arguments, accesses, incoming, users);
    }
    return true;
}

[shader("compute")]
[numthreads(STEP_PROGRAM_GROUP_LANES, 1, 1)]
void main(uint3 group : SV_GroupID, uint3 local : SV_GroupThreadID)
{
    StepProgram program = step_program_begin(group, local, program_launch.groups, program_launch.slot);
    bool validate = program_launch.validate != 0u;
    if (!construct_declaration_accesses(program, validate)) return;
    if (!step_barrier(program)) return;
    if (!construct_block_arguments(program, validate)) return;
    step_program_end(program);
}
