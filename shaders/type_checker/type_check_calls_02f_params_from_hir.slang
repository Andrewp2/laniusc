// HIR function parameter metadata projection.
//
// This pass consumes parser-owned parameter and type-expression records and
// writes the token-indexed function parameter cache used by call resolution and
// backend ABI projection. It does not inspect token spelling, source bytes,
// source-level names or function bodies.

import atomics;
import generated_parse_production_ids;
import gpu_index;

struct Params
{
    uint n_tokens;
    uint source_len;
    uint n_hir_nodes;
};

ConstantBuffer<Params> gParams;

StructuredBuffer<uint> hir_status;
StructuredBuffer<uint> node_kind;
StructuredBuffer<uint> first_child;
StructuredBuffer<uint> hir_token_pos;
StructuredBuffer<uint> hir_type_form;
StructuredBuffer<uint4> hir_param_record;
StructuredBuffer<uint> module_type_path_type;
StructuredBuffer<uint> type_generic_param_slot_by_token;
StructuredBuffer<uint> type_expr_ref_tag;
StructuredBuffer<uint> type_expr_ref_payload;
StructuredBuffer<uint> type_instance_kind;
StructuredBuffer<uint> type_instance_decl_token;
StructuredBuffer<uint> type_instance_elem_ref_tag;
StructuredBuffer<uint> type_instance_elem_ref_payload;

RWStructuredBuffer<uint> call_param_count;
RWStructuredBuffer<uint> call_param_type;

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
static const uint TY_ARRAY_BASE = 128u;
static const uint TY_STRUCT_BASE = 4096u;

static const uint HIR_TYPE_FORM_NONE = 0u;

static const uint HIR_PARAM_RECORD_FN = 0u;
static const uint HIR_PARAM_RECORD_ORDINAL = 1u;
static const uint HIR_PARAM_RECORD_NODE = 3u;

static const uint PARAM_CACHE_STRIDE = 16u;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

uint linear_thread_id(uint3 dtid)
{
    return dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE;
}

uint active_hir_node_count()
{
    return gParams.n_hir_nodes == 0u ? 0u : min(gParams.n_hir_nodes, hir_status[5u]);
}

bool valid_node(uint node)
{
    return node != INVALID && node < active_hir_node_count();
}

bool valid_token(uint token)
{
    return token != INVALID && token < gParams.n_tokens;
}

uint child_node(uint node)
{
    if (!valid_node(node))
        return INVALID;
    uint child = first_child[node];
    return valid_node(child) ? child : INVALID;
}

uint param_type_node(uint param_node)
{
    if (!valid_node(param_node))
        return INVALID;

    uint prod = node_kind[param_node];
    uint child = child_node(param_node);
    if (!valid_node(child))
        return INVALID;

    if (prod == PROD_PARAM_NAMED)
        return hir_type_form[child] != HIR_TYPE_FORM_NONE ? child : INVALID;

    if (prod == PROD_PARAM_SELF)
    {
        uint typed_child = child_node(child);
        return valid_node(typed_child) && hir_type_form[typed_child] != HIR_TYPE_FORM_NONE
                   ? typed_child
                   : INVALID;
    }

    return INVALID;
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

uint param_type_code(uint param_node)
{
    uint type_node = param_type_node(param_node);
    if (!valid_node(type_node))
        return TY_UNKNOWN;

    uint type_token = hir_token_pos[type_node];
    if (!valid_token(type_token))
        return TY_UNKNOWN;

    uint tag = type_expr_ref_tag[type_token];
    uint payload = type_expr_ref_payload[type_token];
    if (tag == TYPE_REF_INVALID)
        return TY_UNKNOWN;
    return semantic_type_code_for_ref(tag, payload);
}

void publish_param(uint param_node)
{
    uint4 record = hir_param_record[param_node];
    uint fn_node = record[HIR_PARAM_RECORD_FN];
    uint ordinal = record[HIR_PARAM_RECORD_ORDINAL];
    uint source_param_node = record[HIR_PARAM_RECORD_NODE];
    if (!valid_node(fn_node) || !valid_node(source_param_node) || ordinal >= PARAM_CACHE_STRIDE)
        return;

    uint fn_token = hir_token_pos[fn_node];
    if (!valid_token(fn_token))
        return;

    atomic_u32_max(call_param_count, fn_token, ordinal + 1u);
    row_major_store<uint>(
        call_param_type,
        fn_token,
        PARAM_CACHE_STRIDE,
        ordinal,
        param_type_code(source_param_node));
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
