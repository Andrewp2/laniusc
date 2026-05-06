struct Params
{
    uint n_tokens;
    uint n_hir_nodes;
    uint n_blocks;
    uint scan_step;
};

ConstantBuffer<Params> gParams;

StructuredBuffer<uint> fn_event_value;
StructuredBuffer<uint> fn_event_end;
StructuredBuffer<uint> fn_event_inblock;
StructuredBuffer<uint> block_prefix;

RWStructuredBuffer<uint> enclosing_fn;
RWStructuredBuffer<uint> enclosing_fn_end;

static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

uint linear_thread_id(uint3 dtid)
{
    return dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint i = linear_thread_id(dtid);
    if (i >= gParams.n_tokens)
        return;

    uint event_idx = max(fn_event_inblock[i], block_prefix[i / WG_SIZE]);
    enclosing_fn[i] = event_idx == 0u ? 0u : fn_event_value[event_idx - 1u];
    enclosing_fn_end[i] = event_idx == 0u ? 0u : fn_event_end[event_idx - 1u];
}
