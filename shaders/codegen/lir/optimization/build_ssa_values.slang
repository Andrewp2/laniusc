import codegen.lir.optimization.ssa_value_steps;
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

    if (validate)
    {
        uint blocks = min(opt_ir_block_total[0u], gParams.block_capacity);
        for (uint row = program.lane; row < operand_rows; row += program.lanes)
            validate_ssa_operands(row, nodes, values, aggregates);
        for (uint row = program.lane; row < max(max(operand_rows, incoming), parameters); row += program.lanes)
            validate_operand_dominance(row, nodes, parameters, blocks, arguments,
                incoming, values, min(accesses, gParams.access_capacity), aggregates);
    }
    step_program_end(program);
}
