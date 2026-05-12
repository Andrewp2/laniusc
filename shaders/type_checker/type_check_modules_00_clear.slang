struct Params
{
    uint n_tokens;
    uint source_len;
    uint n_hir_nodes;
};

ConstantBuffer<Params> gParams;

RWStructuredBuffer<uint> module_item_kind;
RWStructuredBuffer<uint> module_path_start;
RWStructuredBuffer<uint> module_path_end;
RWStructuredBuffer<uint> module_path_hash;
RWStructuredBuffer<uint> import_enclosing_module_token;
RWStructuredBuffer<uint> import_target_kind;
RWStructuredBuffer<uint> import_resolved_module_token;
RWStructuredBuffer<uint> decl_item_kind;
RWStructuredBuffer<uint> decl_name_hash;
RWStructuredBuffer<uint> decl_name_len;
RWStructuredBuffer<uint> decl_namespace;
RWStructuredBuffer<uint> decl_visibility;
RWStructuredBuffer<uint> decl_file_id;
RWStructuredBuffer<uint> decl_hir_node;

static const uint INVALID = 0xffffffffu;
static const uint MODULE_ITEM_NONE = 0u;
static const uint DECL_ITEM_NONE = 0u;
static const uint DECL_NAMESPACE_NONE = 0u;
static const uint DECL_VIS_PRIVATE = 0u;
static const uint IMPORT_TARGET_NONE = 0u;
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

    module_item_kind[i] = MODULE_ITEM_NONE;
    module_path_start[i] = INVALID;
    module_path_end[i] = INVALID;
    module_path_hash[i] = 0u;
    import_enclosing_module_token[i] = INVALID;
    import_target_kind[i] = IMPORT_TARGET_NONE;
    import_resolved_module_token[i] = INVALID;
    decl_item_kind[i] = DECL_ITEM_NONE;
    decl_name_hash[i] = 0u;
    decl_name_len[i] = 0u;
    decl_namespace[i] = DECL_NAMESPACE_NONE;
    decl_visibility[i] = DECL_VIS_PRIVATE;
    decl_file_id[i] = INVALID;
    decl_hir_node[i] = INVALID;
}
