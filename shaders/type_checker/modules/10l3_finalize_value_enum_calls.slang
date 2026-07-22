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

struct HirCore { uint kind; uint parent; uint token_start; uint token_end; };
struct HirPayload { uint a; uint b; uint c; uint d; };

StructuredBuffer<uint> compact_hir_count;
StructuredBuffer<HirCore> compact_hir_core;
StructuredBuffer<HirPayload> compact_hir_payload;
StructuredBuffer<uint> compact_variant_count;
StructuredBuffer<uint> compact_variant_payload_count;
StructuredBuffer<uint> path_count_out;
StructuredBuffer<uint> path_kind;
StructuredBuffer<uint> path_segment_count;
StructuredBuffer<uint> path_segment_base;
StructuredBuffer<uint> path_segment_token;
StructuredBuffer<uint> path_call_hir;
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
StructuredBuffer<uint> call_arg_row_count;
StructuredBuffer<uint> module_value_path_call_head;

RWStructuredBuffer<uint> module_value_path_status;
RWStructuredBuffer<uint> call_return_type;
RWStructuredBuffer<uint> visible_decl;

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
static const uint PATH_KIND_VALUE = 3u;
static const uint HIR_CALL_EXPR = 19u;

static const uint STMT_RECORD_KIND_LET = 1u;
static const uint STMT_RECORD_KIND_RETURN = 2u;

static const uint TYPE_REF_INSTANCE = 3u;
static const uint TY_ENUM_BASE = 6144u;
static const uint HIR_CALL_CONTEXT_ID_MASK = 0x7fffffffu;

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

bool valid_compact_node(uint node)
{
    return node != INVALID && node < min(compact_hir_count[0u], gParams.n_hir_nodes);
}

uint enclosing_function_decl_token(uint token)
{
    uint encoded_fn = valid_token(token) ? enclosing_fn[token] : 0u;
    uint fn_node = encoded_fn == 0u ? INVALID : encoded_fn - 1u;
    uint count = min(compact_hir_count[0u], gParams.n_hir_nodes);
    if (fn_node == INVALID || fn_node >= count)
        return INVALID;
    uint fn_token = compact_hir_payload[fn_node].b;
    return valid_token(fn_token) ? fn_token : INVALID;
}

bool valid_variant(uint row)
{
    return row != INVALID && row < min(compact_variant_count[0u], gParams.n_hir_nodes);
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

uint function_return_instance_for_token(uint token)
{
    if (!valid_token(token))
        return INVALID;

    uint fn_token = enclosing_function_decl_token(token);
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
    return valid_compact_node(call_node)
               ? function_return_instance_for_token(compact_hir_core[call_node].token_start)
                                 : INVALID;
}

uint contextual_instance_for_call(uint owner_token, uint call_node)
{
    uint encoded_context = valid_compact_node(call_node) ? compact_hir_payload[call_node].d
                                                         : HIR_CALL_CONTEXT_ID_MASK;
    uint context_node = (encoded_context & HIR_CALL_CONTEXT_ID_MASK) != HIR_CALL_CONTEXT_ID_MASK
        ? encoded_context & HIR_CALL_CONTEXT_ID_MASK
        : INVALID;
    if (!valid_compact_node(context_node))
        return function_return_instance_for_call(owner_token, call_node);

    HirPayload context = compact_hir_payload[context_node];
    uint context_kind = context.a;
    if (context_kind == STMT_RECORD_KIND_LET)
    {
        uint decl_token = context.b;
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

bool valid_enum_variant_decl(
    uint decl_i,
    out uint variant_token,
    out uint enum_token,
    out uint variant)
{
    variant_token = INVALID;
    enum_token = INVALID;
    variant = INVALID;
    if (decl_i >= gParams.n_hir_nodes || decl_kind[decl_i] != HIR_ITEM_KIND_ENUM_VARIANT)
        return false;

    uint enum_decl_i = decl_parent_type_decl[decl_i];
    if (enum_decl_i >= gParams.n_hir_nodes || decl_kind[enum_decl_i] != HIR_ITEM_KIND_ENUM)
        return false;

    variant_token = decl_name_token[decl_i];
    enum_token = decl_name_token[enum_decl_i];
    variant = decl_hir_node[decl_i];
    return valid_token(variant_token) && valid_token(enum_token) && valid_variant(variant);
}

uint dense_call_for_path(uint path_i)
{
    uint hir_count = min(compact_hir_count[0u], gParams.n_hir_nodes);
    uint call_node = path_i < active_path_count() ? path_call_hir[path_i] : INVALID;
    return call_node < hir_count && compact_hir_core[call_node].kind == HIR_CALL_EXPR
        ? call_node
        : INVALID;
}

bool prepared_constructor_still_valid(
    uint owner_token,
    uint call_node,
    uint enum_token,
    uint variant)
{
    uint actual_count = valid_compact_node(call_node) ? call_arg_row_count[call_node] : 0u;
    uint expected_count = compact_variant_payload_count[variant];
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
    if (path_kind[path_i] != PATH_KIND_VALUE)
        return;

    uint owner_token = path_owner_token[path_i];
    if (!valid_token(owner_token))
        return;
    if (module_value_path_call_head[owner_token] == 0u)
        return;
    if (resolved_value_status[path_i] != PATH_RESOLVE_STATUS_OK ||
        module_value_path_status[owner_token] != PATH_RESOLVE_STATUS_OK)
        return;

    uint variant_token;
    uint enum_token;
    uint variant;
    if (!valid_enum_variant_decl(
            resolved_value_decl[path_i], variant_token, enum_token, variant))
        return;

    uint call_node = dense_call_for_path(path_i);
    if (!prepared_constructor_still_valid(owner_token, call_node, enum_token, variant))
    {
        module_value_path_status[owner_token] = PATH_RESOLVE_STATUS_UNRESOLVED_DECL;
        return;
    }

    uint result_ty = TY_ENUM_BASE + enum_token;
    visible_decl[owner_token] = variant_token;
    call_return_type[owner_token] = result_ty;
    uint leaf_token = path_leaf_token(path_i, owner_token);
    if (leaf_token != owner_token)
    {
        visible_decl[leaf_token] = variant_token;
        call_return_type[leaf_token] = result_ty;
    }
    module_value_path_status[owner_token] = PATH_RESOLVE_STATUS_INVALID;
}
