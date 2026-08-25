// Compacts one row per `(declaration, basic block)` present in the stable
// declaration-access ordering. This relation is sparse by construction: a
// declaration allocates no persistent state for blocks that do not access it.

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
StructuredBuffer<OptIrAccessCore> opt_ir_accesses;
StructuredBuffer<uint> opt_ir_access_order;
StructuredBuffer<uint> opt_ir_declaration_block_start_flag;
StructuredBuffer<uint> opt_ir_declaration_block_prefix;
RWStructuredBuffer<OptIrDeclarationBlock> opt_ir_declaration_blocks;
RWStructuredBuffer<LoweringStatus> lowering_status;

static const uint DISPATCH_X_STRIDE = 16776960u;

void report_capacity(uint required)
{
    InterlockedOr(lowering_status[0u].flags,
        LOWERING_STATUS_OPTIMIZATION_CAPACITY);
    InterlockedMax(lowering_status[0u].required_capacity, required);
    lowering_status[0u].available_capacity = gParams.access_capacity;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint order_i = linear_dispatch_thread_id_2d(dtid, DISPATCH_X_STRIDE);
    uint total = min(opt_ir_declaration_access_total[0u],
        gParams.access_capacity);
    uint access_total = min(opt_ir_access_total[0u], gParams.access_capacity);
    if (order_i >= total ||
        opt_ir_declaration_block_start_flag[order_i] == 0u)
        return;

    uint access_id = opt_ir_access_order[order_i];
    uint row = opt_ir_declaration_block_prefix[order_i];
    if (access_id >= access_total || row >= gParams.access_capacity)
    {
        report_capacity(row + 1u);
        return;
    }

    OptIrDeclarationBlock declaration_block;
    declaration_block.access_start = order_i;
    opt_ir_declaration_blocks[row] = declaration_block;
}
