struct Params
{
    uint n_tokens;
    uint n_hir_nodes;
    uint n_blocks;
    uint scan_step;
};
ConstantBuffer<Params> gParams;

StructuredBuffer<uint> hir_kind;
StructuredBuffer<uint> hir_token_pos;
StructuredBuffer<uint> hir_token_end;
StructuredBuffer<uint> hir_status;

RWStructuredBuffer<int> loop_delta;

static const uint INVALID = 0xffffffffu;
static const uint HIR_WHILE_STMT = 11u;
static const uint HIR_FOR_STMT = 30u;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

uint linear_thread_id(uint3 dtid)
{
    return dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE;
}

uint active_hir_node_count()
{
    return gParams.n_hir_nodes == 0u ? 0u : min(gParams.n_hir_nodes, hir_status[5u]);
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint i = linear_thread_id(dtid);
    if (i >= active_hir_node_count())
        return;

    uint kind = hir_kind[i];
    if (kind != HIR_WHILE_STMT && kind != HIR_FOR_STMT)
        return;

    uint start = hir_token_pos[i];
    if (start == INVALID || start >= gParams.n_tokens)
        return;

    uint end = hir_token_end[i];
    if (end == INVALID || end <= start)
        return;

    uint bounded_end = min(end, gParams.n_tokens);
    int old;
    InterlockedAdd(loop_delta[start], 1, old);
    InterlockedAdd(loop_delta[bounded_end], -1, old);
}
