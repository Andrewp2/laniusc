// Build compact dispatch arguments for clearing virtual instruction rows.
//
// x86_node_inst_gen_inputs publishes the exact virtual-row count produced by
// the instruction-count prefix pipeline. Clearing only that compact range avoids
// touching the larger host estimate before node-local generation overwrites the
// real rows.

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

RWStructuredBuffer<uint> active_virtual_inst_dispatch_args;

static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;
static const uint X86_NODE_INST_GEN_INPUTS_OK = 1u;

uint virtual_inst_count()
{
    bool ok = x86_node_inst_gen_input_status[0u] == X86_NODE_INST_GEN_INPUTS_OK &&
              x86_node_inst_gen_input_status[1u] == 0u &&
              x86_node_inst_gen_input_status[3u] <= gParams.inst_capacity;
    return ok ? min(x86_node_inst_gen_input_status[3u], gParams.inst_capacity) : 0u;
}

void write_dispatch_args(RWStructuredBuffer<uint> args, uint active_records)
{
    uint groups = max(1u, (active_records + WG_SIZE - 1u) / WG_SIZE);
    args[0u] = min(groups, MAX_GROUPS_X);
    args[1u] = max(1u, (groups + MAX_GROUPS_X - 1u) / MAX_GROUPS_X);
    args[2u] = 1u;
}

[shader("compute")]
[numthreads(1, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    if (tid.x != 0u || tid.y != 0u || tid.z != 0u)
        return;

    write_dispatch_args(active_virtual_inst_dispatch_args, virtual_inst_count());
}
