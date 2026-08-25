import codegen.lowering_ir;
import codegen.optimization_ir;
import gpu_index;
import radix;

struct Params
{
    uint semantic_capacity;
    uint hir_capacity;
    uint block_capacity;
    uint access_capacity;
    uint declaration_capacity;
    uint parameter_capacity;
    uint local_capacity;
    uint reserved;
};

ConstantBuffer<Params> gParams;
StructuredBuffer<uint> opt_ir_instruction_access_total;
StructuredBuffer<uint> semantic_function_total;
StructuredBuffer<uint> semantic_param_total;
StructuredBuffer<SemanticLirParam> semantic_params;
StructuredBuffer<uint> semantic_local_total;
StructuredBuffer<SemanticLirLocal> semantic_locals;
StructuredBuffer<OptIrFunction> opt_ir_functions;
RWStructuredBuffer<uint> opt_ir_access_total;
RWStructuredBuffer<uint> opt_ir_metadata_access_total;
RWStructuredBuffer<uint> opt_ir_declaration_access_total;
RWStructuredBuffer<OptIrAccessCore> opt_ir_accesses;
RWStructuredBuffer<uint> opt_ir_access_source_rows;
RWStructuredBuffer<uint> opt_ir_access_positions;
RWStructuredBuffer<uint> opt_ir_access_kinds;
RWStructuredBuffer<uint> opt_ir_access_radix_dispatch_args;
RWStructuredBuffer<LoweringStatus> lowering_status;

static const uint INVALID = 0xffffffffu;
static const uint DISPATCH_X_STRIDE = 16776960u;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

uint saturating_add(uint lhs, uint rhs)
{
    return lhs > 0xffffffffu - rhs ? 0xffffffffu : lhs + rhs;
}

void report_capacity(uint required)
{
    InterlockedOr(lowering_status[0u].flags,
        LOWERING_STATUS_OPTIMIZATION_CAPACITY);
    InterlockedMax(lowering_status[0u].required_capacity, required);
    lowering_status[0u].available_capacity = gParams.access_capacity;
}

void write_metadata_access(uint access_id, uint subject, uint source_row,
    uint function_id, uint kind, uint function_total)
{
    if (access_id >= gParams.access_capacity) return;
    OptIrAccessCore access;
    access.subject = subject;
    if (function_id < function_total)
    {
        OptIrFunction function = opt_ir_functions[function_id];
        access.block_id = function.entry_block;
        opt_ir_access_positions[access_id] = function.node_start;
    }
    else
    {
        access.block_id = INVALID;
        opt_ir_access_positions[access_id] = 0u;
    InterlockedOr(lowering_status[0u].flags,
        LOWERING_STATUS_OPTIMIZATION_STRUCTURE);
    }
    opt_ir_accesses[access_id] = access;
    opt_ir_access_source_rows[access_id] = source_row;
    opt_ir_access_kinds[access_id] = kind;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint row = linear_dispatch_thread_id_2d(dtid, DISPATCH_X_STRIDE);
    uint instruction_total = opt_ir_instruction_access_total[0u];
    uint param_total = min(gParams.parameter_capacity, semantic_param_total[0u]);
    uint local_total = min(gParams.local_capacity, semantic_local_total[0u]);
    uint metadata_total = saturating_add(param_total, local_total);
    uint final_total = saturating_add(metadata_total, instruction_total);
    uint function_total = min(gParams.hir_capacity, semantic_function_total[0u]);
    if (row == 0u)
    {
        uint active_total = min(final_total, gParams.access_capacity);
        opt_ir_metadata_access_total[0u] = min(metadata_total, active_total);
        opt_ir_access_total[0u] = active_total;
        // The group-mark pass lowers this to the first memory-domain row with
        // an atomic min after the stable radix ordering.
        opt_ir_declaration_access_total[0u] = active_total;
        uint blocks = max(radix_active_block_count(
            active_total, gParams.reserved, WG_SIZE), 1u);
        opt_ir_access_radix_dispatch_args[0u] = min(blocks, MAX_GROUPS_X);
        opt_ir_access_radix_dispatch_args[1u] =
            (blocks + MAX_GROUPS_X - 1u) / MAX_GROUPS_X;
        opt_ir_access_radix_dispatch_args[2u] = 1u;
        if (final_total > gParams.access_capacity)
            report_capacity(final_total);
    }

    if (row < param_total)
    {
        SemanticLirParam param = semantic_params[row];
        write_metadata_access(row, param.declaration_id,
            row, param.function_id, OPT_IR_ACCESS_PARAMETER_DEFINITION,
            function_total);
    }
    if (row < local_total)
    {
        SemanticLirLocal local = semantic_locals[row];
        write_metadata_access(param_total + row,
            local.declaration_id, row, local.function_id,
            OPT_IR_ACCESS_LOCAL_DECLARATION, function_total);
    }
}
