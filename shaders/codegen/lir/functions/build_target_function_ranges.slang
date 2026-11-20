import codegen.lir.lowering_ir;
import shared.collectives.program_prefix_scan;
import shared.collectives.step_program;

struct Params { uint semantic_capacity; uint target_capacity; uint function_capacity; uint reserved; };
struct Launch { uint groups; uint slot; uint options; uint reserved; };

ConstantBuffer<Params> gParams;
ConstantBuffer<Launch> program_launch;
StructuredBuffer<uint> opt_ir_total;
StructuredBuffer<uint> semantic_schedule_order;
StructuredBuffer<uint> opt_ir_source_hir;
StructuredBuffer<uint> semantic_function_id_by_hir;
RWStructuredBuffer<uint> function_start_flag;
RWStructuredBuffer<uint> function_index_by_semantic;
StructuredBuffer<uint> target_lir_offset;
RWStructuredBuffer<uint> function_prefix;
RWStructuredBuffer<uint> function_start;
RWStructuredBuffer<uint> compact_function_id;
StructuredBuffer<uint> target_lir_total;
RWStructuredBuffer<uint> function_count;
RWStructuredBuffer<TargetLirFunction> target_function;
RWStructuredBuffer<uint> scan_group_sums;

static const uint INVALID = 0xffffffffu;

void mark_start(uint row, uint total)
{
    if (row < gParams.function_capacity)
        function_index_by_semantic[row] = INVALID;
    if (row >= total) return;
    uint semantic_row = semantic_schedule_order[row];
    uint id = semantic_function_id_by_hir[opt_ir_source_hir[semantic_row]];
    uint previous_id = row == 0u ? INVALID
        : semantic_function_id_by_hir[
            opt_ir_source_hir[semantic_schedule_order[row - 1u]]];
    function_start_flag[row] = id != INVALID && (row == 0u || previous_id != id) ? 1u : 0u;
}

void scatter_start(uint row)
{
    if (function_start_flag[row] == 0u) return;
    uint compact = function_prefix[row];
    if (compact >= gParams.function_capacity) return;
    uint semantic_row = semantic_schedule_order[row];
    function_start[compact] = target_lir_offset[row];
    compact_function_id[compact] =
        semantic_function_id_by_hir[opt_ir_source_hir[semantic_row]];
}

void publish_range(uint row, uint count, uint total)
{
    uint start = min(function_start[row], total);
    uint end = row + 1u < count ? min(function_start[row + 1u], total) : total;
    TargetLirFunction out_value;
    out_value.function_id = compact_function_id[row];
    out_value.instruction_start = start;
    out_value.instruction_count = end - start;
    out_value.flags = 0u;
    target_function[row] = out_value;
    if (out_value.function_id < gParams.function_capacity)
        function_index_by_semantic[out_value.function_id] = row;
}

[shader("compute")]
[numthreads(STEP_PROGRAM_GROUP_LANES, 1, 1)]
void main(uint3 group : SV_GroupID, uint3 local : SV_GroupThreadID)
{
    StepProgram program = step_program_begin(group, local, program_launch.groups, program_launch.slot);
    uint rows = min(gParams.semantic_capacity, opt_ir_total[0u]);
    for (uint row = program.lane; row < max(rows, gParams.function_capacity); row += program.lanes)
        mark_start(row, rows);
    if (!step_barrier(program)) return;

    if (!step_program_prefix_scan(program, rows, function_start_flag,
            function_prefix, function_count, scan_group_sums)) return;
    if (!step_barrier(program)) return;

    for (uint row = program.lane; row < rows; row += program.lanes)
        scatter_start(row);
    if (!step_barrier(program)) return;

    uint functions = min(gParams.function_capacity, function_count[0u]);
    uint total = min(gParams.target_capacity, target_lir_total[0u]);
    for (uint row = program.lane; row < functions; row += program.lanes)
        publish_range(row, functions, total);
    step_program_end(program);
}
