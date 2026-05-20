// Build liveness dispatch arguments after compact virtual use-edge scatter.

struct Params
{
    uint n_tokens;
    uint source_len;
    uint out_capacity;
    uint n_hir_nodes;
    uint inst_capacity;
    uint virtual_use_edge_capacity;
};

ConstantBuffer<Params> gParams;

StructuredBuffer<uint> x86_virtual_inst_status;
StructuredBuffer<uint> x86_virtual_use_status;

RWStructuredBuffer<uint> active_virtual_use_edge_dispatch_args;

static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;
static const uint X86_VIRTUAL_INST_OK = 1u;
static const uint X86_VIRTUAL_USE_OK = 1u;

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

    bool ok = x86_virtual_inst_status[0u] == X86_VIRTUAL_INST_OK &&
              x86_virtual_inst_status[1u] == 0u &&
              x86_virtual_inst_status[3u] <= gParams.inst_capacity &&
              x86_virtual_use_status[0u] == X86_VIRTUAL_USE_OK &&
              x86_virtual_use_status[1u] == 0u &&
              x86_virtual_use_status[3u] <= gParams.virtual_use_edge_capacity;
    uint edge_count = ok ? min(x86_virtual_use_status[3u], gParams.virtual_use_edge_capacity) : 1u;
    write_dispatch_args(active_virtual_use_edge_dispatch_args, edge_count);
}
