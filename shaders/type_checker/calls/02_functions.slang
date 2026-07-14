// HIR function metadata projection.
//
// This pass consumes parser/HIR records plus semantic type-reference records.
// It intentionally does not read token kinds, source bytes, source-level names, or
// whole function bodies. Parameter typing belongs in a separate HIR expression
// and declaration-type pass so this shader stays within the WebGPU storage
// buffer limit.

import lookup;

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
StructuredBuffer<uint> hir_item_kind;
StructuredBuffer<uint> hir_item_name_token;
StructuredBuffer<uint> hir_fn_return_type_node;
StructuredBuffer<uint> hir_method_owner_node;
StructuredBuffer<uint> name_id_by_token;
StructuredBuffer<uint> language_type_code_by_name_id;
StructuredBuffer<uint> generic_param_count_out;
StructuredBuffer<uint> generic_param_owner_node;
StructuredBuffer<uint> generic_param_name_id;
StructuredBuffer<uint> generic_param_token;
StructuredBuffer<uint> generic_param_kind;
StructuredBuffer<uint> generic_param_key_order;
StructuredBuffer<uint> module_type_path_type;
StructuredBuffer<uint> type_generic_param_slot_by_token;
StructuredBuffer<uint> fn_entrypoint_tag;
StructuredBuffer<uint> fn_return_ref_tag;
StructuredBuffer<uint> fn_return_ref_payload;
StructuredBuffer<uint> type_expr_ref_tag;
StructuredBuffer<uint> type_expr_ref_payload;
StructuredBuffer<uint> type_instance_kind;
StructuredBuffer<uint> type_instance_decl_token;
StructuredBuffer<uint> type_instance_arg_count;
StructuredBuffer<uint> type_instance_arg_row_start;
StructuredBuffer<uint> type_instance_arg_row_count_out;
StructuredBuffer<uint> type_instance_arg_row_ref_tag;
StructuredBuffer<uint> type_instance_arg_row_ref_payload;
StructuredBuffer<uint> type_instance_arg_ref_tag;
StructuredBuffer<uint> type_instance_arg_ref_payload;
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
static const uint TYPE_INSTANCE_ARG_REF_STRIDE = 4u;
static const uint GENERIC_PARAM_KIND_TYPE = 1u;
static const uint TY_ARRAY_BASE = 128u;
static const uint TY_STRUCT_BASE = 4096u;
static const uint TY_ENUM_BASE = 6144u;

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

uint active_generic_param_count()
{
    return min(generic_param_count_out[0u], gParams.n_tokens);
}

bool generic_param_key_less(uint row, uint owner, uint name_id)
{
    if (row >= active_generic_param_count())
        return false;

    uint row_owner = generic_param_owner_node[row];
    if (row_owner != owner)
        return row_owner < owner;
    return generic_param_name_id[row] < name_id;
}

bool generic_param_key_matches(uint row, uint owner, uint name_id, uint kind)
{
    return row < active_generic_param_count() &&
           generic_param_owner_node[row] == owner &&
           generic_param_name_id[row] == name_id &&
           generic_param_kind[row] == kind;
}

uint generic_param_row_for_name(uint decl_node, uint name_token, uint kind)
{
    if (!valid_node(decl_node) || !valid_token(name_token))
        return INVALID;

    uint name_id = name_id_by_token[name_token];
    if (name_id == INVALID)
        return INVALID;

    uint count = active_generic_param_count();
    uint lo = 0u;
    uint hi = count;
    for (uint step = 0u; step < 32u; step += 1u)
    {
        if (lo >= hi)
            continue;
        uint mid = lo + ((hi - lo) >> 1u);
        uint row = generic_param_key_order[mid];
        if (row >= count || !generic_param_key_less(row, decl_node, name_id))
            hi = mid;
        else
            lo = mid + 1u;
    }

    if (lo >= count)
        return INVALID;
    uint row = generic_param_key_order[lo];
    return generic_param_key_matches(row, decl_node, name_id, kind) ? row : INVALID;
}

uint generic_param_decl_token_for_name(uint decl_node, uint name_token)
{
    uint row = generic_param_row_for_name(decl_node, name_token, GENERIC_PARAM_KIND_TYPE);
    if (row == INVALID)
        return INVALID;
    uint token = generic_param_token[row];
    return valid_token(token) ? token : INVALID;
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
    if (slot >= TYPE_INSTANCE_ARG_REF_STRIDE)
        return false;
    uint fixed = instance_i * TYPE_INSTANCE_ARG_REF_STRIDE + slot;
    tag = type_instance_arg_ref_tag[fixed];
    payload = type_instance_arg_ref_payload[fixed];
    return tag != TYPE_REF_INVALID;
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

bool alias_target_ref(uint decl_token, out uint tag, out uint payload)
{
    tag = TYPE_REF_INVALID;
    payload = INVALID;
    if (!valid_token(decl_token))
        return false;
    tag = type_expr_ref_tag[decl_token];
    payload = type_expr_ref_payload[decl_token];
    return tag != TYPE_REF_INVALID;
}

uint alias_arg_type_code(uint outer_instance_i, uint tag, uint payload)
{
    if (tag == TYPE_REF_GENERIC_PARAM && valid_token(payload))
    {
        uint slot = type_generic_param_slot_by_token[payload];
        uint arg_tag;
        uint arg_payload;
        if (slot == INVALID || !instance_arg_ref(outer_instance_i, slot, arg_tag, arg_payload))
            return TY_UNKNOWN;
        return type_code_for_alias_arg_ref(arg_tag, arg_payload);
    }
    return type_code_for_alias_arg_ref(tag, payload);
}

uint alias_target_instance_type_code(uint outer_instance_i, uint target_instance_i, uint target_decl_token)
{
    uint target_tag;
    uint target_payload;
    if (!alias_target_ref(target_decl_token, target_tag, target_payload))
        return TY_UNKNOWN;
    if (target_tag == TYPE_REF_GENERIC_PARAM && valid_token(target_payload))
    {
        uint slot = type_generic_param_slot_by_token[target_payload];
        uint arg_tag;
        uint arg_payload;
        if (slot == INVALID || !instance_arg_ref(target_instance_i, slot, arg_tag, arg_payload))
            return TY_UNKNOWN;
        return alias_arg_type_code(
            outer_instance_i,
            arg_tag,
            arg_payload);
    }
    return type_code_for_alias_arg_ref(target_tag, target_payload);
}

uint alias_instance_type_code(uint instance_i, uint decl_token)
{
    uint target_tag;
    uint target_payload;
    if (!alias_target_ref(decl_token, target_tag, target_payload))
        return TY_UNKNOWN;
    if (target_tag == TYPE_REF_GENERIC_PARAM && valid_token(target_payload))
    {
        uint slot = type_generic_param_slot_by_token[target_payload];
        uint arg_tag;
        uint arg_payload;
        if (slot == INVALID || !instance_arg_ref(instance_i, slot, arg_tag, arg_payload))
            return TY_UNKNOWN;
        return type_code_for_alias_arg_ref(arg_tag, arg_payload);
    }
    if (target_tag == TYPE_REF_INSTANCE && valid_token(target_payload) &&
        type_instance_kind[target_payload] == TYPE_INSTANCE_NAMED)
    {
        uint target_decl = type_instance_decl_token[target_payload];
        uint ignored_tag;
        uint ignored_payload;
        if (valid_token(target_decl) && alias_target_ref(target_decl, ignored_tag, ignored_payload))
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
            return TY_UNKNOWN;
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

uint return_type_node(uint fn_node)
{
    if (!valid_node(fn_node))
        return INVALID;
    uint type_node = hir_fn_return_type_node[fn_node];
    return valid_node(type_node) ? type_node : INVALID;
}

uint scalar_return_type_for_function(uint fn_node)
{
    uint type_node = return_type_node(fn_node);
    if (!valid_node(type_node))
        return TY_UNKNOWN;

    uint type_token = hir_token_pos[type_node];
    if (!valid_token(type_token))
        return TY_UNKNOWN;

    uint ty = module_type_path_type[type_token];
    if (ty != TY_UNKNOWN)
        return ty;

    uint name_id = name_id_by_token[type_token];
    return name_id == INVALID ? TY_UNKNOWN : language_type_code_by_name_id[name_id];
}

void return_ref_for_function(uint fn_node, uint fn_decl_token, out uint tag, out uint payload)
{
    tag = fn_return_ref_tag[fn_decl_token];
    payload = fn_return_ref_payload[fn_decl_token];
    if (tag == TYPE_REF_GENERIC_PARAM &&
        valid_token(payload) &&
        type_generic_param_slot_by_token[payload] == INVALID)
    {
        uint decl_token = generic_param_decl_token_for_name(fn_node, payload);
        if (valid_token(decl_token))
            payload = decl_token;
    }
}

uint return_type_for_function(uint fn_node, uint fn_decl_token)
{
    uint tag;
    uint payload;
    return_ref_for_function(fn_node, fn_decl_token, tag, payload);
    if (tag != TYPE_REF_INVALID)
        return semantic_type_code_for_ref(tag, payload);
    uint scalar_ty = scalar_return_type_for_function(fn_node);
    if (scalar_ty != TY_UNKNOWN)
        return scalar_ty;
    if (fn_entrypoint_tag[fn_node] == ENTRYPOINT_MAIN)
        return TY_INT;
    return TY_VOID;
}

void publish_function_lookup(uint fn_node)
{
    uint fn_decl_token = declaration_token_for_function(fn_node);
    if (!valid_token(fn_decl_token))
        return;

    call_fn_index[fn_decl_token] = fn_decl_token;
    uint tag;
    uint payload;
    return_ref_for_function(fn_node, fn_decl_token, tag, payload);
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
           valid_node(hir_method_owner_node[node]);
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
