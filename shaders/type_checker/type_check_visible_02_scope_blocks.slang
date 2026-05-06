struct Params
{
    uint n_tokens;
    uint source_len;
    uint n_hir_nodes;
};

ConstantBuffer<Params> gParams;

StructuredBuffer<uint> token_count;
StructuredBuffer<uint> hir_kind;
StructuredBuffer<uint> hir_token_pos;
StructuredBuffer<uint> hir_token_end;
StructuredBuffer<uint> hir_status;

RWStructuredBuffer<uint> scope_end;

static const uint INVALID = 0xffffffffu;
static const uint HIR_BLOCK = 6u;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

uint linear_thread_id(uint3 dtid)
{
    return dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE;
}

uint active_token_count()
{
    return min(token_count[0], gParams.n_tokens);
}

uint active_hir_node_count()
{
    return gParams.n_hir_nodes == 0u ? 0u : min(gParams.n_hir_nodes, hir_status[5u]);
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint hir_i = linear_thread_id(dtid);
    if (hir_i >= active_hir_node_count() || hir_kind[hir_i] != HIR_BLOCK)
        return;

    uint start = hir_token_pos[hir_i];
    uint end = min(hir_token_end[hir_i], active_token_count());
    if (start == INVALID || start >= end)
        return;

    [loop]
    for (uint i = start; i < end; i += 1u)
    {
        uint old_value = 0u;
        InterlockedMin(scope_end[i], end, old_value);
    }
}
