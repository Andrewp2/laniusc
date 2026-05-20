// GPU match payload type substitution.
//
// This pass consumes parser-owned match payload records plus declaration,
// resolver, and type-instance records. It publishes visible_type for payload
// binder declarations. Uses of those binders are resolved by the normal HIR
// visible-name table and then receive their type in the scope pass.

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
StructuredBuffer<uint> hir_match_scrutinee_node;
StructuredBuffer<uint> hir_match_arm_pattern_node;
StructuredBuffer<uint> hir_match_payload_owner_arm;
StructuredBuffer<uint> hir_match_payload_match_node;
StructuredBuffer<uint> hir_match_payload_ordinal;
StructuredBuffer<uint> hir_variant_payload_start;
StructuredBuffer<uint> hir_variant_payload_count;
StructuredBuffer<uint> visible_decl;
StructuredBuffer<uint> decl_id_by_name_token;
StructuredBuffer<uint> decl_kind;
StructuredBuffer<uint> decl_name_token;
StructuredBuffer<uint> decl_hir_node;
StructuredBuffer<uint> decl_parent_type_decl;
StructuredBuffer<uint> decl_type_ref_tag;
StructuredBuffer<uint> decl_type_ref_payload;
StructuredBuffer<uint> type_expr_ref_tag;
StructuredBuffer<uint> type_expr_ref_payload;
StructuredBuffer<uint> type_instance_decl_token;
StructuredBuffer<uint> type_instance_arg_start;
StructuredBuffer<uint> type_instance_arg_count;
StructuredBuffer<uint> type_instance_arg_ref_tag;
StructuredBuffer<uint> type_instance_arg_ref_payload;
StructuredBuffer<uint> type_generic_param_slot_by_token;

RWStructuredBuffer<uint> visible_type;

static const uint INVALID = 0xffffffffu;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

static const uint HIR_ITEM_KIND_ENUM = 7u;
static const uint HIR_ITEM_KIND_ENUM_VARIANT = 9u;

static const uint TYPE_REF_INVALID = 0u;
static const uint TYPE_REF_SCALAR = 1u;
static const uint TYPE_REF_GENERIC_PARAM = 2u;
static const uint TYPE_REF_INSTANCE = 3u;

static const uint TY_UNKNOWN = 0u;
static const uint TY_ENUM_BASE = 6144u;
static const uint TY_GENERIC_BASE = 8192u;

uint linear_thread_id(uint3 dtid)
{
    return dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE;
}

uint active_hir_node_count()
{
    return gParams.n_hir_nodes == 0u ? 0u : min(gParams.n_hir_nodes, hir_status[5u]);
}

bool valid_token(uint token)
{
    return token != INVALID && token < gParams.n_tokens;
}

bool valid_node(uint node)
{
    return node != INVALID && node < active_hir_node_count();
}

uint type_ref_to_type_code(uint tag, uint payload)
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
        return valid_token(decl_token) ? visible_type[decl_token] : TY_UNKNOWN;
    }
    return TY_UNKNOWN;
}

uint scrutinee_instance_for_match(uint match_node)
{
    if (!valid_node(match_node))
        return INVALID;
    uint scrutinee_node = hir_match_scrutinee_node[match_node];
    if (!valid_node(scrutinee_node))
        return INVALID;

    uint expr_token = hir_token_pos[scrutinee_node];
    if (!valid_token(expr_token))
        return INVALID;

    uint decl_token = visible_decl[expr_token];
    if (!valid_token(decl_token))
        return INVALID;

    if (decl_type_ref_tag[decl_token] != TYPE_REF_INSTANCE)
        return INVALID;
    return decl_type_ref_payload[decl_token];
}

bool enum_variant_decl_for_pattern(
    uint pattern_token,
    out uint enum_token,
    out uint variant_node)
{
    enum_token = INVALID;
    variant_node = INVALID;
    if (!valid_token(pattern_token))
        return false;

    uint variant_token = visible_decl[pattern_token];
    if (!valid_token(variant_token))
        return false;

    uint decl_i = decl_id_by_name_token[variant_token];
    if (!valid_node(decl_i) || decl_kind[decl_i] != HIR_ITEM_KIND_ENUM_VARIANT)
        return false;

    uint enum_decl_i = decl_parent_type_decl[decl_i];
    if (!valid_node(enum_decl_i) || decl_kind[enum_decl_i] != HIR_ITEM_KIND_ENUM)
        return false;

    enum_token = decl_name_token[enum_decl_i];
    variant_node = decl_hir_node[decl_i];
    return valid_token(enum_token) && valid_node(variant_node);
}

void substituted_ref(uint instance_i, uint type_head, out uint tag, out uint payload)
{
    tag = TYPE_REF_INVALID;
    payload = INVALID;
    if (!valid_token(type_head))
        return;

    tag = type_expr_ref_tag[type_head];
    payload = type_expr_ref_payload[type_head];
    if (tag != TYPE_REF_GENERIC_PARAM)
        return;

    uint slot = valid_token(payload) ? type_generic_param_slot_by_token[payload] : INVALID;
    if (slot == INVALID || instance_i == INVALID || slot >= type_instance_arg_count[instance_i])
        return;

    uint arg_i = type_instance_arg_start[instance_i] + slot;
    tag = type_instance_arg_ref_tag[arg_i];
    payload = type_instance_arg_ref_payload[arg_i];
}

uint payload_type_for_node(uint payload_node, uint owner_arm, uint ordinal)
{
    uint pattern_node = valid_node(owner_arm) ? hir_match_arm_pattern_node[owner_arm] : INVALID;
    if (!valid_node(pattern_node))
        return TY_UNKNOWN;

    uint pattern_token = hir_token_pos[pattern_node];
    if (!valid_token(pattern_token))
        return TY_UNKNOWN;

    uint enum_token;
    uint variant_node;
    if (!enum_variant_decl_for_pattern(pattern_token, enum_token, variant_node))
        return TY_UNKNOWN;

    uint match_node = valid_node(payload_node) ? hir_match_payload_match_node[payload_node] : INVALID;
    uint instance_i = scrutinee_instance_for_match(match_node);
    if (instance_i == INVALID || type_instance_decl_token[instance_i] != enum_token)
        return TY_UNKNOWN;

    uint payload_count = hir_variant_payload_count[variant_node];
    if (ordinal >= payload_count)
        return TY_UNKNOWN;

    uint payload_type_node = hir_variant_payload_start[variant_node] + ordinal;
    if (!valid_node(payload_type_node))
        return TY_UNKNOWN;

    uint payload_type_head = hir_token_pos[payload_type_node];
    uint tag;
    uint payload;
    substituted_ref(instance_i, payload_type_head, tag, payload);
    return type_ref_to_type_code(tag, payload);
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint payload_node = linear_thread_id(dtid);
    if (!valid_node(payload_node))
        return;

    uint owner_arm = hir_match_payload_owner_arm[payload_node];
    if (!valid_node(owner_arm))
        return;

    uint binder_token = hir_token_pos[payload_node];
    if (!valid_token(binder_token))
        return;

    uint payload_ty = payload_type_for_node(
        payload_node,
        owner_arm,
        hir_match_payload_ordinal[payload_node]);
    if (payload_ty != TY_UNKNOWN)
        visible_type[binder_token] = payload_ty;
}
