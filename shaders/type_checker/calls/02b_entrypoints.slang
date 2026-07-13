struct Params
{
    uint n_tokens;
    uint source_len;
    uint n_hir_nodes;
};

ConstantBuffer<Params> gParams;

StructuredBuffer<uint> hir_status;
StructuredBuffer<uint> hir_token_pos;
StructuredBuffer<uint> hir_item_kind;
StructuredBuffer<uint> hir_item_name_token;
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

uint active_hir_node_count()
{
    return gParams.n_hir_nodes == 0u ? 0u : min(gParams.n_hir_nodes, hir_status[5u]);
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
    if (i >= active_hir_node_count() || hir_item_kind[i] != HIR_ITEM_KIND_FN)
        return;

    uint fn_name_token = hir_item_name_token[i];
    if (fn_name_token == INVALID || fn_name_token >= gParams.n_tokens)
        return;

    uint fn_name_id = name_id_by_token[fn_name_token];
    uint entrypoint_tag = entrypoint_tag_for_name_id(fn_name_id);
    if (entrypoint_tag == ENTRYPOINT_MAIN)
    {
        // HIR node keyed. Token-keyed writes alias unrelated node rows in large modules.
        fn_entrypoint_tag[i] = entrypoint_tag;
    }
}
