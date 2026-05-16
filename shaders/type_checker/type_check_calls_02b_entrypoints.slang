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
StructuredBuffer<uint> language_decl_name_id;
StructuredBuffer<uint> language_decl_kind;
StructuredBuffer<uint> language_decl_tag;

RWStructuredBuffer<uint> fn_entrypoint_tag;

static const uint INVALID = 0xffffffffu;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

static const uint HIR_ITEM_KIND_FN = 4u;
static const uint LANGUAGE_DECL_COUNT = 18u;
static const uint LANGUAGE_DECL_ENTRYPOINT = 1u;
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
    if (name_id == INVALID)
        return 0u;

    [unroll]
    for (uint decl_i = 0u; decl_i < LANGUAGE_DECL_COUNT; decl_i += 1u)
    {
        if (language_decl_kind[decl_i] == LANGUAGE_DECL_ENTRYPOINT &&
            language_decl_name_id[decl_i] == name_id)
            return language_decl_tag[decl_i];
    }
    return 0u;
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
        fn_entrypoint_tag[i] = entrypoint_tag;
        uint fn_token = hir_token_pos[i];
        if (fn_token != INVALID && fn_token < gParams.n_tokens)
            fn_entrypoint_tag[fn_token] = entrypoint_tag;
    }
}
