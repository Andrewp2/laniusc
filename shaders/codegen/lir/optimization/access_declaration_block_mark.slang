// Reuses the declaration-group flag storage after group construction to mark
// the first ordered access in each populated `(declaration, basic block)`.

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
StructuredBuffer<uint> opt_ir_declaration_access_total;
StructuredBuffer<OptIrAccessCore> opt_ir_accesses;
StructuredBuffer<uint> opt_ir_access_order;
RWStructuredBuffer<uint> opt_ir_declaration_block_start_flag;

static const uint DISPATCH_X_STRIDE = 16776960u;

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint order_i = linear_dispatch_thread_id_2d(dtid, DISPATCH_X_STRIDE);
    uint total = min(opt_ir_declaration_access_total[0u],
        gParams.access_capacity);
    if (order_i >= total) return;

    uint access_id = opt_ir_access_order[order_i];
    bool starts = order_i == 0u || access_id >= gParams.access_capacity;
    if (!starts)
    {
        uint previous_id = opt_ir_access_order[order_i - 1u];
        starts = previous_id >= gParams.access_capacity ||
            opt_ir_accesses[previous_id].subject !=
                opt_ir_accesses[access_id].subject ||
            opt_ir_accesses[previous_id].block_id !=
                opt_ir_accesses[access_id].block_id;
    }
    opt_ir_declaration_block_start_flag[order_i] = starts ? 1u : 0u;
}
