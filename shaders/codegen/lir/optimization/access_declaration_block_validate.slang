// Validates the sparse declaration/block relation and its initialized local
// reaching-definition state independently from the construction shader.

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
StructuredBuffer<uint> opt_ir_access_total;
StructuredBuffer<uint> opt_ir_declaration_access_total;
StructuredBuffer<uint> opt_ir_declaration_block_total;
StructuredBuffer<OptIrAccessCore> opt_ir_accesses;
StructuredBuffer<uint> opt_ir_access_kinds;
StructuredBuffer<uint> opt_ir_access_order;
StructuredBuffer<uint> opt_ir_local_definition_by_access;
StructuredBuffer<OptIrDeclarationBlock> opt_ir_declaration_blocks;
StructuredBuffer<OptIrReachingDefinitionState>
    opt_ir_reaching_definition_states;
RWStructuredBuffer<LoweringStatus> lowering_status;

static const uint INVALID = 0xffffffffu;
static const uint DISPATCH_X_STRIDE = 16776960u;

void report_structure_failure(uint access_id)
{
    InterlockedOr(lowering_status[0u].flags,
        LOWERING_STATUS_OPTIMIZATION_STRUCTURE);
    InterlockedMin(lowering_status[0u].first_unsupported_opt_row, access_id);
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint row = linear_dispatch_thread_id_2d(dtid, DISPATCH_X_STRIDE);
    uint row_total = min(opt_ir_declaration_block_total[0u],
        gParams.access_capacity);
    if (row >= row_total) return;

    uint declaration_total = min(opt_ir_declaration_access_total[0u],
        gParams.access_capacity);
    uint access_total = min(opt_ir_access_total[0u], gParams.access_capacity);
    OptIrDeclarationBlock declaration_block = opt_ir_declaration_blocks[row];
    OptIrReachingDefinitionState state =
        opt_ir_reaching_definition_states[row];
    uint end = row + 1u < row_total
        ? opt_ir_declaration_blocks[row + 1u].access_start
        : declaration_total;
    bool valid = declaration_block.access_start < end &&
        end <= declaration_total;
    uint first_access_id = valid
        ? opt_ir_access_order[declaration_block.access_start]
        : INVALID;
    valid = valid && first_access_id < access_total;
    uint declaration_id = valid
        ? opt_ir_accesses[first_access_id].subject : INVALID;
    uint block_id = valid
        ? opt_ir_accesses[first_access_id].block_id : INVALID;
    bool expected_incoming = false;

    if (row > 0u)
    {
        OptIrDeclarationBlock previous = opt_ir_declaration_blocks[row - 1u];
        uint previous_access_id =
            opt_ir_access_order[previous.access_start];
        valid = valid && previous_access_id < access_total;
        if (valid)
        {
            OptIrAccessCore previous_access =
                opt_ir_accesses[previous_access_id];
            valid = previous_access.subject < declaration_id ||
                (previous_access.subject == declaration_id &&
                 previous_access.block_id < block_id);
        }
    }

    for (uint order_i = declaration_block.access_start;
         valid && order_i < end; ++order_i)
    {
        uint access_id = opt_ir_access_order[order_i];
        valid = access_id < access_total;
        if (!valid) break;
        OptIrAccessCore access = opt_ir_accesses[access_id];
        uint kind = opt_ir_access_kinds[access_id];
        valid = access.subject == declaration_id &&
            access.block_id == block_id &&
            opt_ir_access_domain(kind) == 0u;
        if (kind == OPT_IR_ACCESS_DECLARATION_READ &&
            opt_ir_local_definition_by_access[access_id] == INVALID)
            expected_incoming = true;
    }

    uint expected_state = expected_incoming
        ? OPT_IR_REACHING_DEFINITION_UNRESOLVED
        : OPT_IR_REACHING_DEFINITION_UNUSED;
    valid = valid && state.incoming_definition == expected_state;
    if (!valid) report_structure_failure(declaration_block.access_start);
}
