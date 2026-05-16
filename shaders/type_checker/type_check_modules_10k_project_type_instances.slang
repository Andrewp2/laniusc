// GPU type-instance projection from module resolver arrays.
//
// Scheduling contract:
// - Dispatch after type-instance collection has marked named generic instance
//   heads, after declaration generic arities have been derived from HIR, and
//   after module type paths have resolved through sorted resolver tables.
// - For local and qualified generic type expressions such as Option<i32> and
//   core::option::Option<i32>, publish the path head as a TYPE_REF_INSTANCE
//   pointing at the leaf generic instance token, and bind that instance to the
//   resolved declaration.
// - Generic argument refs are populated by the HIR arg-ref pass; this pass only
//   checks the declaration arity record and attaches the declaration token.
// - It does not inspect source bytes, hash token text, compare names by text,
//   scan token neighborhoods, perform CPU lookup, or create a same-source
//   shortcut.

struct Params
{
    uint n_tokens;
    uint source_len;
    uint n_hir_nodes;
};

ConstantBuffer<Params> gParams;

StructuredBuffer<uint> path_segment_count;
StructuredBuffer<uint> path_segment_base;
StructuredBuffer<uint> path_segment_token;
StructuredBuffer<uint> path_owner_token;
StructuredBuffer<uint> resolved_type_decl;
StructuredBuffer<uint> decl_name_token;
StructuredBuffer<uint> type_instance_kind;
StructuredBuffer<uint> type_instance_arg_count;
StructuredBuffer<uint> type_decl_generic_param_count;

RWStructuredBuffer<uint> type_expr_ref_tag;
RWStructuredBuffer<uint> type_expr_ref_payload;
RWStructuredBuffer<uint> type_instance_decl_token;
RWStructuredBuffer<uint> type_instance_state;

static const uint INVALID = 0xffffffffu;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;
static const uint MAX_PATH_SEGMENTS = 64u;
static const uint TYPE_INSTANCE_ARG_REF_STRIDE = 4u;

static const uint TYPE_REF_INSTANCE = 3u;

static const uint TYPE_INSTANCE_NAMED = 1u;
static const uint TYPE_INSTANCE_RESOLVED = 1u;
static const uint TYPE_INSTANCE_UNSUPPORTED = 3u;

uint linear_thread_id(uint3 dtid)
{
    return dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE;
}

bool valid_token(uint token)
{
    return token != INVALID && token < gParams.n_tokens;
}

uint leaf_token_for_path(uint path_i)
{
    uint count = min(path_segment_count[path_i], MAX_PATH_SEGMENTS);
    if (count == 0u)
        return INVALID;
    return path_segment_token[path_segment_base[path_i] + count - 1u];
}

bool bind_resolved_named_instance(uint owner_token, uint leaf_token, uint decl_token)
{
    if (!valid_token(owner_token) || !valid_token(leaf_token) || !valid_token(decl_token))
        return false;
    if (type_instance_kind[leaf_token] != TYPE_INSTANCE_NAMED)
        return false;

    uint actual_count = type_instance_arg_count[leaf_token];
    uint expected_count = type_decl_generic_param_count[decl_token];
    if (actual_count != expected_count || actual_count > TYPE_INSTANCE_ARG_REF_STRIDE)
    {
        type_instance_state[leaf_token] = TYPE_INSTANCE_UNSUPPORTED;
        return false;
    }

    type_instance_decl_token[leaf_token] = decl_token;
    type_instance_state[leaf_token] = TYPE_INSTANCE_RESOLVED;
    type_expr_ref_tag[owner_token] = TYPE_REF_INSTANCE;
    type_expr_ref_payload[owner_token] = leaf_token;
    return true;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint path_i = linear_thread_id(dtid);
    if (path_i >= gParams.n_hir_nodes)
        return;

    uint decl_i = resolved_type_decl[path_i];
    if (decl_i >= gParams.n_hir_nodes)
        return;

    uint owner_token = path_owner_token[path_i];
    uint leaf_token = leaf_token_for_path(path_i);
    uint decl_token = decl_name_token[decl_i];
    bind_resolved_named_instance(owner_token, leaf_token, decl_token);
}
