// GPU value-path fail-closed status projection from resolver arrays.
//
// Scheduling contract:
// - Dispatch after type path projection and value call-head marking, so
//   successfully resolved type expressions are not also treated as value
//   expressions and value status is propagated for downstream value consumers.
// - This pass consumes value resolution produced by the sorted GPU module/import
//   resolver. Call/value consumers are not allowed to accept qualified values
//   through token-level shortcuts, so qualified value paths write a
//   token-indexed status at the path head even when the resolver found a
//   declaration. HIR value/call consumers must read the value declaration arrays
//   directly and clear the status only for cases they really consume.
//   One-segment imported or top-level value paths also publish resolver status
//   when the sorted tables found a declaration or import ambiguity; unresolved
//   one-segment paths with no module owner or no import hit stay available to
//   normal lexical local/parameter lookup.
// - It does not inspect source bytes, hash token text, scan for "::", patch
//   call outputs, or perform any CPU lookup.

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
StructuredBuffer<uint> resolved_value_status;
StructuredBuffer<uint> module_type_path_status;
StructuredBuffer<uint> module_value_path_call_head;
StructuredBuffer<uint> module_value_path_expr_head;

RWStructuredBuffer<uint> module_value_path_status;

static const uint INVALID = 0xffffffffu;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

static const uint PATH_RECORD_KIND_HIR_PATH_EXPR = 3u;
static const uint PATH_RESOLVE_STATUS_OK = 0u;
static const uint PATH_RESOLVE_STATUS_UNRESOLVED = 2u;
static const uint PATH_RESOLVE_STATUS_INVALID_OWNER = 3u;
static const uint PATH_RESOLVE_STATUS_UNRESOLVED_DECL = 6u;

uint linear_thread_id(uint3 dtid)
{
    return dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE;
}

uint active_path_count()
{
    return min(path_count_out[0], gParams.n_hir_nodes);
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
    if (resolved_type_decl[path_i] != INVALID)
        return;
    if (module_type_path_status[owner_token] == PATH_RESOLVE_STATUS_OK)
        return;
    if (module_value_path_expr_head[owner_token] == 0u)
        return;
    if (segment_count == 1u &&
        (resolved_value_status[path_i] == PATH_RESOLVE_STATUS_UNRESOLVED ||
         resolved_value_status[path_i] == PATH_RESOLVE_STATUS_INVALID_OWNER ||
         resolved_value_status[path_i] == PATH_RESOLVE_STATUS_UNRESOLVED_DECL))
        return;
    module_value_path_status[owner_token] = resolved_value_status[path_i];
}
