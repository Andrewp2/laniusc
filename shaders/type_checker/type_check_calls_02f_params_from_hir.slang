// HIR function parameter metadata projection.
//
// This pass consumes parser-owned parameter and type-expression records and
// writes the token-indexed function parameter cache used by call resolution and
// backend ABI projection. It does not inspect token spelling, source bytes,
// source-level names or function bodies.

import atomics;
import gpu_index;

struct Params
{
    uint n_tokens;
    uint source_len;
    uint n_hir_nodes;
};

ConstantBuffer<Params> gParams;

StructuredBuffer<uint> hir_status;
StructuredBuffer<uint> hir_token_pos;
StructuredBuffer<uint4> hir_param_record;
StructuredBuffer<uint> hir_param_type_node;
StructuredBuffer<uint> module_type_path_type;
StructuredBuffer<uint> type_generic_param_slot_by_token;
StructuredBuffer<uint> type_expr_ref_tag;
StructuredBuffer<uint> type_expr_ref_payload;
StructuredBuffer<uint> type_instance_kind;
StructuredBuffer<uint> type_instance_decl_token;
StructuredBuffer<uint> type_instance_arg_ref_tag;
StructuredBuffer<uint> type_instance_arg_ref_payload;
StructuredBuffer<uint> type_instance_elem_ref_tag;
StructuredBuffer<uint> type_instance_elem_ref_payload;

RWStructuredBuffer<uint> call_param_count;
RWStructuredBuffer<uint> call_param_type;
RWStructuredBuffer<uint> call_param_ref_tag;
RWStructuredBuffer<uint> call_param_ref_payload;

static const uint INVALID = 0xffffffffu;

static const uint TY_UNKNOWN = 0u;
static const uint TY_GENERIC_BASE = 8192u;

static const uint TYPE_REF_INVALID = 0u;
static const uint TYPE_REF_SCALAR = 1u;
static const uint TYPE_REF_GENERIC_PARAM = 2u;
static const uint TYPE_REF_INSTANCE = 3u;
static const uint TYPE_INSTANCE_NAMED = 1u;
static const uint TYPE_INSTANCE_ARRAY = 2u;
static const uint TYPE_INSTANCE_SLICE = 3u;
static const uint TYPE_INSTANCE_ARG_REF_STRIDE = 4u;
static const uint TY_ARRAY_BASE = 128u;
static const uint TY_STRUCT_BASE = 4096u;

static const uint HIR_PARAM_RECORD_FN = 0u;
static const uint HIR_PARAM_RECORD_ORDINAL = 1u;

static const uint PARAM_CACHE_STRIDE = 4u;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

uint linear_thread_id(uint3 dtid)
{
    return dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE;
}

uint active_hir_node_count()
{
    return gParams.n_hir_nodes;
}

bool valid_node(uint node)
{
    return node != INVALID && node < active_hir_node_count();
}

bool valid_token(uint token)
{
    return token != INVALID && token < gParams.n_tokens;
}

uint arg_ref_index(uint instance_i, uint slot)
{
    return instance_i * TYPE_INSTANCE_ARG_REF_STRIDE + slot;
}

uint param_type_node(uint param_node)
{
    return valid_node(param_node) ? hir_param_type_node[param_node] : INVALID;
}

uint scalar_or_named_type_code_for_ref(uint tag, uint payload)
{
    if (tag == TYPE_REF_SCALAR)
        return payload;
    if (tag == TYPE_REF_GENERIC_PARAM)
    {
        uint slot = valid_token(payload) ? type_generic_param_slot_by_token[payload] : INVALID;
        return slot == INVALID ? TY_UNKNOWN : TY_GENERIC_BASE + slot;
    }
    if (tag == TYPE_REF_INSTANCE && valid_token(payload))
    {
        uint named_ty = module_type_path_type[payload];
        if (named_ty != TY_UNKNOWN)
            return named_ty;
        uint decl_token = type_instance_decl_token[payload];
        if (valid_token(decl_token))
        {
            named_ty = module_type_path_type[decl_token];
            if (named_ty != TY_UNKNOWN)
                return named_ty;
            return TY_STRUCT_BASE + decl_token;
        }
    }
    return TY_UNKNOWN;
}

uint type_code_for_alias_arg_ref(uint tag, uint payload)
{
    if (tag == TYPE_REF_SCALAR)
        return payload;
    if (tag == TYPE_REF_GENERIC_PARAM)
    {
        uint slot = valid_token(payload) ? type_generic_param_slot_by_token[payload] : INVALID;
        return slot == INVALID ? TY_UNKNOWN : TY_GENERIC_BASE + slot;
    }
    if (tag == TYPE_REF_INSTANCE)
        return scalar_or_named_type_code_for_ref(tag, payload);
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
        return type_code_for_alias_arg_ref(
            type_instance_arg_ref_tag[ref_i],
            type_instance_arg_ref_payload[ref_i]);
    }
    return type_code_for_alias_arg_ref(tag, payload);
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
    return type_code_for_alias_arg_ref(target_tag, target_payload);
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
        return type_code_for_alias_arg_ref(
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
    return type_code_for_alias_arg_ref(target_tag, target_payload);
}

uint semantic_type_code_for_ref(uint tag, uint payload)
{
    if (tag == TYPE_REF_SCALAR)
        return payload;
    if (tag == TYPE_REF_GENERIC_PARAM)
    {
        uint slot = valid_token(payload) ? type_generic_param_slot_by_token[payload] : INVALID;
        return slot == INVALID ? TY_UNKNOWN : TY_GENERIC_BASE + slot;
    }
    if (tag == TYPE_REF_INSTANCE)
    {
        if (!valid_token(payload))
            return TY_UNKNOWN;

        uint kind = type_instance_kind[payload];
        if (kind == TYPE_INSTANCE_ARRAY || kind == TYPE_INSTANCE_SLICE)
        {
            uint elem_tag = type_instance_elem_ref_tag[payload];
            uint elem_payload = type_instance_elem_ref_payload[payload];
            uint elem_ty = scalar_or_named_type_code_for_ref(elem_tag, elem_payload);
            return elem_ty == TY_UNKNOWN ? TY_ARRAY_BASE + TY_UNKNOWN : TY_ARRAY_BASE + elem_ty;
        }

        if (kind == TYPE_INSTANCE_NAMED)
        {
            uint decl_token = type_instance_decl_token[payload];
            if (valid_token(decl_token))
            {
                uint alias_ty = alias_instance_type_code(payload, decl_token);
                if (alias_ty != TY_UNKNOWN)
                    return alias_ty;
                uint named_ty = module_type_path_type[payload];
                if (named_ty != TY_UNKNOWN)
                    return named_ty;
                named_ty = module_type_path_type[decl_token];
                if (named_ty != TY_UNKNOWN)
                    return named_ty;
                return TY_STRUCT_BASE + decl_token;
            }
        }

        return module_type_path_type[payload];
    }
    return TY_UNKNOWN;
}

bool param_type_ref(uint param_node, out uint tag, out uint payload)
{
    tag = TYPE_REF_INVALID;
    payload = INVALID;
    uint type_node = param_type_node(param_node);
    if (!valid_node(type_node))
        return false;

    uint type_token = hir_token_pos[type_node];
    if (!valid_token(type_token))
        return false;

    tag = type_expr_ref_tag[type_token];
    payload = type_expr_ref_payload[type_token];
    return tag != TYPE_REF_INVALID;
}

uint param_type_code(uint param_node)
{
    uint tag;
    uint payload;
    if (!param_type_ref(param_node, tag, payload))
        return TY_UNKNOWN;
    return semantic_type_code_for_ref(tag, payload);
}

void publish_param(uint param_node)
{
    uint4 record = hir_param_record[param_node];
    uint fn_node = record[HIR_PARAM_RECORD_FN];
    uint ordinal = record[HIR_PARAM_RECORD_ORDINAL];
    if (!valid_node(fn_node))
        return;

    uint fn_token = hir_token_pos[fn_node];
    if (!valid_token(fn_token))
        return;

    atomic_u32_max(call_param_count, fn_token, ordinal + 1u);
    if (ordinal >= PARAM_CACHE_STRIDE)
        return;

    uint tag;
    uint payload;
    param_type_ref(param_node, tag, payload);
    row_major_store<uint>(
        call_param_type,
        fn_token,
        PARAM_CACHE_STRIDE,
        ordinal,
        param_type_code(param_node));
    row_major_store<uint>(
        call_param_ref_tag,
        fn_token,
        PARAM_CACHE_STRIDE,
        ordinal,
        tag);
    row_major_store<uint>(
        call_param_ref_payload,
        fn_token,
        PARAM_CACHE_STRIDE,
        ordinal,
        payload);
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint node = linear_thread_id(dtid);
    if (node >= active_hir_node_count())
        return;

    publish_param(node);
}
