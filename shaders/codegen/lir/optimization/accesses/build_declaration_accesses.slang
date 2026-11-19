import codegen.lir.optimization_ir;
import codegen.lir.optimization.accesses.access_steps;
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
        uint subject_capacity = max(gParams.declaration_capacity, gParams.semantic_capacity);
        uint bits = uint(firstbithigh(max(1u, subject_capacity - 1u)) + 1);
        return radix_packed_u32x2_variable_bit_key(
            opt_ir_accesses[row].subject, opt_ir_access_domain(opt_ir_access_kinds[row]),
            bits, 1u, step);
    }
};

[shader("compute")]
[numthreads(STEP_PROGRAM_GROUP_LANES, 1, 1)]
void main(uint3 group : SV_GroupID, uint3 local : SV_GroupThreadID)
{
    StepProgram program = step_program_begin(group, local, program_launch.groups, program_launch.slot);
    uint nodes = min(opt_ir_total[0u], gParams.semantic_capacity);
    for (uint row = program.lane; row < nodes; row += program.lanes)
        mark_local_accesses(row, nodes);
    if (!step_barrier(program)) return;

    if (!step_program_prefix_scan(program, nodes, opt_ir_access_flag, opt_ir_access_prefix,
            opt_ir_instruction_access_total, scan_group_sums)) return;
    if (!step_barrier(program)) return;

    uint instruction_accesses = opt_ir_instruction_access_total[0u];
    uint parameters = min(gParams.parameter_capacity, semantic_param_total[0u]);
    uint locals = min(gParams.local_capacity, semantic_local_total[0u]);
    uint functions = min(gParams.hir_capacity, semantic_function_total[0u]);
    for (uint row = program.lane; row < max(1u, max(parameters, locals)); row += program.lanes)
        local_access_layout(row, instruction_accesses, parameters, locals, functions);
    if (!step_barrier(program)) return;

    uint metadata = min(opt_ir_metadata_access_total[0u], gParams.access_capacity);
    uint accesses = min(opt_ir_access_total[0u], gParams.access_capacity);
    for (uint row = program.lane; row < max(1u, nodes); row += program.lanes)
        scatter_local_accesses(row, nodes, metadata);
    if (!step_barrier(program)) return;

    if (program_launch.validate != 0u)
    {
        uint blocks = min(gParams.block_capacity, opt_ir_block_total[0u]);
        for (uint row = program.lane; row < accesses; row += program.lanes)
            validate_local_accesses(row, accesses, nodes, blocks, functions, parameters, locals);
    }

    uint subjects = max(gParams.declaration_capacity, gParams.semantic_capacity);
    uint bits = uint(firstbithigh(max(1u, subjects - 1u)) + 1);
    uint digits = (bits + 8u) / 8u;
    if (!step_program_radix_sort<AccessKey>(program, accesses, digits, opt_ir_access_order,
            access_order_temporary, access_histogram, access_bucket_total)) return;
    if (!step_barrier(program)) return;

    for (uint row = program.lane; row < accesses; row += program.lanes)
    {
        if (program_launch.validate != 0u) validate_sorted_accesses(row, accesses);
        mark_access_groups(row, accesses);
    }
    if (!step_barrier(program)) return;

    uint declarations = min(opt_ir_declaration_access_total[0u], accesses);
    if (!step_program_prefix_scan(program, accesses, opt_ir_access_group_start_flag,
            opt_ir_access_group_prefix, opt_ir_access_group_total, scan_group_sums)) return;
    if (!step_barrier(program)) return;

    uint groups = min(opt_ir_access_group_total[0u], gParams.declaration_capacity);
    for (uint row = program.lane; row < accesses; row += program.lanes)
        scatter_access_groups(row, accesses);
    if (!step_barrier(program)) return;

    for (uint row = program.lane; row < groups; row += program.lanes)
        finalize_access_groups(row, groups, accesses, declarations);
    for (uint row = program.lane; row < declarations; row += program.lanes)
        mark_access_declaration_blocks(row, declarations);
    if (!step_barrier(program)) return;

    for (uint row = group.x; row < groups; row += program.groups)
    {
        find_access_local_definitions(row, local.x, groups, accesses);
        GroupMemoryBarrierWithGroupSync();
    }
    if (!step_program_prefix_scan(program, declarations, opt_ir_access_group_start_flag,
            opt_ir_access_group_prefix, opt_ir_declaration_block_total, scan_group_sums)) return;
    if (!step_barrier(program)) return;

    uint declaration_blocks = min(opt_ir_declaration_block_total[0u], gParams.access_capacity);
    if (program_launch.validate != 0u)
    {
        for (uint row = program.lane; row < accesses; row += program.lanes)
            validate_access_local_definitions(row, accesses);
    }
    for (uint row = program.lane; row < declarations; row += program.lanes)
        scatter_access_declaration_blocks(row, declarations, accesses);
    if (!step_barrier(program)) return;

    for (uint row = program.lane; row < declaration_blocks; row += program.lanes)
    {
        finalize_access_declaration_blocks(row, declaration_blocks, declarations, accesses);
        if (program_launch.validate != 0u)
            validate_access_declaration_blocks(row, declaration_blocks, declarations, accesses);
    }
    step_program_end(program);
}
