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

uint event_token(uint event_key)
{
    return (event_key - 1u) / 2u;
}

bool event_is_start(uint event_key)
{
    return ((event_key - 1u) & 1u) == 1u;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint i = linear_thread_id(dtid);
    if (i >= gParams.n_tokens)
        return;

    uint event_key = max(fn_event_inblock[i], block_prefix[i / WG_SIZE]);
    if (event_key == 0u || !event_is_start(event_key))
    {
        enclosing_fn[i] = 0u;
        enclosing_fn_end[i] = 0u;
        return;
    }

    uint token = event_token(event_key);
    enclosing_fn[i] = fn_event_value[token];
    enclosing_fn_end[i] = fn_event_end[token];
}
