// Compact virtual-instruction row initialization.
//
// Padding rows are represented as X86_VINST_NONE. This pass initializes only
// rows below the exact virtual instruction count so later select/size/encode
// stages never depend on capacity-wide host clears.

import gpu_index;

struct Params
{
    uint n_tokens;
    uint source_len;
    uint out_capacity;
    uint n_hir_nodes;
    uint inst_capacity;
};

ConstantBuffer<Params> gParams;

StructuredBuffer<uint> x86_node_inst_gen_input_status;

RWStructuredBuffer<uint4> x86_virtual_inst_record;
RWStructuredBuffer<uint4> x86_virtual_inst_args;

static const uint DISPATCH_X_STRIDE = 16776960u;
static const uint INVALID = 0xffffffffu;
static const uint X86_NODE_INST_GEN_INPUTS_OK = 1u;

uint linear_dispatch_id(uint3 tid)
{
    return linear_dispatch_thread_id_2d(tid, DISPATCH_X_STRIDE);
}

uint virtual_inst_count()
{
    bool ok = x86_node_inst_gen_input_status[0u] == X86_NODE_INST_GEN_INPUTS_OK &&
              x86_node_inst_gen_input_status[1u] == 0u &&
              x86_node_inst_gen_input_status[3u] <= gParams.inst_capacity;
    return ok ? min(x86_node_inst_gen_input_status[3u], gParams.inst_capacity) : 0u;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    uint row = linear_dispatch_id(tid);
    if (row >= virtual_inst_count())
        return;

    x86_virtual_inst_record[row] = uint4(INVALID, 0u, 0u, INVALID);
    x86_virtual_inst_args[row] = uint4(0u, 0u, 0u, 0u);
}
