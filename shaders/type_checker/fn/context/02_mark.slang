struct Params
{
    uint n_tokens;
    uint n_hir_nodes;
    uint n_blocks;
    uint scan_step;
};

ConstantBuffer<Params> gParams;

struct HirCore { uint kind; uint parent; uint token_start; uint token_end; };
struct HirPayload { uint a; uint b; uint c; uint d; };

StructuredBuffer<uint> compact_hir_count;
StructuredBuffer<HirCore> compact_hir_core;
StructuredBuffer<HirPayload> compact_hir_payload;

RWStructuredBuffer<uint> fn_event_value;
RWStructuredBuffer<uint> fn_event_end;
RWStructuredBuffer<uint> fn_event_index;

static const uint INVALID = 0xffffffffu;
static const uint HIR_FN = 3u;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

uint encode_event_key(uint token, bool is_start)
{
    return token * 2u + (is_start ? 2u : 1u);
}

uint linear_thread_id(uint3 dtid)
{
    return dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE;
}

uint active_hir_node_count()
{
    return min(gParams.n_hir_nodes, compact_hir_count[0u]);
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint hir_i = linear_thread_id(dtid);
    if (hir_i >= active_hir_node_count() || compact_hir_core[hir_i].kind != HIR_FN)
        return;

    HirCore core = compact_hir_core[hir_i];
    uint fn_start = core.token_start;
    uint fn_end = min(core.token_end, gParams.n_tokens);
    uint fn_decl_token = compact_hir_payload[hir_i].b;
    if (fn_start == INVALID || fn_start >= gParams.n_tokens || fn_end <= fn_start ||
        fn_decl_token == INVALID || fn_decl_token >= gParams.n_tokens)
        return;

    InterlockedMax(fn_event_index[fn_start], encode_event_key(fn_start, true));
    // Preserve semantic identity in the enclosing-function relation. Consumers
    // that need a token-keyed table translate this dense HIR ID through the
    // function payload; source-span anchors remain interval boundaries only.
    fn_event_value[fn_start] = hir_i + 1u;
    fn_event_end[fn_start] = fn_end;

    if (fn_end < gParams.n_tokens)
    {
        InterlockedMax(fn_event_index[fn_end], encode_event_key(fn_end, false));
    }
}
