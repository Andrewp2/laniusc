// Build indirect dispatch arguments for active type-check passes.
//
// This pass consumes GPU-resident lexer/parser counters and writes standard
// three-u32 dispatch argument buffers. It avoids host readback of active
// counts while letting semantic passes launch over active records rather than
// over conservative allocation capacity.

struct Params
{
    uint n_tokens;
    uint source_len;
    uint n_hir_nodes;
};

ConstantBuffer<Params> gParams;

StructuredBuffer<uint> token_count;
StructuredBuffer<uint> hir_status;
RWStructuredBuffer<uint> token_active_dispatch_args;
RWStructuredBuffer<uint> hir_active_dispatch_args;
RWStructuredBuffer<uint> token_hir_active_dispatch_args;
RWStructuredBuffer<uint> hir_active_count;

static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

uint active_hir_node_count()
{
    return hir_status[0u] == 0u || gParams.n_hir_nodes == 0u
        ? 0u
        : min(gParams.n_hir_nodes, hir_status[5u]);
}

uint active_token_count()
{
    return hir_status[0u] == 0u ? 0u : min(gParams.n_tokens, token_count[0u]);
}

void write_dispatch_args(RWStructuredBuffer<uint> args, uint active_records)
{
    uint groups = (active_records + WG_SIZE - 1u) / WG_SIZE;
    args[0u] = min(groups, MAX_GROUPS_X);
    args[1u] = groups == 0u ? 0u : (groups + MAX_GROUPS_X - 1u) / MAX_GROUPS_X;
    args[2u] = groups == 0u ? 0u : 1u;
}

[shader("compute")]
[numthreads(1, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    if (dtid.x != 0u || dtid.y != 0u || dtid.z != 0u)
        return;

    uint active_tokens = active_token_count();
    uint active_hir = active_hir_node_count();
    hir_active_count[0u] = active_hir;
    write_dispatch_args(token_active_dispatch_args, active_tokens);
    write_dispatch_args(hir_active_dispatch_args, active_hir);
    write_dispatch_args(token_hir_active_dispatch_args, max(active_tokens, active_hir));
}
