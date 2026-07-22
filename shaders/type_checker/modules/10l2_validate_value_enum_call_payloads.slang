// GPU HIR enum constructor payload validator.
//
// The constructor prepare pass keeps only structurally valid candidate calls in
// module_value_path_status. This pass fans those candidates out to one thread
// per payload slot, so payload type checks are a relation-style validation step
// rather than a consumer-local loop.

struct Params
{
    uint n_tokens;
    uint source_len;
    uint n_hir_nodes;
};

ConstantBuffer<Params> gParams;

StructuredBuffer<uint> call_arg_row_node;
StructuredBuffer<uint> call_arg_row_call_node;
StructuredBuffer<uint> call_arg_row_ordinal;
StructuredBuffer<uint> call_arg_row_start;
StructuredBuffer<uint> call_arg_row_count;
struct HirCore { uint kind; uint parent; uint token_start; uint token_end; };
struct HirPayload { uint a; uint b; uint c; uint d; };
struct HirVariant { uint owner; uint name_token; uint ordinal; uint file_id; };
struct HirVariantPayload { uint variant; uint type_node; uint ordinal; uint file_id; };
StructuredBuffer<uint> compact_hir_count;
StructuredBuffer<HirCore> compact_hir_core;
StructuredBuffer<HirPayload> compact_hir_payload;
StructuredBuffer<uint> compact_variant_count;
StructuredBuffer<HirVariant> compact_variants;
StructuredBuffer<uint> compact_variant_payload_start;
StructuredBuffer<uint> compact_variant_payload_count;
StructuredBuffer<uint> compact_variant_payload_row_count;
StructuredBuffer<HirVariantPayload> compact_variant_payloads;
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
StructuredBuffer<uint> type_expr_ref_tag;
StructuredBuffer<uint> type_expr_ref_payload;
StructuredBuffer<uint> type_generic_param_slot_by_token;
StructuredBuffer<uint> generic_param_count_out;
StructuredBuffer<uint> generic_param_owner_token;
StructuredBuffer<uint> generic_param_name_id;
StructuredBuffer<uint> generic_param_token;
StructuredBuffer<uint> generic_param_kind;
StructuredBuffer<uint> generic_param_key_order;
StructuredBuffer<uint> type_instance_decl_token;
StructuredBuffer<uint> type_instance_arg_start;
StructuredBuffer<uint> type_instance_arg_count;
StructuredBuffer<uint> type_instance_arg_ref_tag;
StructuredBuffer<uint> type_instance_arg_ref_payload;
StructuredBuffer<uint> type_instance_arg_row_start;
StructuredBuffer<uint> type_instance_arg_row_count_out;
StructuredBuffer<uint> type_instance_arg_row_ref_tag;
StructuredBuffer<uint> type_instance_arg_row_ref_payload;
StructuredBuffer<uint> decl_type_ref_tag;
StructuredBuffer<uint> decl_type_ref_payload;
StructuredBuffer<uint> fn_return_ref_tag;
StructuredBuffer<uint> fn_return_ref_payload;
StructuredBuffer<uint> visible_decl;
StructuredBuffer<uint> visible_type;
StructuredBuffer<uint> enclosing_fn;
StructuredBuffer<uint> module_value_path_call_head;
StructuredBuffer<uint> name_id_by_token;

RWStructuredBuffer<uint> module_value_path_status;

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
static const uint GENERIC_PARAM_KIND_TYPE = 1u;

static const uint STMT_RECORD_KIND_LET = 1u;
static const uint STMT_RECORD_KIND_RETURN = 2u;
static const uint HIR_CALL_CONTEXT_ID_MASK = 0x7fffffffu;

static const uint HIR_EXPR_NONE = 0u;
static const uint HIR_EXPR_NAME = 2u;
static const uint HIR_EXPR_INT = 3u;
static const uint HIR_EXPR_TRUE = 4u;
static const uint HIR_EXPR_FALSE = 5u;
static const uint HIR_EXPR_NOT = 6u;
static const uint HIR_EXPR_EQ = 7u;
static const uint HIR_EXPR_NE = 8u;
static const uint HIR_EXPR_LT = 9u;
static const uint HIR_EXPR_GT = 10u;
static const uint HIR_EXPR_LE = 11u;
static const uint HIR_EXPR_GE = 12u;
static const uint HIR_EXPR_NEG = 13u;
static const uint HIR_EXPR_ADD = 14u;
static const uint HIR_EXPR_SUB = 15u;
static const uint HIR_EXPR_MUL = 16u;
static const uint HIR_EXPR_AND = 17u;
static const uint HIR_EXPR_OR = 18u;
static const uint HIR_EXPR_MOD = 19u;
static const uint HIR_EXPR_DIV = 20u;
static const uint HIR_EXPR_BIT_OR = 21u;
static const uint HIR_EXPR_BIT_XOR = 22u;
static const uint HIR_EXPR_BIT_AND = 23u;
static const uint HIR_EXPR_SHL = 24u;
static const uint HIR_EXPR_SHR = 25u;
static const uint HIR_EXPR_FLOAT = 27u;

static const uint TYPE_REF_INVALID = 0u;
static const uint TYPE_REF_SCALAR = 1u;
static const uint TYPE_REF_GENERIC_PARAM = 2u;
static const uint TYPE_REF_INSTANCE = 3u;

static const uint TY_UNKNOWN = 0u;
static const uint TY_BOOL = 2u;
static const uint TY_INT = 3u;
static const uint TY_UINT = 4u;
static const uint TY_FLOAT = 5u;
static const uint TY_CHAR = 6u;
static const uint TY_STRING = 7u;
static const uint TY_ENUM_BASE = 6144u;
static const uint TY_GENERIC_BASE = 8192u;

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

bool valid_variant(uint row)
{
    return row != INVALID && row < min(compact_variant_count[0u], gParams.n_hir_nodes);
}

uint active_generic_param_count()
{
    return min(generic_param_count_out[0u], gParams.n_tokens);
}

bool generic_param_key_less(uint row, uint owner_token, uint name_id)
{
    uint row_owner = generic_param_owner_token[row];
    if (row_owner != owner_token)
        return row_owner < owner_token;
    return generic_param_name_id[row] < name_id;
}

bool generic_param_key_matches(uint row, uint owner_token, uint name_id)
{
    return row < active_generic_param_count() &&
           generic_param_owner_token[row] == owner_token &&
           generic_param_name_id[row] == name_id &&
           generic_param_kind[row] == GENERIC_PARAM_KIND_TYPE;
}

uint generic_param_token_for_variant_payload(uint variant, uint type_head)
{
    if (!valid_variant(variant) || !valid_token(type_head))
        return INVALID;

    HirVariant variant_row = compact_variants[variant];
    if (!valid_compact_node(variant_row.owner))
        return INVALID;

    uint owner_token = compact_hir_payload[variant_row.owner].b;
    uint name_id = name_id_by_token[type_head];
    if (!valid_token(owner_token) || name_id == INVALID)
        return INVALID;

    uint count = active_generic_param_count();
    if (count == 0u)
        return INVALID;
    uint lo = 0u;
    uint hi = count;
    for (uint step = 0u; step < 32u; step += 1u)
    {
        if (lo >= hi)
            continue;
        uint mid = lo + ((hi - lo) >> 1u);
        uint row = generic_param_key_order[mid];
        if (row >= count || !generic_param_key_less(row, owner_token, name_id))
            hi = mid;
        else
            lo = mid + 1u;
    }

    if (lo >= count)
        return INVALID;
    uint row = generic_param_key_order[lo];
    if (!generic_param_key_matches(row, owner_token, name_id))
        return INVALID;
    return generic_param_token[row];
}

uint expr_form(uint node)
{
    return valid_compact_node(node) ? compact_hir_payload[node].a : HIR_EXPR_NONE;
}

uint expr_value_token(uint node)
{
    if (!valid_compact_node(node))
        return INVALID;
    uint token = compact_hir_payload[node].d;
    return valid_token(token) ? token : compact_hir_core[node].token_start;
}

uint function_return_instance_for_token(uint token)
{
    if (!valid_token(token))
        return INVALID;

    uint encoded_fn = enclosing_fn[token];
    uint fn_node = encoded_fn == 0u ? INVALID : encoded_fn - 1u;
    uint count = min(compact_hir_count[0u], gParams.n_hir_nodes);
    uint fn_token = fn_node < count ? compact_hir_payload[fn_node].b : INVALID;
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

uint type_code_for_ref(uint tag, uint payload)
{
    if (tag == TYPE_REF_SCALAR)
        return payload;
    if (tag == TYPE_REF_GENERIC_PARAM && valid_token(payload))
    {
        uint slot = type_generic_param_slot_by_token[payload];
        return slot == INVALID ? TY_UNKNOWN : TY_GENERIC_BASE + slot;
    }
    if (tag == TYPE_REF_INSTANCE && valid_token(payload))
    {
        uint decl_token = type_instance_decl_token[payload];
        return valid_token(decl_token) ? TY_ENUM_BASE + decl_token : TY_UNKNOWN;
    }
    return TY_UNKNOWN;
}

uint visible_type_for_token(uint token)
{
    if (!valid_token(token))
        return TY_UNKNOWN;

    uint ty = visible_type[token];
    if (ty != TY_UNKNOWN)
        return ty;

    uint decl = visible_decl[token];
    if (valid_token(decl))
    {
        ty = visible_type[decl];
        if (ty != TY_UNKNOWN)
            return ty;

        ty = type_code_for_ref(decl_type_ref_tag[decl], decl_type_ref_payload[decl]);
        if (ty != TY_UNKNOWN)
            return ty;
    }

    return type_code_for_ref(decl_type_ref_tag[token], decl_type_ref_payload[token]);
}

uint direct_arithmetic_operand_type(uint node)
{
    if (!valid_compact_node(node))
        return TY_UNKNOWN;

    uint form = expr_form(node);
    if (form == HIR_EXPR_TRUE || form == HIR_EXPR_FALSE)
        return TY_BOOL;
    if (form == HIR_EXPR_INT)
        return TY_INT;
    if (form == HIR_EXPR_FLOAT)
        return TY_FLOAT;
    if (form == HIR_EXPR_NAME)
    {
        uint token = expr_value_token(node);
        if (!valid_token(token))
            token = compact_hir_core[node].token_start;
        return visible_type_for_token(token);
    }

    return TY_UNKNOWN;
}

uint direct_expr_type(uint node)
{
    if (!valid_compact_node(node))
        return TY_UNKNOWN;

    uint form = expr_form(node);
    if (form == HIR_EXPR_TRUE || form == HIR_EXPR_FALSE)
        return TY_BOOL;
    if (form == HIR_EXPR_INT)
        return TY_INT;
    if (form == HIR_EXPR_FLOAT)
        return TY_FLOAT;
    if (form == HIR_EXPR_NAME)
    {
        uint token = expr_value_token(node);
        if (!valid_token(token))
            token = compact_hir_core[node].token_start;
        return visible_type_for_token(token);
    }

    if (form == HIR_EXPR_NOT ||
        form == HIR_EXPR_EQ ||
        form == HIR_EXPR_NE ||
        form == HIR_EXPR_LT ||
        form == HIR_EXPR_GT ||
        form == HIR_EXPR_LE ||
        form == HIR_EXPR_GE ||
        form == HIR_EXPR_AND ||
        form == HIR_EXPR_OR)
        return TY_BOOL;

    if (form == HIR_EXPR_NEG ||
        form == HIR_EXPR_ADD ||
        form == HIR_EXPR_SUB ||
        form == HIR_EXPR_MUL ||
        form == HIR_EXPR_DIV)
    {
        HirPayload record = compact_hir_payload[node];
        uint left_ty = direct_arithmetic_operand_type(record.b);
        uint right_ty = direct_arithmetic_operand_type(record.c);
        return left_ty == TY_FLOAT || right_ty == TY_FLOAT ? TY_FLOAT : TY_INT;
    }

    if (form == HIR_EXPR_MOD ||
        form == HIR_EXPR_BIT_OR ||
        form == HIR_EXPR_BIT_XOR ||
        form == HIR_EXPR_BIT_AND ||
        form == HIR_EXPR_SHL ||
        form == HIR_EXPR_SHR)
        return TY_INT;

    return TY_UNKNOWN;
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

bool instance_arg_ref(uint instance_i, uint slot, out uint tag, out uint payload)
{
    tag = TYPE_REF_INVALID;
    payload = INVALID;
    if (!valid_token(instance_i) || slot >= type_instance_arg_count[instance_i])
        return false;

    uint start = type_instance_arg_row_start[instance_i];
    uint row = start == INVALID ? INVALID : start + slot;
    if (row != INVALID && row < type_instance_arg_row_count_out[0u])
    {
        tag = type_instance_arg_row_ref_tag[row];
        payload = type_instance_arg_row_ref_payload[row];
        if (tag != TYPE_REF_INVALID)
            return true;
    }

    if (slot >= PARAM_CACHE_STRIDE)
        return false;
    uint fixed = instance_i * PARAM_CACHE_STRIDE + slot;
    tag = type_instance_arg_ref_tag[fixed];
    payload = type_instance_arg_ref_payload[fixed];
    return tag != TYPE_REF_INVALID;
}

void substituted_ref(
    uint context_instance,
    uint variant,
    uint type_head,
    out uint tag,
    out uint payload)
{
    tag = type_expr_ref_tag[type_head];
    payload = type_expr_ref_payload[type_head];
    if (tag == TYPE_REF_INVALID)
    {
        uint generic_token = generic_param_token_for_variant_payload(variant, type_head);
        if (valid_token(generic_token))
        {
            tag = TYPE_REF_GENERIC_PARAM;
            payload = generic_token;
        }
    }
    if (tag != TYPE_REF_GENERIC_PARAM)
        return;

    if (context_instance == INVALID)
        return;

    uint slot = valid_token(payload) ? type_generic_param_slot_by_token[payload] : INVALID;
    if (slot == INVALID)
        return;

    uint substituted_tag;
    uint substituted_payload;
    if (instance_arg_ref(context_instance, slot, substituted_tag, substituted_payload))
    {
        tag = substituted_tag;
        payload = substituted_payload;
    }
}

bool assignable(uint dst, uint src)
{
    if (dst == TY_UNKNOWN || src == TY_UNKNOWN)
        return false;
    if (dst == src)
        return true;
    if (dst == TY_INT)
        return src == TY_UINT || src == TY_CHAR;
    if (dst == TY_UINT)
        return src == TY_INT || src == TY_CHAR;
    if (dst == TY_FLOAT)
        return src == TY_INT || src == TY_UINT || src == TY_CHAR;
    return false;
}

bool valid_enum_variant_decl(uint decl_i, out uint enum_token, out uint variant)
{
    enum_token = INVALID;
    variant = INVALID;
    if (decl_i >= gParams.n_hir_nodes || decl_kind[decl_i] != HIR_ITEM_KIND_ENUM_VARIANT)
        return false;

    uint enum_decl_i = decl_parent_type_decl[decl_i];
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

uint call_arg_node_for_call(uint call_node, uint ordinal)
{
    if (!valid_node(call_node))
        return INVALID;

    uint start = call_arg_row_start[call_node];
    uint count = call_arg_row_count[call_node];
    if (start == INVALID || ordinal >= count)
        return INVALID;

    uint row = start + ordinal;
    if (row >= gParams.n_hir_nodes ||
        call_arg_row_call_node[row] != call_node ||
        call_arg_row_ordinal[row] != ordinal)
        return INVALID;
    return call_arg_row_node[row];
}

bool payload_matches(
    uint path_i,
    uint owner_token,
    uint enum_token,
    uint variant,
    uint ordinal)
{
    uint call_node = dense_call_for_path(path_i);
    uint actual_count = valid_compact_node(call_node) ? call_arg_row_count[call_node] : 0u;
    uint expected_count = compact_variant_payload_count[variant];
    if (actual_count != expected_count ||
        actual_count > PARAM_CACHE_STRIDE ||
        expected_count > VARIANT_PAYLOAD_SLOT_STRIDE)
        return false;
    if (ordinal >= expected_count)
        return true;

    uint context_instance = contextual_instance_for_call(owner_token, call_node);
    if (context_instance != INVALID && type_instance_decl_token[context_instance] != enum_token)
        return false;

    uint payload_start = compact_variant_payload_start[variant];
    uint payload_row_count = min(compact_variant_payload_row_count[0u], gParams.n_hir_nodes);
    if (payload_start == INVALID || payload_start + ordinal >= payload_row_count)
        return false;
    HirVariantPayload payload_row = compact_variant_payloads[payload_start + ordinal];
    if (payload_row.variant != variant || payload_row.ordinal != ordinal ||
        !valid_compact_node(payload_row.type_node))
        return false;
    uint payload_head = compact_hir_core[payload_row.type_node].token_start;
    if (!valid_token(payload_head))
        return false;
    uint tag = TYPE_REF_INVALID;
    uint payload = INVALID;
    substituted_ref(context_instance, variant, payload_head, tag, payload);
    if (tag == TYPE_REF_GENERIC_PARAM && context_instance == INVALID)
        return false;
    uint expected_ty = type_code_for_ref(tag, payload);
    if (context_instance == INVALID && expected_ty == TY_UNKNOWN)
        return false;

    uint arg_node = call_arg_node_for_call(call_node, ordinal);
    uint actual_ty = direct_expr_type(arg_node);
    if (actual_ty == TY_UNKNOWN && context_instance != INVALID && expected_ty >= TY_GENERIC_BASE)
        return true;
    return assignable(expected_ty, actual_ty);
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint work_i = linear_thread_id(dtid);
    uint path_i = work_i / PARAM_CACHE_STRIDE;
    uint ordinal = work_i - path_i * PARAM_CACHE_STRIDE;
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

    uint enum_token;
    uint variant;
    if (!valid_enum_variant_decl(resolved_value_decl[path_i], enum_token, variant))
        return;

    if (!payload_matches(path_i, owner_token, enum_token, variant, ordinal))
        module_value_path_status[owner_token] = PATH_RESOLVE_STATUS_UNRESOLVED_DECL;
}
