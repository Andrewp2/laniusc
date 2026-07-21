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
struct HirCore { uint kind; uint parent; uint token_start; uint token_end; };
StructuredBuffer<HirCore> compact_hir_core;

RWStructuredBuffer<uint> enclosing_fn;
RWStructuredBuffer<uint> enclosing_fn_start_token;
RWStructuredBuffer<uint> enclosing_fn_end;

static const uint INVALID = 0xffffffffu;

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
        enclosing_fn_start_token[i] = 0u;
        enclosing_fn_end[i] = 0u;
        return;
    }

    uint token = event_token(event_key);
    uint encoded_hir = fn_event_value[token];
    enclosing_fn[i] = encoded_hir;
    uint hir_i = encoded_hir - 1u;
    uint start_token = compact_hir_core[hir_i].token_start;
    enclosing_fn_start_token[i] = start_token == INVALID || start_token >= gParams.n_tokens
        ? 0u
        : start_token + 1u;
    enclosing_fn_end[i] = fn_event_end[token];
}
