// Pre-resolution GPU module/path metadata foundation.
//
// Scheduling contract:
// - Dispatch after parser-owned HIR item fields and name_id_by_token exist.
// - This pass marks candidate rows only. A GPU prefix scan over these flags
//   allocates compact records for later scatter passes.
// - It does not resolve imports, decide declaration visibility, accept
//   qualified paths, perform same-source shortcuts, use hash-only lookup, or
//   ask the CPU to classify paths.

struct Params
{
    uint n_tokens;
    uint source_len;
    uint n_hir_nodes;
};

ConstantBuffer<Params> gParams;

StructuredBuffer<uint> hir_status;
StructuredBuffer<uint> hir_kind;
StructuredBuffer<uint> hir_token_pos;
StructuredBuffer<uint> hir_token_end;
StructuredBuffer<uint> hir_item_kind;
StructuredBuffer<uint> hir_item_name_token;
StructuredBuffer<uint> hir_item_namespace;
StructuredBuffer<uint> hir_item_path_start;
StructuredBuffer<uint> hir_item_path_end;
StructuredBuffer<uint> hir_item_import_target_kind;

RWStructuredBuffer<uint> module_record_flag;
RWStructuredBuffer<uint> import_record_flag;
RWStructuredBuffer<uint> decl_record_flag;
RWStructuredBuffer<uint> path_record_flag;
RWStructuredBuffer<uint> path_record_kind;

static const uint INVALID = 0xffffffffu;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

static const uint HIR_TYPE = 5u;
static const uint HIR_PATH_EXPR = 33u;

static const uint HIR_ITEM_KIND_NONE = 0u;
static const uint HIR_ITEM_KIND_MODULE = 1u;
static const uint HIR_ITEM_KIND_IMPORT = 2u;
static const uint HIR_ITEM_KIND_CONST = 3u;
static const uint HIR_ITEM_KIND_FN = 4u;
static const uint HIR_ITEM_KIND_EXTERN_FN = 5u;
static const uint HIR_ITEM_KIND_STRUCT = 6u;
static const uint HIR_ITEM_KIND_ENUM = 7u;
static const uint HIR_ITEM_KIND_TYPE_ALIAS = 8u;
static const uint HIR_ITEM_KIND_ENUM_VARIANT = 9u;

static const uint HIR_ITEM_NAMESPACE_NONE = 0u;
static const uint HIR_ITEM_NAMESPACE_MODULE = 1u;
static const uint HIR_ITEM_NAMESPACE_VALUE = 2u;
static const uint HIR_ITEM_NAMESPACE_TYPE = 3u;

static const uint HIR_ITEM_IMPORT_TARGET_NONE = 0u;
static const uint HIR_ITEM_IMPORT_TARGET_PATH = 1u;
static const uint HIR_ITEM_IMPORT_TARGET_STRING = 2u;

static const uint PATH_RECORD_KIND_NONE = 0u;
static const uint PATH_RECORD_KIND_MODULE_DECL = 1u;
static const uint PATH_RECORD_KIND_IMPORT_PATH = 2u;
static const uint PATH_RECORD_KIND_HIR_PATH_EXPR = 3u;
static const uint PATH_RECORD_KIND_HIR_TYPE_EXPR = 4u;

uint linear_thread_id(uint3 dtid)
{
    return dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE;
}

uint active_hir_node_count()
{
    return gParams.n_hir_nodes == 0u ? 0u : min(gParams.n_hir_nodes, hir_status[5u]);
}

bool valid_span(uint start, uint end_exclusive)
{
    return start != INVALID && end_exclusive != INVALID && start < end_exclusive &&
           end_exclusive <= gParams.n_tokens;
}

bool is_top_level_decl_kind(uint item_kind)
{
    return item_kind == HIR_ITEM_KIND_CONST || item_kind == HIR_ITEM_KIND_FN ||
           item_kind == HIR_ITEM_KIND_EXTERN_FN || item_kind == HIR_ITEM_KIND_STRUCT ||
           item_kind == HIR_ITEM_KIND_ENUM || item_kind == HIR_ITEM_KIND_TYPE_ALIAS ||
           item_kind == HIR_ITEM_KIND_ENUM_VARIANT;
}

bool is_decl_namespace(uint namespace)
{
    return namespace == HIR_ITEM_NAMESPACE_VALUE || namespace == HIR_ITEM_NAMESPACE_TYPE;
}

uint candidate_path_kind(uint i, uint item_kind)
{
    if (item_kind == HIR_ITEM_KIND_MODULE &&
        valid_span(hir_item_path_start[i], hir_item_path_end[i]))
        return PATH_RECORD_KIND_MODULE_DECL;

    if (item_kind == HIR_ITEM_KIND_IMPORT &&
        hir_item_import_target_kind[i] == HIR_ITEM_IMPORT_TARGET_PATH &&
        valid_span(hir_item_path_start[i], hir_item_path_end[i]))
        return PATH_RECORD_KIND_IMPORT_PATH;

    if (hir_kind[i] == HIR_PATH_EXPR && valid_span(hir_token_pos[i], hir_token_end[i]))
        return PATH_RECORD_KIND_HIR_PATH_EXPR;

    if (hir_kind[i] == HIR_TYPE && valid_span(hir_token_pos[i], hir_token_end[i]))
        return PATH_RECORD_KIND_HIR_TYPE_EXPR;

    return PATH_RECORD_KIND_NONE;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint i = linear_thread_id(dtid);
    if (i >= gParams.n_hir_nodes)
        return;

    module_record_flag[i] = 0u;
    import_record_flag[i] = 0u;
    decl_record_flag[i] = 0u;
    path_record_flag[i] = 0u;
    path_record_kind[i] = PATH_RECORD_KIND_NONE;

    if (i >= active_hir_node_count())
        return;

    uint item_kind = hir_item_kind[i];
    uint item_namespace = hir_item_namespace[i];

    if (item_kind == HIR_ITEM_KIND_MODULE &&
        valid_span(hir_item_path_start[i], hir_item_path_end[i]))
    {
        module_record_flag[i] = 1u;
    }

    if (item_kind == HIR_ITEM_KIND_IMPORT &&
        hir_item_import_target_kind[i] != HIR_ITEM_IMPORT_TARGET_NONE)
    {
        import_record_flag[i] = 1u;
    }

    if (is_top_level_decl_kind(item_kind) && is_decl_namespace(item_namespace) &&
        hir_item_name_token[i] != INVALID)
    {
        decl_record_flag[i] = 1u;
    }

    uint kind = candidate_path_kind(i, item_kind);
    if (kind != PATH_RECORD_KIND_NONE)
    {
        path_record_flag[i] = 1u;
        path_record_kind[i] = kind;
    }
}
