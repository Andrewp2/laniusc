// GPU HIR enum constructor call consumer.
//
// Scheduling contract:
// - Dispatch after the generic enum-constructor validator has written any
//   constructor-token sentinel needed for generic enum payload checks.
// - Consume resolved_value_decl/status path rows produced by the sorted
//   module/import resolver and the HIR call-head marker.
// - For resolved, call-shaped HIR paths to enum variant declarations, including
//   local one-segment constructors and qualified module constructors, publish the
//   parent enum type at the path head and clear the fail-closed value-path
//   status. Generic enum constructors clear only after the validator sentinel
//   exists at the leaf constructor token.
// - It does not inspect source bytes, hash token text, scan for "::", perform
//   unqualified lookup, or ask the CPU to resolve constructors.

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
StructuredBuffer<uint> path_segment_base;
StructuredBuffer<uint> path_segment_token;
StructuredBuffer<uint> path_owner_token;
StructuredBuffer<uint> resolved_value_decl;
StructuredBuffer<uint> resolved_value_status;
StructuredBuffer<uint> decl_kind;
StructuredBuffer<uint> decl_namespace;
StructuredBuffer<uint> decl_name_token;
StructuredBuffer<uint> decl_parent_type_decl;
StructuredBuffer<uint> module_value_path_call_head;
StructuredBuffer<uint> type_decl_generic_param_count;

RWStructuredBuffer<uint> module_value_path_status;
RWStructuredBuffer<uint> call_return_type;

static const uint INVALID = 0xffffffffu;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;
static const uint MAX_PATH_SEGMENTS = 64u;

static const uint PATH_RECORD_KIND_HIR_PATH_EXPR = 3u;
static const uint PATH_RESOLVE_STATUS_OK = 0u;
static const uint PATH_RESOLVE_STATUS_UNRESOLVED_DECL = 6u;

static const uint HIR_ITEM_KIND_ENUM = 7u;
static const uint HIR_ITEM_KIND_ENUM_VARIANT = 9u;
static const uint HIR_ITEM_NAMESPACE_VALUE = 2u;

static const uint TY_ENUM_BASE = 6144u;
static const uint GENERIC_ENUM_CTOR_OK = 0xfffffffdu;

uint linear_thread_id(uint3 dtid)
{
    return dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE;
}

uint active_token_count()
{
    return gParams.n_tokens;
}

uint active_path_count()
{
    return min(path_count_out[0], gParams.n_hir_nodes);
}

bool enum_decl_has_generic_params(uint enum_token)
{
    return enum_token < active_token_count() && type_decl_generic_param_count[enum_token] != 0u;
}

uint leaf_token_for_path(uint path_i)
{
    uint count = min(path_segment_count[path_i], MAX_PATH_SEGMENTS);
    if (count == 0u)
        return INVALID;
    return path_segment_token[path_segment_base[path_i] + count - 1u];
}

bool valid_enum_variant_decl(uint decl_i, out uint enum_token)
{
    enum_token = INVALID;
    if (decl_i >= gParams.n_hir_nodes)
        return false;
    if (decl_namespace[decl_i] != HIR_ITEM_NAMESPACE_VALUE ||
        decl_kind[decl_i] != HIR_ITEM_KIND_ENUM_VARIANT)
        return false;

    uint enum_decl_i = decl_parent_type_decl[decl_i];
    if (enum_decl_i >= gParams.n_hir_nodes || decl_kind[enum_decl_i] != HIR_ITEM_KIND_ENUM)
        return false;

    enum_token = decl_name_token[enum_decl_i];
    return enum_token != INVALID && enum_token < active_token_count();
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint path_i = linear_thread_id(dtid);
    if (path_i >= active_path_count())
        return;
    if (path_kind[path_i] != PATH_RECORD_KIND_HIR_PATH_EXPR)
        return;

    uint owner_token = path_owner_token[path_i];
    if (owner_token >= active_token_count())
        return;
    if (resolved_value_status[path_i] != PATH_RESOLVE_STATUS_OK)
        return;

    uint enum_token;
    if (!valid_enum_variant_decl(resolved_value_decl[path_i], enum_token))
        return;

    uint leaf_token = leaf_token_for_path(path_i);
    if (leaf_token == INVALID || leaf_token >= active_token_count())
    {
        module_value_path_status[owner_token] = PATH_RESOLVE_STATUS_UNRESOLVED_DECL;
        return;
    }
    if (module_value_path_call_head[owner_token] == 0u)
        return;

    bool is_generic_enum = enum_decl_has_generic_params(enum_token);
    if (is_generic_enum && call_return_type[leaf_token] != GENERIC_ENUM_CTOR_OK)
        return;

    if (!is_generic_enum || owner_token != leaf_token)
        call_return_type[owner_token] = TY_ENUM_BASE + enum_token;
    module_value_path_status[owner_token] = INVALID;
}
