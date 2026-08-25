import codegen.lowering_ir;
import codegen.optimization_ir;
import gpu_index;

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
StructuredBuffer<uint> opt_ir_total;
StructuredBuffer<uint> opt_ir_block_total;
StructuredBuffer<uint> opt_ir_access_total;
StructuredBuffer<OptIrNodeControl> opt_ir_control;
StructuredBuffer<uint> opt_ir_position_by_node;
StructuredBuffer<OptIrBlock> opt_ir_blocks;
StructuredBuffer<uint> semantic_function_total;
StructuredBuffer<OptIrFunction> opt_ir_functions;
StructuredBuffer<uint> semantic_param_total;
StructuredBuffer<SemanticLirParam> semantic_params;
StructuredBuffer<uint> semantic_local_total;
StructuredBuffer<SemanticLirLocal> semantic_locals;
StructuredBuffer<OptIrAccessCore> opt_ir_accesses;
StructuredBuffer<uint> opt_ir_access_source_rows;
StructuredBuffer<uint> opt_ir_access_positions;
StructuredBuffer<uint> opt_ir_access_kinds;
RWStructuredBuffer<LoweringStatus> lowering_status;

static const uint INVALID = 0xffffffffu;
static const uint DISPATCH_X_STRIDE = 16776960u;

void report_structure_failure(uint node)
{
    InterlockedOr(lowering_status[0u].flags,
        LOWERING_STATUS_OPTIMIZATION_STRUCTURE);
    InterlockedMin(lowering_status[0u].first_unsupported_opt_row, node);
}

bool valid_function_position(uint function_id, uint block_id, uint position,
    uint function_total, uint block_total)
{
    if (function_id >= function_total) return false;
    OptIrFunction function = opt_ir_functions[function_id];
    if (function.entry_block == INVALID)
        return block_id == INVALID && position == 0u;
    return block_id >= function.block_start &&
        block_id < function.block_start + function.block_count &&
        block_id < block_total && position >= function.node_start &&
        position < function.node_start + function.node_count;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint access_id = linear_dispatch_thread_id_2d(dtid, DISPATCH_X_STRIDE);
    uint access_total = min(gParams.access_capacity, opt_ir_access_total[0u]);
    if (access_id >= access_total) return;

    uint node_total = min(gParams.semantic_capacity, opt_ir_total[0u]);
    uint block_total = min(gParams.block_capacity, opt_ir_block_total[0u]);
    uint function_total = min(gParams.hir_capacity, semantic_function_total[0u]);
    uint param_total = min(gParams.parameter_capacity, semantic_param_total[0u]);
    uint local_total = min(gParams.local_capacity, semantic_local_total[0u]);
    OptIrAccessCore access = opt_ir_accesses[access_id];
    uint source_row = opt_ir_access_source_rows[access_id];
    uint position = opt_ir_access_positions[access_id];
    uint kind = opt_ir_access_kinds[access_id];
    bool valid = kind > OPT_IR_ACCESS_INVALID &&
        kind < OPT_IR_ACCESS_KIND_COUNT;
    uint diagnostic_node = 0u;

    if (kind >= OPT_IR_ACCESS_DECLARATION_READ &&
        kind <= OPT_IR_ACCESS_MEMORY_WRITE)
    {
        diagnostic_node = source_row;
        valid = valid && source_row < node_total &&
            access.block_id < block_total &&
            opt_ir_control[source_row].block_id == access.block_id &&
            opt_ir_position_by_node[source_row] == position;
        if (valid)
        {
            OptIrBlock block = opt_ir_blocks[access.block_id];
            valid = valid_function_position(block.function_id,
                access.block_id, position, function_total, block_total);
        }
        if (kind == OPT_IR_ACCESS_DECLARATION_READ ||
            kind == OPT_IR_ACCESS_DECLARATION_WRITE)
            valid = valid && access.subject < gParams.declaration_capacity;
        else
            valid = valid && access.subject < node_total;
    }
    else if (kind == OPT_IR_ACCESS_PARAMETER_DEFINITION)
    {
        valid = valid && source_row < param_total;
        if (valid)
        {
            SemanticLirParam param = semantic_params[source_row];
            valid = access.subject == param.declaration_id &&
                access.subject < gParams.declaration_capacity &&
                valid_function_position(param.function_id, access.block_id,
                    position, function_total, block_total);
        }
    }
    else if (kind == OPT_IR_ACCESS_LOCAL_DECLARATION)
    {
        valid = valid && source_row < local_total;
        if (valid)
        {
            SemanticLirLocal local = semantic_locals[source_row];
            valid = access.subject == local.declaration_id &&
                access.subject < gParams.declaration_capacity &&
                valid_function_position(local.function_id, access.block_id,
                    position, function_total, block_total);
        }
    }
    if (!valid) report_structure_failure(diagnostic_node);
}
