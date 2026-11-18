import hir_records;
import status;

// GPU HIR enum constructor call consumer.
//
// Inputs are resolver rows, parser-owned HIR call/variant/result records, and
// type-reference tables. This pass validates constructor shape. Complete
// parameter and result inference belongs to the shared callable binder.


struct Params
{
    uint n_tokens;
    uint source_len;
    uint n_hir_nodes;
};

ConstantBuffer<Params> gParams;


StructuredBuffer<uint> compact_hir_count;
StructuredBuffer<HirCore> compact_hir_core;
StructuredBuffer<uint> compact_variant_count;
StructuredBuffer<uint> compact_variant_payload_count;
StructuredBuffer<uint> path_count_out;
StructuredBuffer<uint> path_kind;
StructuredBuffer<uint> path_call_hir;
StructuredBuffer<uint> path_owner_token;
StructuredBuffer<uint> resolved_value_decl;
StructuredBuffer<uint> resolved_value_status;
StructuredBuffer<uint> decl_kind;
StructuredBuffer<uint> decl_name_token;
StructuredBuffer<uint> decl_hir_node;
StructuredBuffer<uint> decl_parent_type_decl;
StructuredBuffer<uint> call_arg_row_count;
StructuredBuffer<uint> module_value_path_call_head;

RWStructuredBuffer<uint> module_value_path_status;
RWStructuredBuffer<uint> status;

static const uint INVALID = 0xffffffffu;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;
static const uint PARAM_CACHE_STRIDE = 4u;
static const uint VARIANT_PAYLOAD_SLOT_STRIDE = 4u;

static const uint PATH_RESOLVE_STATUS_OK = 0u;
static const uint PATH_RESOLVE_STATUS_UNRESOLVED_DECL = 6u;
static const uint HIR_ITEM_KIND_ENUM = 7u;
static const uint HIR_ITEM_KIND_ENUM_VARIANT = 9u;
static const uint PATH_KIND_VALUE = 3u;
static const uint HIR_CALL_EXPR = 19u;
static const uint HIR_STMT = 7u;
static const uint HIR_LET_STMT = 8u;
static const uint HIR_RETURN_STMT = 9u;

static const uint TYPE_REF_INSTANCE = 3u;
static const uint ERR_CALL_MISMATCH = 10u;
static const uint CALL_MISMATCH_ARITY = 0xffffff05u;

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


bool valid_variant(uint row)
{
    return row != INVALID && row < min(compact_variant_count[0u], gParams.n_hir_nodes);
}

bool valid_enum_variant_decl(uint decl_i, out uint enum_decl_i, out uint enum_token, out uint variant)
{
    enum_decl_i = INVALID;
    enum_token = INVALID;
    variant = INVALID;
    if (decl_i >= gParams.n_hir_nodes || decl_kind[decl_i] != HIR_ITEM_KIND_ENUM_VARIANT)
        return false;

    enum_decl_i = decl_parent_type_decl[decl_i];
    if (enum_decl_i >= gParams.n_hir_nodes || decl_kind[enum_decl_i] != HIR_ITEM_KIND_ENUM)
        return false;

    enum_token = decl_name_token[enum_decl_i];
    variant = decl_hir_node[decl_i];
    return valid_token(enum_token) && valid_variant(variant);
}

uint dense_call_for_path(uint path_i)
{
    uint hir_count = min(compact_hir_count[0u], gParams.n_hir_nodes);
    uint call_node = path_i < active_path_count() ? path_call_hir[path_i] : INVALID;
    return call_node < hir_count && compact_hir_core[call_node].kind == HIR_CALL_EXPR
        ? call_node
        : INVALID;
}

uint call_arg_count_for_call(uint dense_call)
{
    return dense_call < min(compact_hir_count[0u], gParams.n_hir_nodes)
        ? call_arg_row_count[dense_call]
        : 0u;
}

bool prepare_enum_constructor_call(
    uint owner_token,
    uint dense_call,
    uint enum_token,
    uint variant)
{
    uint expected_count = compact_variant_payload_count[variant];
    if (expected_count > 0u && !valid_node(dense_call))
        return false;
    uint actual_count = call_arg_count_for_call(dense_call);
    if (actual_count != expected_count)
        return false;
    if (actual_count > PARAM_CACHE_STRIDE ||
        expected_count > VARIANT_PAYLOAD_SLOT_STRIDE)
        return false;
    return true;
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
    if (resolved_value_status[path_i] != PATH_RESOLVE_STATUS_OK)
    {
        module_value_path_status[owner_token] = resolved_value_status[path_i];
        return;
    }

    uint enum_decl_i;
    uint enum_token;
    uint variant;
    if (!valid_enum_variant_decl(resolved_value_decl[path_i], enum_decl_i, enum_token, variant))
    {
        module_value_path_status[owner_token] = PATH_RESOLVE_STATUS_UNRESOLVED_DECL;
        return;
    }

    uint dense_call = dense_call_for_path(path_i);
    if (valid_node(dense_call) &&
        call_arg_count_for_call(dense_call) != compact_variant_payload_count[variant])
    {
        record_min_token_error(
            status, owner_token, ERR_CALL_MISMATCH, CALL_MISMATCH_ARITY);
        module_value_path_status[owner_token] = INVALID;
        return;
    }
    if (!prepare_enum_constructor_call(owner_token, dense_call, enum_token, variant))
    {
        module_value_path_status[owner_token] = PATH_RESOLVE_STATUS_UNRESOLVED_DECL;
        return;
    }
    // The shared callable binder owns result inference. Receiving contexts
    // constrain that signature; this resolver must not replace an inferred
    // value's type with its destination's type.
    module_value_path_status[owner_token] = PATH_RESOLVE_STATUS_OK;
}
