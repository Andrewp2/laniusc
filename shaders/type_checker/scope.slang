// Scope/type projection from parser-owned records.
//
// HIR-backed compilation publishes visible declarations through the compact
// HIR declaration table and consumes parser/type records here. Token-only
// invocation fails closed with a syntax diagnostic because those shapes have no
// parser-owned scope records.

import status;

struct Params
{
    uint n_tokens;
    uint source_len;
    uint n_hir_nodes;
};

ConstantBuffer<Params> gParams;

StructuredBuffer<uint> token_count;
StructuredBuffer<uint> hir_status;
StructuredBuffer<uint> visible_decl;
StructuredBuffer<uint> decl_type_ref_tag;
StructuredBuffer<uint> decl_type_ref_payload;
StructuredBuffer<uint> type_generic_param_slot_by_token;
StructuredBuffer<uint> type_expr_ref_tag;
StructuredBuffer<uint> type_expr_ref_payload;
StructuredBuffer<uint> type_instance_kind;
StructuredBuffer<uint> type_instance_decl_token;
StructuredBuffer<uint> type_instance_arg_ref_tag;
StructuredBuffer<uint> type_instance_arg_ref_payload;
StructuredBuffer<uint> type_instance_elem_ref_tag;
StructuredBuffer<uint> type_instance_elem_ref_payload;

RWStructuredBuffer<uint> status;
RWStructuredBuffer<uint> visible_type;

static const uint INVALID = 0xffffffffu;
static const uint ERR_BAD_HIR = 6u;

static const uint TY_UNKNOWN = 0u;
static const uint TY_ARRAY_BASE = 128u;
static const uint TY_GENERIC_BASE = 8192u;

static const uint TYPE_REF_INVALID = 0u;
static const uint TYPE_REF_SCALAR = 1u;
static const uint TYPE_REF_GENERIC_PARAM = 2u;
static const uint TYPE_REF_INSTANCE = 3u;

static const uint TYPE_INSTANCE_NAMED = 1u;
static const uint TYPE_INSTANCE_ARRAY = 2u;
static const uint TYPE_INSTANCE_SLICE = 3u;
static const uint TYPE_INSTANCE_ARG_REF_STRIDE = 4u;

static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

uint linear_thread_id(uint3 dtid)
{
    return dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE;
}

uint active_token_count()
{
    return min(token_count[0], gParams.n_tokens);
}

uint active_hir_node_count()
{
    return gParams.n_hir_nodes == 0u ? 0u : min(gParams.n_hir_nodes, hir_status[5u]);
}

bool valid_token(uint token)
{
    return token != INVALID && token < active_token_count();
}

uint arg_ref_index(uint instance_i, uint slot)
{
    return instance_i * TYPE_INSTANCE_ARG_REF_STRIDE + slot;
}

void record_error(uint token_i, uint code, uint detail)
{
    record_min_token_error(status, token_i, code, detail);
}

uint type_code_for_non_alias_ref(uint tag, uint payload)
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
        uint instance_kind = type_instance_kind[payload];
        if (instance_kind == TYPE_INSTANCE_ARRAY || instance_kind == TYPE_INSTANCE_SLICE)
        {
            uint elem_tag = type_instance_elem_ref_tag[payload];
            uint elem_payload = type_instance_elem_ref_payload[payload];
            return elem_tag == TYPE_REF_SCALAR ? TY_ARRAY_BASE + elem_payload
                                               : TY_ARRAY_BASE + TY_UNKNOWN;
        }

        if (instance_kind == TYPE_INSTANCE_NAMED)
        {
            uint decl_token = type_instance_decl_token[payload];
            if (valid_token(decl_token))
                return visible_type[decl_token];
        }
    }
    return TY_UNKNOWN;
}

uint alias_arg_type_code(uint outer_instance_i, uint tag, uint payload)
{
    if (tag == TYPE_REF_GENERIC_PARAM && valid_token(payload))
    {
        uint slot = type_generic_param_slot_by_token[payload];
        if (slot == INVALID || slot >= TYPE_INSTANCE_ARG_REF_STRIDE)
            return TY_UNKNOWN;
        uint ref_i = arg_ref_index(outer_instance_i, slot);
        return type_code_for_non_alias_ref(
            type_instance_arg_ref_tag[ref_i],
            type_instance_arg_ref_payload[ref_i]);
    }
    return type_code_for_non_alias_ref(tag, payload);
}

uint alias_target_instance_type_code(uint outer_instance_i, uint target_instance_i, uint target_decl_token)
{
    uint target_tag = type_expr_ref_tag[target_decl_token];
    uint target_payload = type_expr_ref_payload[target_decl_token];
    if (target_tag == TYPE_REF_INVALID)
        return TY_UNKNOWN;
    if (target_tag == TYPE_REF_GENERIC_PARAM && valid_token(target_payload))
    {
        uint slot = type_generic_param_slot_by_token[target_payload];
        if (slot == INVALID || slot >= TYPE_INSTANCE_ARG_REF_STRIDE)
            return TY_UNKNOWN;
        uint ref_i = arg_ref_index(target_instance_i, slot);
        return alias_arg_type_code(
            outer_instance_i,
            type_instance_arg_ref_tag[ref_i],
            type_instance_arg_ref_payload[ref_i]);
    }
    return type_code_for_non_alias_ref(target_tag, target_payload);
}

uint alias_instance_type_code(uint instance_i, uint decl_token)
{
    uint target_tag = type_expr_ref_tag[decl_token];
    uint target_payload = type_expr_ref_payload[decl_token];
    if (target_tag == TYPE_REF_INVALID)
        return TY_UNKNOWN;
    if (target_tag == TYPE_REF_GENERIC_PARAM && valid_token(target_payload))
    {
        uint slot = type_generic_param_slot_by_token[target_payload];
        if (slot == INVALID || slot >= TYPE_INSTANCE_ARG_REF_STRIDE)
            return TY_UNKNOWN;
        uint ref_i = arg_ref_index(instance_i, slot);
        return type_code_for_non_alias_ref(
            type_instance_arg_ref_tag[ref_i],
            type_instance_arg_ref_payload[ref_i]);
    }
    if (target_tag == TYPE_REF_INSTANCE && valid_token(target_payload) &&
        type_instance_kind[target_payload] == TYPE_INSTANCE_NAMED)
    {
        uint target_decl = type_instance_decl_token[target_payload];
        if (valid_token(target_decl) && type_expr_ref_tag[target_decl] != TYPE_REF_INVALID)
        {
            uint target_ty = alias_target_instance_type_code(instance_i, target_payload, target_decl);
            if (target_ty != TY_UNKNOWN)
                return target_ty;
        }
    }
    return type_code_for_non_alias_ref(target_tag, target_payload);
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
        uint instance_kind = type_instance_kind[payload];
        if (instance_kind == TYPE_INSTANCE_ARRAY || instance_kind == TYPE_INSTANCE_SLICE)
        {
            uint elem_tag = type_instance_elem_ref_tag[payload];
            uint elem_payload = type_instance_elem_ref_payload[payload];
            return elem_tag == TYPE_REF_SCALAR ? TY_ARRAY_BASE + elem_payload
                                               : TY_ARRAY_BASE + TY_UNKNOWN;
        }

        if (instance_kind == TYPE_INSTANCE_NAMED)
        {
            uint decl_token = type_instance_decl_token[payload];
            uint alias_ty = valid_token(decl_token)
                                ? alias_instance_type_code(payload, decl_token)
                                : TY_UNKNOWN;
            if (alias_ty != TY_UNKNOWN)
                return alias_ty;
            if (valid_token(decl_token))
                return visible_type[decl_token];
        }
    }
    return TY_UNKNOWN;
}

uint declaration_type_from_ref(uint decl_i)
{
    if (!valid_token(decl_i))
        return TY_UNKNOWN;
    return type_code_for_ref(decl_type_ref_tag[decl_i], decl_type_ref_payload[decl_i]);
}

uint resolved_visible_decl(uint ident_i)
{
    return valid_token(ident_i) ? visible_decl[ident_i] : INVALID;
}

void publish_hir_visible_type(uint token_i)
{
    if (!valid_token(token_i))
        return;

    uint direct_ty = declaration_type_from_ref(token_i);
    if (direct_ty != TY_UNKNOWN)
        visible_type[token_i] = direct_ty;

    uint decl = resolved_visible_decl(token_i);
    if (decl == INVALID || decl == token_i || !valid_token(decl))
        return;

    uint decl_ty = declaration_type_from_ref(decl);
    if (decl_ty == TY_UNKNOWN)
        decl_ty = visible_type[decl];
    if (decl_ty != TY_UNKNOWN)
        visible_type[token_i] = decl_ty;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    uint token_i = linear_thread_id(tid);
    uint n_tokens = active_token_count();
    if (token_i >= n_tokens)
        return;

    if (active_hir_node_count() == 0u)
    {
        if (token_i == 0u)
            record_error(token_i, ERR_BAD_HIR, 0u);
        return;
    }

    publish_hir_visible_type(token_i);
}
