// GPU type-path projection from resolver arrays.
//
// Scheduling contract:
// - Dispatch after local/imported/qualified type path resolution and after
//   declaration span records are available.
// - This pass consumes declaration ids produced by the sorted GPU module/import
//   resolver and writes a token-indexed type code for HIR path-expression heads.
// - It does not inspect source bytes, hash token text, scan for "::", patch
//   visibility/call outputs, or perform any CPU lookup.

struct Params
{
    uint n_tokens;
    uint source_len;
    uint n_hir_nodes;
};

ConstantBuffer<Params> gParams;

StructuredBuffer<uint> path_count_out;
StructuredBuffer<uint> path_kind;
StructuredBuffer<uint> path_segment_count;
StructuredBuffer<uint> path_owner_token;
StructuredBuffer<uint> resolved_type_decl;
StructuredBuffer<uint> resolved_type_status;
StructuredBuffer<uint> decl_kind;
StructuredBuffer<uint> decl_namespace;
StructuredBuffer<uint> decl_name_token;

RWStructuredBuffer<uint> module_type_path_type;
RWStructuredBuffer<uint> module_type_path_status;

static const uint INVALID = 0xffffffffu;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

static const uint PATH_RECORD_KIND_HIR_PATH_EXPR = 3u;
static const uint PATH_RECORD_KIND_HIR_TYPE_EXPR = 4u;
static const uint PATH_RESOLVE_STATUS_OK = 0u;

static const uint HIR_ITEM_KIND_STRUCT = 6u;
static const uint HIR_ITEM_KIND_ENUM = 7u;
static const uint HIR_ITEM_KIND_TYPE_ALIAS = 8u;
static const uint HIR_ITEM_NAMESPACE_TYPE = 3u;

static const uint TY_STRUCT_BASE = 4096u;
static const uint TY_ENUM_BASE = 6144u;

uint linear_thread_id(uint3 dtid)
{
    return dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE;
}

uint active_path_count()
{
    return min(path_count_out[0], gParams.n_hir_nodes);
}

uint projected_type_code(uint decl_i)
{
    if (decl_i == INVALID)
        return 0u;
    if (decl_namespace[decl_i] != HIR_ITEM_NAMESPACE_TYPE)
        return 0u;

    uint token_i = decl_name_token[decl_i];
    if (token_i == INVALID || token_i >= gParams.n_tokens)
        return 0u;

    uint kind = decl_kind[decl_i];
    if (kind == HIR_ITEM_KIND_STRUCT)
        return TY_STRUCT_BASE + token_i;
    if (kind == HIR_ITEM_KIND_ENUM)
        return TY_ENUM_BASE + token_i;
    if (kind == HIR_ITEM_KIND_TYPE_ALIAS)
        return module_type_path_type[token_i];
    return 0u;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint path_i = linear_thread_id(dtid);
    if (path_i >= active_path_count())
        return;
    if (path_kind[path_i] != PATH_RECORD_KIND_HIR_TYPE_EXPR)
        return;

    uint owner_token = path_owner_token[path_i];
    if (owner_token >= gParams.n_tokens)
        return;

    uint resolved_status = resolved_type_status[path_i];
    if (resolved_status != PATH_RESOLVE_STATUS_OK)
    {
        if (path_segment_count[path_i] > 1u)
            module_type_path_status[owner_token] = resolved_status;
        return;
    }

    uint ty = projected_type_code(resolved_type_decl[path_i]);
    if (ty != 0u)
    {
        module_type_path_type[owner_token] = ty;
        module_type_path_status[owner_token] = PATH_RESOLVE_STATUS_OK;
    }
}
