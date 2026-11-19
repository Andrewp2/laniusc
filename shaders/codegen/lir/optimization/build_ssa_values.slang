import codegen.lir.optimization.ssa_value_steps;
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

struct UseKey : IStepProgramRadixKey
{
    static uint digit(uint row, uint step)
    {
        return radix_byte_key(opt_ir_ssa_use_values[row], step);
    }
};

[shader("compute")]
[numthreads(STEP_PROGRAM_GROUP_LANES, 1, 1)]
void main(uint3 group : SV_GroupID, uint3 local : SV_GroupThreadID)
{
    StepProgram program = step_program_begin(group, local, program_launch.groups, program_launch.slot);
    bool validate = program_launch.validate != 0u;
    uint nodes = min(opt_ir_total[0u], gParams.semantic_capacity);
    uint arguments = min(opt_ir_ssa_block_argument_total[0u], gParams.block_argument_capacity);
    uint parameters = min(semantic_param_total[0u], gParams.parameter_capacity);
    uint calls = min(semantic_lir_call_arg_total[0u], gParams.call_argument_capacity);
    uint aggregates = min(semantic_lir_aggregate_element_total[0u], gParams.aggregate_element_capacity);
    uint incoming = min(opt_ir_ssa_block_argument_incoming_total[0u], gParams.incoming_capacity);
    uint accesses = opt_ir_access_total[0u];
    uint value_rows = max(parameters, max(nodes, arguments));
    for (uint row = program.lane; row < max(nodes, arguments); row += program.lanes)
        mark_ssa_values(row, nodes, arguments);
    if (!step_barrier(program)) return;

    if (!step_program_prefix_scan(program, nodes, opt_ir_ssa_node_value_flag,
            opt_ir_ssa_node_value_flag, opt_ir_ssa_node_value_total, scan_group_sums)) return;
    if (!step_barrier(program)) return;
    if (!step_program_prefix_scan(program, arguments, opt_ir_ssa_block_argument_value_flag,
            opt_ir_ssa_block_argument_value_flag, opt_ir_ssa_surviving_block_argument_total,
            scan_group_sums)) return;
    if (!step_barrier(program)) return;

    uint node_values = opt_ir_ssa_node_value_total[0u];
    uint surviving_arguments = opt_ir_ssa_surviving_block_argument_total[0u];
    for (uint row = program.lane; row < max(1u, value_rows); row += program.lanes)
        scatter_ssa_values(row, parameters, nodes, node_values, arguments, surviving_arguments);
    if (!step_barrier(program)) return;

    uint values = min(opt_ir_ssa_value_total[0u], gParams.value_capacity);
    if (validate)
    {
        for (uint row = program.lane; row < value_rows; row += program.lanes)
            validate_ssa_values(row, parameters, nodes, node_values, arguments, surviving_arguments, values);
    }
    for (uint row = program.lane; row < nodes; row += program.lanes)
        seed_ssa_value_resolution(row, nodes);
    if (!step_barrier(program)) return;

    for (uint row = program.lane; row < accesses; row += program.lanes)
        resolve_ssa_value_reads(row, accesses, nodes, parameters, arguments, values);
    if (!step_barrier(program)) return;

    // A pair covers 64 * 64 hops. The links only point into the node table.
    uint pairs = uint(firstbithigh(max(1u, nodes)) + 12) / 12u;
    for (uint pair = 0u; pair < pairs; ++pair)
    {
        for (uint row = program.lane; row < nodes; row += program.lanes)
            propagate_ssa_value_resolutions(row, nodes, opt_ir_ssa_value_link_a, opt_ir_ssa_value_link_b);
        if (!step_barrier(program)) return;
        for (uint row = program.lane; row < nodes; row += program.lanes)
            propagate_ssa_value_resolutions(row, nodes, opt_ir_ssa_value_link_b, opt_ir_ssa_value_link_a);
        if (!step_barrier(program)) return;
    }

    for (uint row = program.lane; row < nodes; row += program.lanes)
        publish_ssa_value_resolutions(row, nodes, values);
    if (!step_barrier(program)) return;

    if (validate)
    {
        for (uint row = program.lane; row < accesses; row += program.lanes)
            validate_ssa_value_resolutions(row, accesses, nodes, parameters, arguments, values);
    }
    // Consumers address only the active prefixes of these tables.
    uint operand_rows = max(nodes, max(calls, aggregates));
    for (uint row = program.lane; row < operand_rows; row += program.lanes)
        rewrite_operands_to_ssa_values(row, nodes, values);
    for (uint row = program.lane; row < incoming; row += program.lanes)
        rewrite_incoming_block_values(row, incoming);
    if (!step_barrier(program)) return;

    uint use_rows = max(operand_rows, incoming);
    if (validate)
    {
        uint blocks = min(opt_ir_block_total[0u], gParams.block_capacity);
        for (uint row = program.lane; row < operand_rows; row += program.lanes)
            validate_ssa_operands(row, nodes, values, aggregates);
        for (uint row = program.lane; row < max(use_rows, parameters); row += program.lanes)
            validate_operand_dominance(row, nodes, parameters, blocks, arguments,
                incoming, values, min(accesses, gParams.access_capacity), aggregates);
    }
    for (uint row = program.lane; row < operand_rows; row += program.lanes)
        mark_ssa_value_uses(row, nodes, calls, aggregates, values);
    if (!step_barrier(program)) return;

    if (!step_program_prefix_scan(program, nodes, opt_ir_ssa_node_use_count,
            opt_ir_ssa_node_use_count, opt_ir_ssa_node_use_total, scan_group_sums)) return;
    if (!step_barrier(program)) return;
    if (!step_program_prefix_scan(program, calls, opt_ir_ssa_call_use_flag,
            opt_ir_ssa_call_use_flag, opt_ir_ssa_call_use_total, scan_group_sums)) return;
    if (!step_barrier(program)) return;
    if (!step_program_prefix_scan(program, aggregates, opt_ir_ssa_aggregate_use_flag,
            opt_ir_ssa_aggregate_use_flag, opt_ir_ssa_aggregate_use_total, scan_group_sums)) return;
    if (!step_barrier(program)) return;

    uint fixed = opt_ir_ssa_node_use_total[0u];
    uint call_uses = min(opt_ir_ssa_call_use_total[0u], calls);
    uint aggregate_uses = min(opt_ir_ssa_aggregate_use_total[0u], aggregates);
    for (uint row = program.lane; row < max(1u, use_rows); row += program.lanes)
        scatter_ssa_value_uses(row, nodes, fixed, calls, call_uses,
            aggregates, aggregate_uses, incoming, values);
    if (!step_barrier(program)) return;

    uint uses = min(opt_ir_ssa_use_total[0u], gParams.use_capacity);
    if (validate)
    {
        for (uint row = program.lane; row < max(1u, use_rows); row += program.lanes)
            validate_ssa_value_uses(row, nodes, fixed, calls, call_uses,
                aggregates, aggregate_uses, incoming, uses);
    }
    uint digits = uint(firstbithigh(max(1u, gParams.value_capacity - 1u)) + 8) / 8u;
    if (!step_program_radix_sort<UseKey>(program, uses, digits, opt_ir_ssa_use_order,
            use_order_temporary, use_histogram, use_bucket_total)) return;
    if (!step_barrier(program)) return;

    for (uint row = program.lane; row < uses; row += program.lanes)
    {
        if (validate) validate_sorted_ssa_uses(row, uses);
        mark_ssa_use_groups(row, uses);
    }
    if (!step_barrier(program)) return;

    if (!step_program_prefix_scan(program, uses, opt_ir_ssa_use_group_start_flag,
            opt_ir_ssa_use_group_start_flag, opt_ir_ssa_use_group_total, scan_group_sums)) return;
    if (!step_barrier(program)) return;

    uint groups = min(opt_ir_ssa_use_group_total[0u], gParams.value_capacity);
    for (uint row = program.lane; row < uses; row += program.lanes)
        scatter_ssa_use_groups(row, uses);
    if (!step_barrier(program)) return;

    for (uint row = program.lane; row < groups; row += program.lanes)
        finalize_ssa_use_groups(row, groups, uses);
    if (validate)
    {
        if (!step_barrier(program)) return;
        for (uint row = program.lane; row < uses; row += program.lanes)
            validate_ssa_use_groups(row, uses, groups);
    }
    step_program_end(program);
}
