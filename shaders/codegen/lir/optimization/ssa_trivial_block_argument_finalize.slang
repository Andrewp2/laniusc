// Converts the least-summary fixed point into canonical replacement values.

import codegen.optimization_ir;
import codegen.lir.optimization.ssa_block_argument_lookup;
import gpu_index;

struct Params
{
    uint block_capacity;
    uint edge_capacity;
    uint access_capacity;
    uint declaration_capacity;
    uint declaration_block_capacity;
    uint demand_capacity;
    uint worker_count;
    uint max_radix_blocks;
    uint incoming_capacity;
};

ConstantBuffer<Params> gParams;
StructuredBuffer<uint> opt_ir_ssa_block_argument_summary;
RWStructuredBuffer<uint> opt_ir_ssa_block_argument_replacement;

static const uint SUMMARY_NONE = 0u;
static const uint SUMMARY_CONFLICT = 0xffffffffu;
static const uint DISPATCH_X_STRIDE = 16776960u;

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint argument = linear_dispatch_thread_id_2d(dtid, DISPATCH_X_STRIDE);
    uint argument_total = opt_ir_active_ssa_block_argument_total(
        gParams.demand_capacity);
    if (argument >= argument_total) return;

    uint summary = opt_ir_ssa_block_argument_summary[argument];
    OptIrSsaValueRef replacement;
    if (summary != SUMMARY_NONE && summary != SUMMARY_CONFLICT)
    {
        replacement.kind = OPT_IR_SSA_SOURCE_LOCAL_DEFINITION;
        replacement.payload = summary - 1u;
    }
    else
    {
        replacement.kind = OPT_IR_SSA_SOURCE_BLOCK_ARGUMENT;
        replacement.payload = argument;
    }
    opt_ir_ssa_block_argument_replacement[argument] =
        opt_ir_pack_ssa_source(replacement);
}
