// One pointer-jump round over declaration-read copy chains.

import codegen.optimization_ir;
import gpu_index;

struct Params
{
    uint semantic_capacity;
    uint parameter_capacity;
    uint block_argument_capacity;
    uint value_capacity;
};

ConstantBuffer<Params> gParams;
StructuredBuffer<uint> opt_ir_total;
StructuredBuffer<uint> opt_ir_ssa_value_link_in;
RWStructuredBuffer<uint> opt_ir_ssa_value_link_out;

static const uint DISPATCH_X_STRIDE = 16776960u;

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint row = linear_dispatch_thread_id_2d(dtid, DISPATCH_X_STRIDE);
    uint total = min(opt_ir_total[0u], gParams.semantic_capacity);
    if (row >= total) return;

    uint link = opt_ir_ssa_value_link_in[row];
    if (opt_ir_ssa_value_link_kind(link) ==
        OPT_IR_SSA_VALUE_LINK_NODE)
    {
        uint target = opt_ir_ssa_value_link_payload(link);
        link = target < total ? opt_ir_ssa_value_link_in[target] : 0u;
    }
    opt_ir_ssa_value_link_out[row] = link;
}
