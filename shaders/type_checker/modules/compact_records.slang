import type_checker.modules.records.record_steps;
import shared.collectives.step_program;
import shared.collectives.program_prefix_scan;

struct Launch
{
    uint groups;
    uint slot;
    uint module_capacity;
    uint reserved;
};
ConstantBuffer<Launch> program_launch;

bool scan_record_family(inout StepProgram program, uint hir, uint family,
    RWStructuredBuffer<uint> total)
{
    for (uint row = program.lane; row < hir; row += program.lanes)
        module_record_family_flag[row] = (module_record_family_bits[row] & family) != 0u ? 1u : 0u;
    if (!step_barrier(program)) return false;
    if (!step_program_prefix_scan(program, hir, module_record_family_flag,
            module_record_prefix, total, record_scan_group_sums)) return false;
    return step_barrier(program);
}

[shader("compute")]
[numthreads(STEP_PROGRAM_GROUP_LANES, 1, 1)]
void main(uint3 group : SV_GroupID, uint3 local : SV_GroupThreadID)
{
    StepProgram program = step_program_begin(group, local, program_launch.groups, program_launch.slot);
    uint hir = min(hir_active_count[0u], gParams.n_hir_nodes);
    for (uint row = program.lane; row < gParams.n_tokens; row += program.lanes)
        decl_id_by_name_token[row] = 0xffffffffu;

    if (!scan_record_family(program, hir, 1u, module_record_count_out)) return;
    for (uint row = program.lane; row < hir; row += program.lanes)
        scatter_module_records(row, program_launch.module_capacity);
    if (!step_barrier(program)) return;

    if (!scan_record_family(program, hir, 2u, import_record_count_out)) return;
    for (uint row = program.lane; row < hir; row += program.lanes)
        scatter_import_records(row);
    if (!step_barrier(program)) return;

    if (!scan_record_family(program, hir, 4u, decl_count_out)) return;
    uint variants = min(compact_variant_count[0u], gParams.n_hir_nodes);
    uint total = min(decl_count_out[0u] + variants, gParams.n_hir_nodes);
    uint core = total - variants;
    for (uint row = program.lane; row < hir; row += program.lanes)
    {
        scatter_decl_core_records(row);
        scatter_decl_span_records(row);
    }
    // Publish after every lane has read the original core count.
    if (!step_barrier(program)) return;
    if (program.lane == 0u) decl_count_out[0u] = total;
    for (uint row = program.lane; row < variants; row += program.lanes)
        scatter_variant_decl_records(row, core);
    step_program_end(program);
}
