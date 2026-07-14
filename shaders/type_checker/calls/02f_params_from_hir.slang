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
StructuredBuffer<uint> hir_kind;
StructuredBuffer<uint> hir_token_pos;
StructuredBuffer<uint4> hir_param_record;
StructuredBuffer<uint> hir_param_type_node;
StructuredBuffer<uint> module_type_path_type;
StructuredBuffer<uint> name_id_by_token;
StructuredBuffer<uint> generic_param_count_out;
StructuredBuffer<uint> generic_param_owner_node;
StructuredBuffer<uint> generic_param_name_id;
StructuredBuffer<uint> generic_param_token;
StructuredBuffer<uint> generic_param_kind;
StructuredBuffer<uint> generic_param_key_order;
StructuredBuffer<uint> type_generic_param_slot_by_token;
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

RWStructuredBuffer<uint> call_param_count;
RWStructuredBuffer<uint> call_param_type;
RWStructuredBuffer<uint> call_param_ref_tag;
RWStructuredBuffer<uint> call_param_ref_payload;
RWStructuredBuffer<uint> call_param_row_flag;
RWStructuredBuffer<uint> call_param_row_node_type;
RWStructuredBuffer<uint> call_param_row_node_ref_tag;
RWStructuredBuffer<uint> call_param_row_node_ref_payload;

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
static const uint GENERIC_PARAM_KIND_TYPE = 1u;
static const uint TY_ARRAY_BASE = 128u;
static const uint TY_STRUCT_BASE = 4096u;

static const uint HIR_PARAM_RECORD_FN = 0u;
static const uint HIR_PARAM_RECORD_ORDINAL = 1u;
static const uint HIR_PARAM = 4u;

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

uint param_type_node(uint param_node)
{
    return valid_node(param_node) ? hir_param_type_node[param_node] : INVALID;
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

bool param_type_ref(uint param_node, uint fn_node, out uint tag, out uint payload)
{
    tag = TYPE_REF_INVALID;
    payload = INVALID;
    uint type_node = param_type_node(param_node);
    if (!valid_node(type_node))
        return false;

    uint type_token = hir_token_pos[type_node];
    if (!valid_token(type_token))
        return false;

    uint decl_token = generic_param_decl_token_for_name(fn_node, type_token);
    if (valid_token(decl_token))
    {
        tag = TYPE_REF_GENERIC_PARAM;
        payload = decl_token;
        return true;
    }

    tag = type_expr_ref_tag[type_token];
    payload = type_expr_ref_payload[type_token];
    if (tag != TYPE_REF_INVALID)
    {
        if (tag == TYPE_REF_GENERIC_PARAM && valid_token(payload) &&
            type_generic_param_slot_by_token[payload] == INVALID)
        {
            uint decl_token = generic_param_decl_token_for_name(fn_node, payload);
            if (valid_token(decl_token))
                payload = decl_token;
        }
        return true;
    }

    return false;
}

uint param_type_code(uint param_node, uint fn_node)
{
    uint tag;
    uint payload;
    if (!param_type_ref(param_node, fn_node, tag, payload))
        return TY_UNKNOWN;
    return semantic_type_code_for_ref(tag, payload);
}

void publish_param(uint param_node)
{
    call_param_row_flag[param_node] = 0u;
    call_param_row_node_type[param_node] = TY_UNKNOWN;
    call_param_row_node_ref_tag[param_node] = TYPE_REF_INVALID;
    call_param_row_node_ref_payload[param_node] = INVALID;

    if (!valid_node(param_node) || hir_kind[param_node] != HIR_PARAM)
        return;

    uint4 record = hir_param_record[param_node];
    uint fn_node = record[HIR_PARAM_RECORD_FN];
    uint ordinal = record[HIR_PARAM_RECORD_ORDINAL];
    if (!valid_node(fn_node))
        return;

    uint fn_token = hir_token_pos[fn_node];
    if (!valid_token(fn_token))
        return;

    atomic_u32_max(call_param_count, fn_token, ordinal + 1u);

    uint tag;
    uint payload;
    param_type_ref(param_node, fn_node, tag, payload);
    uint type_code = param_type_code(param_node, fn_node);
    call_param_row_flag[param_node] = 1u;
    call_param_row_node_type[param_node] = type_code;
    call_param_row_node_ref_tag[param_node] = tag;
    call_param_row_node_ref_payload[param_node] = payload;

    if (ordinal >= PARAM_CACHE_STRIDE)
        return;

    row_major_store<uint>(
        call_param_type,
        fn_token,
        PARAM_CACHE_STRIDE,
        ordinal,
        type_code);
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
