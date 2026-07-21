struct Params
{
    uint n_tokens;
    uint source_len;
    uint n_hir_nodes;
};

ConstantBuffer<Params> gParams;

struct HirCore { uint kind; uint parent; uint token_start; uint token_end; };
struct HirPayload { uint a; uint b; uint c; uint d; };
StructuredBuffer<uint> compact_hir_count;
StructuredBuffer<HirCore> compact_hir_core;
StructuredBuffer<HirPayload> compact_hir_payload;
StructuredBuffer<uint> name_id_by_token;
StructuredBuffer<uint> language_entrypoint_tag_by_name_id;

RWStructuredBuffer<uint> fn_entrypoint_tag;

static const uint INVALID = 0xffffffffu;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

static const uint HIR_ITEM_KIND_FN = 4u;
static const uint LANGUAGE_SYMBOL_COUNT = 63u;
static const uint ENTRYPOINT_MAIN = 1u;

uint linear_thread_id(uint3 dtid)
{
    return dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE;
}

uint active_hir_count()
{
    return min(gParams.n_hir_nodes, compact_hir_count[0u]);
}

uint entrypoint_tag_for_name_id(uint name_id)
{
    if (name_id == INVALID || name_id >= gParams.n_tokens + LANGUAGE_SYMBOL_COUNT)
        return 0u;
    return language_entrypoint_tag_by_name_id[name_id];
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint i = linear_thread_id(dtid);
    if (i >= active_hir_count())
        return;

    HirCore core = compact_hir_core[i];
    HirPayload payload = compact_hir_payload[i];
    if (core.kind != 3u || payload.a != HIR_ITEM_KIND_FN)
        return;

    uint fn_name_token = payload.b;
    if (fn_name_token == INVALID || fn_name_token >= gParams.n_tokens)
        return;

    uint fn_name_id = name_id_by_token[fn_name_token];
    uint entrypoint_tag = entrypoint_tag_for_name_id(fn_name_id);
    if (entrypoint_tag == ENTRYPOINT_MAIN)
    {
        // Semantic consumers key functions by their declaration-name token;
        // backends key bodies by the function span's first token. Publish both
        // token-domain projections from this one dense HIR function row.
        fn_entrypoint_tag[fn_name_token] = entrypoint_tag;
        if (core.token_start < gParams.n_tokens)
            fn_entrypoint_tag[core.token_start] = entrypoint_tag;
    }
}
