// GPU HIR enum constructor finalizer.
//
// Runs after per-payload validation. A constructor call is finalized only if
// the prepare pass left it as a valid candidate and no payload row rejected it.

struct Params
{
    uint n_tokens;
    uint source_len;
    uint n_hir_nodes;
};

ConstantBuffer<Params> gParams;

StructuredBuffer<uint> hir_stmt_record;
StructuredBuffer<uint> hir_token_pos;
StructuredBuffer<uint> hir_call_context_stmt_node;
StructuredBuffer<uint> hir_variant_payload_count;
StructuredBuffer<uint> path_count_out;
StructuredBuffer<uint> path_segment_count;
StructuredBuffer<uint> path_segment_base;
StructuredBuffer<uint> path_segment_token;
StructuredBuffer<uint> path_owner_token;
StructuredBuffer<uint> resolved_value_decl;
StructuredBuffer<uint> resolved_value_status;
StructuredBuffer<uint> decl_kind;
StructuredBuffer<uint> decl_name_token;
StructuredBuffer<uint> decl_hir_node;
StructuredBuffer<uint> decl_parent_type_decl;
StructuredBuffer<uint> type_instance_decl_token;
StructuredBuffer<uint> decl_type_ref_tag;
StructuredBuffer<uint> decl_type_ref_payload;
StructuredBuffer<uint> fn_return_ref_tag;
StructuredBuffer<uint> fn_return_ref_payload;
StructuredBuffer<uint> enclosing_fn;
StructuredBuffer<uint4> call_arg_record;
StructuredBuffer<uint> call_arg_row_count;

RWStructuredBuffer<uint> module_value_path_status;
RWStructuredBuffer<uint> call_return_type;

static const uint INVALID = 0xffffffffu;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;
static const uint PARAM_CACHE_STRIDE = 4u;
static const uint VARIANT_PAYLOAD_SLOT_STRIDE = 4u;

static const uint PATH_RESOLVE_STATUS_OK = 0u;
static const uint PATH_RESOLVE_STATUS_UNRESOLVED_DECL = 6u;
static const uint PATH_RESOLVE_STATUS_INVALID = 0xffffffffu;

static const uint HIR_ITEM_KIND_ENUM = 7u;
static const uint HIR_ITEM_KIND_ENUM_VARIANT = 9u;

static const uint STMT_RECORD_STRIDE = 4u;
static const uint STMT_RECORD_KIND_LET = 1u;
static const uint STMT_RECORD_KIND_RETURN = 2u;

static const uint TYPE_REF_INSTANCE = 3u;
static const uint TY_ENUM_BASE = 6144u;

uint linear_thread_id(uint3 dtid)
{
    return dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE;
}

uint active_path_count()
{
    return min(path_count_out[0], gParams.n_hir_nodes);
}

bool valid_token(uint token)
{
    return token != INVALID && token < gParams.n_tokens;
}

bool valid_node(uint node)
{
    return node != INVALID && node < gParams.n_hir_nodes;
}

uint path_leaf_token(uint path_i, uint owner_token)
{
    uint count = path_segment_count[path_i];
    if (count <= 1u)
        return owner_token;
    uint leaf_i = path_segment_base[path_i] + count - 1u;
    uint leaf_token =
        leaf_i < gParams.n_tokens ? path_segment_token[leaf_i] : INVALID;
    return valid_token(leaf_token) ? leaf_token : owner_token;
}

uint stmt_slot(uint node, uint slot)
{
    return node * STMT_RECORD_STRIDE + slot;
}

uint function_return_instance_for_token(uint token)
{
    if (!valid_token(token))
        return INVALID;

    uint encoded_fn = enclosing_fn[token];
    uint fn_token = encoded_fn == 0u ? INVALID : encoded_fn - 1u;
    if (valid_token(fn_token))
    {
        uint tag = fn_return_ref_tag[fn_token];
        uint payload = fn_return_ref_payload[fn_token];
        if (tag == TYPE_REF_INSTANCE && valid_token(payload))
            return payload;
    }
    return INVALID;
}

uint function_return_instance_for_call(uint owner_token, uint call_node)
{
    uint instance = function_return_instance_for_token(owner_token);
    if (instance != INVALID)
        return instance;
    return valid_node(call_node) ? function_return_instance_for_token(hir_token_pos[call_node])
                                 : INVALID;
}

uint contextual_instance_for_call(uint owner_token, uint call_node)
{
    uint context_node = valid_node(call_node) ? hir_call_context_stmt_node[call_node] : INVALID;
    if (!valid_node(context_node))
        return function_return_instance_for_call(owner_token, call_node);

    uint context_kind = hir_stmt_record[stmt_slot(context_node, 0u)];
    if (context_kind == STMT_RECORD_KIND_LET)
    {
        uint decl_token = hir_stmt_record[stmt_slot(context_node, 1u)];
        if (valid_token(decl_token))
        {
            uint tag = decl_type_ref_tag[decl_token];
            uint payload = decl_type_ref_payload[decl_token];
            if (tag == TYPE_REF_INSTANCE && valid_token(payload))
                return payload;
        }
    }

    if (context_kind == STMT_RECORD_KIND_RETURN && valid_token(owner_token))
    {
        uint instance = function_return_instance_for_call(owner_token, call_node);
        if (instance != INVALID)
            return instance;
    }

    return function_return_instance_for_call(owner_token, call_node);
}

bool valid_enum_variant_decl(uint decl_i, out uint enum_token, out uint variant_node)
{
    enum_token = INVALID;
    variant_node = INVALID;
    if (decl_i >= gParams.n_hir_nodes || decl_kind[decl_i] != HIR_ITEM_KIND_ENUM_VARIANT)
        return false;

    uint enum_decl_i = decl_parent_type_decl[decl_i];
    if (enum_decl_i >= gParams.n_hir_nodes || decl_kind[enum_decl_i] != HIR_ITEM_KIND_ENUM)
        return false;

    enum_token = decl_name_token[enum_decl_i];
    variant_node = decl_hir_node[decl_i];
    return valid_token(enum_token) && valid_node(variant_node);
}

uint call_arg_count_for_call(uint owner_token, uint call_node)
{
    uint record_count = valid_token(owner_token) ? call_arg_record[owner_token].w : 0u;
    if (!valid_node(call_node))
        return record_count;
    return max(record_count, call_arg_row_count[call_node]);
}

bool prepared_constructor_still_valid(uint owner_token, uint enum_token, uint variant_node)
{
    uint4 arg_record = call_arg_record[owner_token];
    uint call_node = arg_record.z;
    uint actual_count = call_arg_count_for_call(owner_token, call_node);
    uint expected_count = hir_variant_payload_count[variant_node];
    if (actual_count != expected_count)
        return false;
    if (actual_count > PARAM_CACHE_STRIDE ||
        expected_count > VARIANT_PAYLOAD_SLOT_STRIDE)
        return false;
    if (expected_count > 0u && !valid_node(call_node))
        return false;

    uint context_instance = contextual_instance_for_call(owner_token, call_node);
    return context_instance == INVALID || type_instance_decl_token[context_instance] == enum_token;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint path_i = linear_thread_id(dtid);
    if (path_i >= active_path_count())
        return;

    uint owner_token = path_owner_token[path_i];
    if (!valid_token(owner_token))
        return;
    if (resolved_value_status[path_i] != PATH_RESOLVE_STATUS_OK ||
        module_value_path_status[owner_token] != PATH_RESOLVE_STATUS_OK)
        return;

    uint enum_token;
    uint variant_node;
    if (!valid_enum_variant_decl(resolved_value_decl[path_i], enum_token, variant_node))
        return;

    if (!prepared_constructor_still_valid(owner_token, enum_token, variant_node))
    {
        module_value_path_status[owner_token] = PATH_RESOLVE_STATUS_UNRESOLVED_DECL;
        return;
    }

    uint result_ty = TY_ENUM_BASE + enum_token;
    call_return_type[owner_token] = result_ty;
    uint leaf_token = path_leaf_token(path_i, owner_token);
    if (leaf_token != owner_token)
        call_return_type[leaf_token] = result_ty;
    module_value_path_status[owner_token] = PATH_RESOLVE_STATUS_INVALID;
}
