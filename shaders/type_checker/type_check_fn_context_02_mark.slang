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

RWStructuredBuffer<uint> fn_event_value;
RWStructuredBuffer<uint> fn_event_end;
RWStructuredBuffer<uint> fn_event_index;

static const uint INVALID = 0xffffffffu;
static const uint HIR_FN = 3u;
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
    uint hir_i = linear_thread_id(dtid);
    if (hir_i >= active_hir_node_count() || hir_kind[hir_i] != HIR_FN)
        return;

    uint fn_start = hir_token_pos[hir_i];
    uint fn_end = min(hir_token_end[hir_i], gParams.n_tokens);
    if (fn_start == INVALID || fn_start >= gParams.n_tokens || fn_end <= fn_start)
        return;

    fn_event_index[fn_start] = fn_start + 1u;
    fn_event_value[fn_start] = fn_start + 1u;
    fn_event_end[fn_start] = fn_end;

    if (fn_end < gParams.n_tokens)
    {
        fn_event_index[fn_end] = fn_end + 1u;
        fn_event_value[fn_end] = 0u;
    }
}
