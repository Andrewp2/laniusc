// Substitute enum match payload types from compact HIR family rows.

struct Params { uint n_tokens; uint source_len; uint n_hir_nodes; };
struct HirCore { uint kind; uint parent; uint token_start; uint token_end; };
struct HirPayload { uint a; uint b; uint c; uint d; };
struct HirMatchArm { uint owner; uint pattern; uint result; uint ordinal; };
struct HirMatchPayload { uint arm; uint pattern; uint ordinal; uint file_id; };
struct HirVariantPayload { uint variant; uint type_node; uint ordinal; uint file_id; };

ConstantBuffer<Params> gParams;
StructuredBuffer<uint> compact_hir_count;
StructuredBuffer<HirCore> compact_hir_core;
StructuredBuffer<HirPayload> compact_hir_payload;
StructuredBuffer<uint> compact_match_arm_count;
StructuredBuffer<HirMatchArm> compact_match_arms;
StructuredBuffer<uint> compact_match_payload_row_count;
StructuredBuffer<HirMatchPayload> compact_match_payloads;
StructuredBuffer<uint> compact_variant_count;
StructuredBuffer<uint> compact_variant_payload_start;
StructuredBuffer<uint> compact_variant_payload_count;
StructuredBuffer<uint> compact_variant_payload_row_count;
StructuredBuffer<HirVariantPayload> compact_variant_payloads;
RWStructuredBuffer<uint> visible_decl;
RWStructuredBuffer<uint> module_value_path_status;
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
StructuredBuffer<uint> type_instance_arg_count;
StructuredBuffer<uint> type_instance_arg_ref_tag;
StructuredBuffer<uint> type_instance_arg_ref_payload;
StructuredBuffer<uint> type_instance_arg_row_start;
StructuredBuffer<uint> type_instance_arg_row_count_out;
StructuredBuffer<uint> type_instance_arg_row_ref_tag;
StructuredBuffer<uint> type_instance_arg_row_ref_payload;
StructuredBuffer<uint> type_generic_param_slot_by_token;
RWStructuredBuffer<uint> visible_type;

static const uint INVALID = 0xffffffffu;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;
static const uint LEGACY_ARG_STRIDE = 4u;
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

uint active_hir_count() { return min(compact_hir_count[0u], gParams.n_hir_nodes); }
uint active_arm_count() { return min(compact_match_arm_count[0u], gParams.n_hir_nodes); }
uint active_payload_count() { return min(compact_match_payload_row_count[0u], gParams.n_hir_nodes); }
uint active_variant_count() { return min(compact_variant_count[0u], gParams.n_hir_nodes); }
uint active_variant_payload_count() { return min(compact_variant_payload_row_count[0u], gParams.n_hir_nodes); }
bool valid_hir(uint node) { return node != INVALID && node < active_hir_count(); }
bool valid_token(uint token) { return token != INVALID && token < gParams.n_tokens; }

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
    if (slot >= LEGACY_ARG_STRIDE)
        return false;
    uint fixed = instance_i * LEGACY_ARG_STRIDE + slot;
    tag = type_instance_arg_ref_tag[fixed];
    payload = type_instance_arg_ref_payload[fixed];
    return tag != TYPE_REF_INVALID;
}

bool scrutinee_context_for_match(uint match_node, uint enum_token, out uint instance_i)
{
    instance_i = INVALID;
    if (!valid_hir(match_node))
        return false;
    uint scrutinee_node = compact_hir_payload[match_node].a;
    if (!valid_hir(scrutinee_node))
        return false;
    uint expr_token = compact_hir_core[scrutinee_node].token_start;
    if (!valid_token(expr_token))
        return false;
    uint decl_token = visible_decl[expr_token];
    if (!valid_token(decl_token))
        return false;
    if (decl_type_ref_tag[decl_token] == TYPE_REF_INSTANCE)
    {
        instance_i = decl_type_ref_payload[decl_token];
        return valid_token(instance_i) && type_instance_decl_token[instance_i] == enum_token;
    }
    uint scrutinee_ty = visible_type[decl_token];
    if (scrutinee_ty == TY_UNKNOWN)
        scrutinee_ty = type_ref_to_type_code(
            decl_type_ref_tag[decl_token], decl_type_ref_payload[decl_token]);
    return scrutinee_ty == TY_ENUM_BASE + enum_token;
}

bool enum_variant_for_arm(
    HirMatchArm arm,
    out uint enum_token,
    out uint variant)
{
    enum_token = INVALID;
    variant = INVALID;
    if (!valid_hir(arm.pattern))
        return false;
    uint pattern_token = compact_hir_core[arm.pattern].token_start;
    if (!valid_token(pattern_token))
        return false;
    uint variant_token = visible_decl[pattern_token];
    if (!valid_token(variant_token))
        return false;
    uint decl_i = decl_id_by_name_token[variant_token];
    if (decl_i >= gParams.n_hir_nodes || decl_kind[decl_i] != HIR_ITEM_KIND_ENUM_VARIANT)
        return false;
    uint enum_decl_i = decl_parent_type_decl[decl_i];
    if (enum_decl_i >= gParams.n_hir_nodes || decl_kind[enum_decl_i] != HIR_ITEM_KIND_ENUM)
        return false;
    enum_token = decl_name_token[enum_decl_i];
    variant = decl_hir_node[decl_i];
    return valid_token(enum_token) && variant < active_variant_count();
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
    if (slot == INVALID || instance_i == INVALID)
        return;
    uint substituted_tag;
    uint substituted_payload;
    if (instance_arg_ref(instance_i, slot, substituted_tag, substituted_payload))
    {
        tag = substituted_tag;
        payload = substituted_payload;
    }
}

uint payload_type(HirMatchPayload payload_row)
{
    if (payload_row.arm >= active_arm_count())
        return TY_UNKNOWN;
    HirMatchArm arm = compact_match_arms[payload_row.arm];
    uint enum_token;
    uint variant;
    if (!enum_variant_for_arm(arm, enum_token, variant))
        return TY_UNKNOWN;
    uint instance_i;
    if (!scrutinee_context_for_match(arm.owner, enum_token, instance_i))
        return TY_UNKNOWN;
    uint count = compact_variant_payload_count[variant];
    uint start = compact_variant_payload_start[variant];
    if (payload_row.ordinal >= count || start == INVALID ||
        start + payload_row.ordinal >= active_variant_payload_count())
        return TY_UNKNOWN;
    HirVariantPayload variant_payload = compact_variant_payloads[start + payload_row.ordinal];
    if (variant_payload.variant != variant ||
        variant_payload.ordinal != payload_row.ordinal ||
        !valid_hir(variant_payload.type_node))
        return TY_UNKNOWN;
    uint type_head = compact_hir_core[variant_payload.type_node].token_start;
    uint tag;
    uint ref_payload;
    substituted_ref(instance_i, type_head, tag, ref_payload);
    return type_ref_to_type_code(tag, ref_payload);
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint row = linear_thread_id(dtid);
    if (row >= active_payload_count())
        return;
    HirMatchPayload payload = compact_match_payloads[row];
    if (payload.arm >= active_arm_count() || !valid_hir(payload.pattern))
        return;
    uint binder_token = compact_hir_core[payload.pattern].token_start;
    if (!valid_token(binder_token))
        return;
    visible_decl[binder_token] = binder_token;
    module_value_path_status[binder_token] = INVALID;
    uint ty = payload_type(payload);
    if (ty != TY_UNKNOWN)
        visible_type[binder_token] = ty;
}
