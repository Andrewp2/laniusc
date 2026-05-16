// GPU HIR-qualified constant value consumer.
//
// Scheduling contract:
// - Dispatch after type_check_scope.slang has populated declaration
//   visible_type entries for const declarations and before type_check_tokens.
// - Consume resolved_value_decl/status path rows produced by the sorted
//   module/import resolver.
// - For resolved, non-call HIR paths to regular const declarations, including
//   one-segment imports made visible by the sorted import table, project the
//   declaration token and declaration type onto the path head, then clear the
//   fail-closed value-path status for that head.
// - It does not inspect source bytes, hash token text, scan for "::", perform
//   unqualified lookup, or ask the CPU to resolve values.

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
StructuredBuffer<uint> decl_name_token;
StructuredBuffer<uint> module_value_path_call_head;

RWStructuredBuffer<uint> module_value_path_status;
RWStructuredBuffer<uint> module_value_path_const_head;
RWStructuredBuffer<uint> module_value_path_const_end;
RWStructuredBuffer<uint> visible_decl;
RWStructuredBuffer<uint> visible_type;

static const uint INVALID = 0xffffffffu;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;
static const uint MAX_PATH_SEGMENTS = 8u;

static const uint PATH_RECORD_KIND_HIR_PATH_EXPR = 3u;
static const uint PATH_RESOLVE_STATUS_OK = 0u;
static const uint PATH_RESOLVE_STATUS_UNRESOLVED_DECL = 6u;

static const uint HIR_ITEM_KIND_CONST = 3u;
static const uint HIR_ITEM_KIND_ENUM_VARIANT = 9u;

static const uint TY_UNKNOWN = 0u;

uint linear_thread_id(uint3 dtid)
{
    return dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE;
}

uint active_path_count()
{
    return min(path_count_out[0], gParams.n_hir_nodes);
}

bool valid_const_decl(uint decl_i, out uint const_token)
{
    const_token = INVALID;
    if (decl_i >= gParams.n_hir_nodes)
        return false;
    if (decl_kind[decl_i] != HIR_ITEM_KIND_CONST)
        return false;

    uint token_i = decl_name_token[decl_i];
    if (token_i == INVALID || token_i >= gParams.n_tokens)
        return false;

    const_token = token_i;
    return true;
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
    uint segment_count = path_segment_count[path_i];
    if (segment_count == 0u)
        return;

    uint owner_token = path_owner_token[path_i];
    if (owner_token >= gParams.n_tokens)
        return;
    if (module_value_path_call_head[owner_token] != 0u)
        return;
    if (resolved_value_status[path_i] != PATH_RESOLVE_STATUS_OK)
        return;

    uint decl_i = resolved_value_decl[path_i];
    uint visible = visible_decl[owner_token];
    uint resolved_decl_name =
        decl_i < gParams.n_hir_nodes ? decl_name_token[decl_i] : INVALID;
    if (segment_count == 1u && visible != INVALID && visible != resolved_decl_name)
    {
        module_value_path_status[owner_token] = INVALID;
        return;
    }

    uint const_token;
    if (!valid_const_decl(decl_i, const_token))
    {
        if (decl_i < gParams.n_hir_nodes && decl_kind[decl_i] == HIR_ITEM_KIND_ENUM_VARIANT)
            return;
        if (module_value_path_status[owner_token] == INVALID && segment_count == 1u)
            return;
        module_value_path_status[owner_token] = PATH_RESOLVE_STATUS_UNRESOLVED_DECL;
        return;
    }

    uint ty = visible_type[const_token];
    if (ty == TY_UNKNOWN)
    {
        module_value_path_status[owner_token] = PATH_RESOLVE_STATUS_UNRESOLVED_DECL;
        return;
    }

    visible_decl[owner_token] = const_token;
    visible_type[owner_token] = ty;
    module_value_path_const_head[owner_token] = 1u;
    uint count = min(segment_count, MAX_PATH_SEGMENTS);
    module_value_path_const_end[owner_token] =
        count == 0u ? owner_token : path_segment_token[path_segment_base[path_i] + count - 1u];
    module_value_path_status[owner_token] = INVALID;
}
