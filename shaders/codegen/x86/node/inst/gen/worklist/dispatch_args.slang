// Build compact dispatch arguments for node-local virtual-instruction generation.

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

RWStructuredBuffer<uint> active_node_inst_gen_dispatch_args;

static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

void write_dispatch_args(RWStructuredBuffer<uint> args, uint active_records, uint z_groups)
{
    uint groups = max(1u, (active_records + WG_SIZE - 1u) / WG_SIZE);
    args[0u] = min(groups, MAX_GROUPS_X);
    args[1u] = max(1u, (groups + MAX_GROUPS_X - 1u) / MAX_GROUPS_X);
    args[2u] = max(1u, z_groups);
}

[shader("compute")]
[numthreads(1, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    if (tid.x != 0u || tid.y != 0u || tid.z != 0u)
        return;

    uint count = min(x86_node_inst_gen_input_status[4u], min(gParams.n_hir_nodes, gParams.inst_capacity));
    write_dispatch_args(active_node_inst_gen_dispatch_args, count, 1u);
}
