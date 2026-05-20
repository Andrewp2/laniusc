// HIR function metadata projection.
//
// This pass consumes parser/HIR records plus semantic type-reference records.
// It intentionally does not read token kinds, source bytes, source-level names, or
// whole function bodies. Parameter typing belongs in a separate HIR expression
// and declaration-type pass so this shader stays within the WebGPU storage
// buffer limit.

import generated_parse_production_ids;
import lookup;

struct Params
{
    uint n_tokens;
    uint source_len;
    uint n_hir_nodes;
};

ConstantBuffer<Params> gParams;

StructuredBuffer<uint> hir_status;
StructuredBuffer<uint> node_kind;
StructuredBuffer<uint> hir_kind;
StructuredBuffer<uint> hir_token_pos;
StructuredBuffer<uint> hir_item_kind;
StructuredBuffer<uint> hir_item_name_token;
StructuredBuffer<uint> name_id_by_token;
StructuredBuffer<uint> module_type_path_type;
StructuredBuffer<uint> type_generic_param_slot_by_token;
StructuredBuffer<uint> fn_entrypoint_tag;
StructuredBuffer<uint> fn_return_ref_tag;
StructuredBuffer<uint> fn_return_ref_payload;
StructuredBuffer<uint> type_instance_kind;
StructuredBuffer<uint> type_instance_decl_token;
StructuredBuffer<uint> type_instance_elem_ref_tag;
StructuredBuffer<uint> type_instance_elem_ref_payload;

RWStructuredBuffer<uint> call_fn_index;
RWStructuredBuffer<uint> call_return_type;
RWStructuredBuffer<uint> call_return_type_token;
RWStructuredBuffer<uint> function_lookup_key;
RWStructuredBuffer<uint> function_lookup_fn;

static const uint INVALID = 0xffffffffu;

static const uint TY_UNKNOWN = 0u;
static const uint TY_VOID = 1u;
static const uint TY_INT = 3u;
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
static const uint TY_ENUM_BASE = 6144u;

static const uint HIR_FN = 3u;
static const uint HIR_ITEM_KIND_FN = 4u;
static const uint HIR_ITEM_KIND_EXTERN_FN = 5u;

static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;
static const uint ENTRYPOINT_MAIN = 1u;

uint linear_thread_id(uint3 dtid)
{
    return dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE;
}

uint active_hir_node_count()
{
    return gParams.n_hir_nodes == 0u ? 0u : min(gParams.n_hir_nodes, hir_status[5u]);
}

uint lookup_capacity()
{
    return max(gParams.n_tokens * 2u, 1u);
}

bool valid_node(uint node)
{
    return node != INVALID && node < active_hir_node_count();
}

bool valid_token(uint token)
{
    return token != INVALID && token < gParams.n_tokens;
}

uint declaration_token_for_function(uint fn_node)
{
    uint decl_token = hir_token_pos[fn_node];
    return valid_token(decl_token) ? decl_token : INVALID;
}

uint name_token_for_function(uint fn_node)
{
    uint name_token = hir_item_name_token[fn_node];
    return valid_token(name_token) ? name_token : INVALID;
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

uint return_type_token_for_ref(uint tag, uint payload)
{
    return (tag == TYPE_REF_GENERIC_PARAM || tag == TYPE_REF_INSTANCE) && valid_token(payload)
               ? payload
               : INVALID;
}

uint return_type_for_function(uint fn_node, uint fn_decl_token)
{
    uint tag = fn_return_ref_tag[fn_decl_token];
    uint payload = fn_return_ref_payload[fn_decl_token];
    if (tag != TYPE_REF_INVALID)
        return semantic_type_code_for_ref(tag, payload);
    if (fn_entrypoint_tag[fn_node] == ENTRYPOINT_MAIN ||
        (valid_token(fn_decl_token) && fn_entrypoint_tag[fn_decl_token] == ENTRYPOINT_MAIN))
        return TY_INT;
    return TY_VOID;
}

void publish_function_lookup(uint fn_node)
{
    uint fn_decl_token = declaration_token_for_function(fn_node);
    if (!valid_token(fn_decl_token))
        return;

    call_fn_index[fn_decl_token] = fn_decl_token;
    uint tag = fn_return_ref_tag[fn_decl_token];
    uint payload = fn_return_ref_payload[fn_decl_token];
    call_return_type_token[fn_decl_token] = return_type_token_for_ref(tag, payload);
    call_return_type[fn_decl_token] = return_type_for_function(fn_node, fn_decl_token);

    if (!function_item_kind(hir_item_kind[fn_node]))
        return;

    uint fn_name_token = name_token_for_function(fn_node);
    if (!valid_token(fn_name_token))
        return;

    uint key = name_id_by_token[fn_name_token];
    if (key == INVALID)
        return;

    open_address_publish_min_u32_buffer<OpenAddressU32InvalidMaxKeyOps>(
        key,
        fn_decl_token,
        lookup_capacity(),
        INVALID,
        function_lookup_key,
        function_lookup_fn);
}

bool function_item_kind(uint item_kind)
{
    return item_kind == HIR_ITEM_KIND_FN || item_kind == HIR_ITEM_KIND_EXTERN_FN;
}

bool function_decl_node(uint node)
{
    return function_item_kind(hir_item_kind[node]) ||
           (hir_kind[node] == HIR_FN && node_kind[node] == PROD_IMPL_FN);
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint node = linear_thread_id(dtid);
    if (node >= active_hir_node_count() || !function_decl_node(node))
        return;

    publish_function_lookup(node);
}
