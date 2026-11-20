import shared.syntax.hir_records;
import shared.collectives.program_prefix_scan;
import shared.collectives.step_program;

struct Params { uint n_hir_nodes; uint param_capacity; uint n_tokens; uint reserved; };
ConstantBuffer<Params> gParams;
StructuredBuffer<uint> compact_param_count;
StructuredBuffer<HirParam> compact_params;
StructuredBuffer<uint> semantic_function_flag;
RWStructuredBuffer<uint> semantic_param_flag;

StructuredBuffer<uint> compact_hir_count;
RWStructuredBuffer<uint> semantic_function_prefix;
RWStructuredBuffer<uint> semantic_function_total;
RWStructuredBuffer<uint> semantic_param_prefix;
RWStructuredBuffer<uint> semantic_param_total;
RWStructuredBuffer<uint> scan_group_sums;

struct Launch { uint groups; uint slot; uint options; uint reserved; };
ConstantBuffer<Launch> program_launch;

void mark_parameter(uint row)
{
    uint owner = compact_params[row].owner;
    semantic_param_flag[row] = owner < gParams.n_hir_nodes &&
        semantic_function_flag[owner] != 0u ? 1u : 0u;
}

[shader("compute")]
[numthreads(STEP_PROGRAM_GROUP_LANES, 1, 1)]
void main(uint3 group : SV_GroupID, uint3 local : SV_GroupThreadID)
{
    StepProgram program = step_program_begin(group, local, program_launch.groups, program_launch.slot);
    uint parameters = min(compact_param_count[0u], gParams.param_capacity);
    uint nodes = min(compact_hir_count[0u], gParams.n_hir_nodes);
    for (uint row = program.lane; row < parameters; row += program.lanes)
        mark_parameter(row);
    if (!step_program_prefix_scan(program, nodes, semantic_function_flag,
            semantic_function_prefix, semantic_function_total, scan_group_sums)) return;
    if (!step_barrier(program)) return;

    if (!step_program_prefix_scan(program, parameters, semantic_param_flag,
            semantic_param_prefix, semantic_param_total, scan_group_sums)) return;
    step_program_end(program);
}
