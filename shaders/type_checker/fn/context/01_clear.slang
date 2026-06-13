struct Params
{
    uint n_tokens;
    uint n_hir_nodes;
    uint n_blocks;
    uint scan_step;
};

ConstantBuffer<Params> gParams;

RWStructuredBuffer<uint> enclosing_fn;
RWStructuredBuffer<uint> enclosing_fn_end;
RWStructuredBuffer<uint> fn_event_value;
RWStructuredBuffer<uint> fn_event_end;
RWStructuredBuffer<uint> fn_event_index;
RWStructuredBuffer<uint> fn_event_inblock;
RWStructuredBuffer<uint> block_sum;
RWStructuredBuffer<uint> block_prefix;

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
    if (i < gParams.n_tokens)
    {
        enclosing_fn[i] = 0u;
        enclosing_fn_end[i] = 0u;
        fn_event_value[i] = 0u;
        fn_event_end[i] = 0u;
        fn_event_index[i] = 0u;
        fn_event_inblock[i] = 0u;
    }
    if (i < gParams.n_blocks)
    {
        block_sum[i] = 0u;
        block_prefix[i] = 0u;
    }
}
