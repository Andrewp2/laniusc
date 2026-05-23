// HIR-record generic array/slice call return inference.
//
// This pass runs after call resolution, visible-declaration projection, and
// declaration type refs. It handles bounded call shapes:
//   fn first<T, const N: usize>(values: [T; N]) -> T
// or:
//   fn first_slice<T>(values: [T]) -> T
// plus matching array/slice identifier returns:
//   fn copy<T, const N: usize>(values: [T; N]) -> [T; N]
// called with one declaration-backed actual array/slice argument. It consumes
// HIR call/argument records and type-instance element refs; it does not inspect
// source bytes, token spellings, token kinds, helper names, or function bodies.

import gpu_index;
import hir_records;

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
StructuredBuffer<uint> hir_expr_record;
StructuredBuffer<uint> hir_call_callee_node;
StructuredBuffer<uint> hir_call_arg_parent_call;
StructuredBuffer<uint4> call_arg_record;
StructuredBuffer<uint> call_fn_index;
StructuredBuffer<uint> call_param_count;
StructuredBuffer<uint> call_param_type;
StructuredBuffer<uint> visible_decl;
StructuredBuffer<uint> decl_type_ref_tag;
StructuredBuffer<uint> decl_type_ref_payload;
StructuredBuffer<uint> type_generic_param_slot_by_token;
StructuredBuffer<uint> type_instance_kind;
StructuredBuffer<uint> type_instance_elem_ref_tag;
StructuredBuffer<uint> type_instance_elem_ref_payload;

RWStructuredBuffer<uint> call_return_type;

static const uint INVALID = 0xffffffffu;

static const uint HIR_CALL_EXPR = 19u;
static const uint HIR_NAME_EXPR = 22u;

static const uint HIR_EXPR_RECORD_STRIDE = 4u;
static const uint HIR_EXPR_RECORD_FORM = 0u;
static const uint HIR_EXPR_RECORD_LEFT = 1u;
static const uint HIR_EXPR_RECORD_VALUE_TOKEN = 3u;

static const uint HIR_EXPR_FORWARD = 1u;
static const uint HIR_EXPR_NAME = 2u;

static const uint TYPE_REF_SCALAR = 1u;
static const uint TYPE_REF_GENERIC_PARAM = 2u;
static const uint TYPE_REF_INSTANCE = 3u;

static const uint TYPE_INSTANCE_ARRAY = 2u;
static const uint TYPE_INSTANCE_SLICE = 3u;

static const uint TY_UNKNOWN = 0u;
static const uint TY_GENERIC_BASE = 8192u;
static const uint TY_ARRAY_BASE = 128u;

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

uint expr_slot(uint node, uint slot)
{
    return valid_node(node) ? hir_expr_record[node * HIR_EXPR_RECORD_STRIDE + slot] : INVALID;
}

uint expr_form(uint node)
{
    return expr_slot(node, HIR_EXPR_RECORD_FORM);
}

uint resolve_expr(uint node)
{
    [loop]
    for (uint guard = 0u; guard < 64u && valid_node(node); guard += 1u)
    {
        if (expr_form(node) != HIR_EXPR_FORWARD)
            return node;
        uint child = expr_slot(node, HIR_EXPR_RECORD_LEFT);
        if (!valid_node(child))
            return node;
        node = child;
    }
    return node;
}

uint name_token_for_expr(uint root)
{
    uint node = resolve_expr(root);
    if (!valid_node(node) || hir_kind[node] != HIR_NAME_EXPR)
        return INVALID;

    uint token = expr_slot(node, HIR_EXPR_RECORD_VALUE_TOKEN);
    return valid_token(token) ? token : hir_token_pos[node];
}

uint call_callee_token(uint call_node)
{
    if (!valid_node(call_node) || hir_kind[call_node] != HIR_CALL_EXPR)
        return INVALID;

    uint callee_node = hir_call_callee_node[call_node];
    if (!valid_node(callee_node))
        return INVALID;

    uint callee_token = hir_token_pos[callee_node];
    return valid_token(callee_token) ? callee_token : INVALID;
}

uint call_node_for_callee_token(uint callee_token)
{
    return valid_token(callee_token) ? call_arg_record[callee_token].z : INVALID;
}

uint call_arg_node_for_call(uint call_node, uint ordinal)
{
    if (!valid_node(call_node) || ordinal >= PARAM_CACHE_STRIDE)
        return INVALID;

    uint count = active_hir_node_count();
    [loop]
    for (uint node = 0u; node < count; node += 1u)
    {
        uint packed = hir_call_arg_parent_call[node];
        if (hir_node_ordinal_node(packed) == call_node &&
            hir_node_ordinal_ordinal(packed) == ordinal)
            return node;
    }
    return INVALID;
}

bool plain_generic_type(uint ty)
{
    return ty >= TY_GENERIC_BASE && ty < TY_GENERIC_BASE + PARAM_CACHE_STRIDE;
}

uint plain_generic_slot(uint ty)
{
    return plain_generic_type(ty) ? ty - TY_GENERIC_BASE : INVALID;
}

uint array_or_slice_generic_slot(uint ty)
{
    return ty >= TY_ARRAY_BASE + TY_GENERIC_BASE &&
           ty < TY_ARRAY_BASE + TY_GENERIC_BASE + PARAM_CACHE_STRIDE
               ? ty - TY_ARRAY_BASE - TY_GENERIC_BASE
               : INVALID;
}

uint type_code_for_ref(uint tag, uint payload)
{
    if (tag == TYPE_REF_SCALAR)
        return payload;
    if (tag == TYPE_REF_GENERIC_PARAM)
    {
        uint slot = valid_token(payload) ? type_generic_param_slot_by_token[payload] : INVALID;
        return slot == INVALID ? TY_UNKNOWN : TY_GENERIC_BASE + slot;
    }
    return TY_UNKNOWN;
}

uint array_or_slice_element_type_for_name_token(uint name_token)
{
    if (!valid_token(name_token))
        return TY_UNKNOWN;

    uint decl_token = visible_decl[name_token];
    if (!valid_token(decl_token))
        return TY_UNKNOWN;

    if (decl_type_ref_tag[decl_token] != TYPE_REF_INSTANCE)
        return TY_UNKNOWN;

    uint instance = decl_type_ref_payload[decl_token];
    if (!valid_token(instance))
        return TY_UNKNOWN;

    uint kind = type_instance_kind[instance];
    if (kind != TYPE_INSTANCE_ARRAY && kind != TYPE_INSTANCE_SLICE)
        return TY_UNKNOWN;

    return type_code_for_ref(
        type_instance_elem_ref_tag[instance],
        type_instance_elem_ref_payload[instance]);
}

uint array_or_slice_type_for_name_token(uint name_token)
{
    uint elem_ty = array_or_slice_element_type_for_name_token(name_token);
    return elem_ty == TY_UNKNOWN ? TY_UNKNOWN : TY_ARRAY_BASE + elem_ty;
}

void infer_array_generic_return(uint callee_token)
{
    if (!valid_token(callee_token))
        return;

    uint call_node = call_node_for_callee_token(callee_token);
    if (!valid_node(call_node))
        return;

    uint fn_token = call_fn_index[callee_token];
    if (!valid_token(fn_token))
        return;

    uint param_count = call_param_count[fn_token];
    uint arg_count = call_arg_record[callee_token].w;
    uint arg_node = call_arg_node_for_call(call_node, 0u);
    if (arg_count != 1u && !valid_node(arg_node))
        return;
    bool missing_param_metadata = param_count == 0u;
    if (!missing_param_metadata && param_count != 1u)
        return;

    uint param_ty = missing_param_metadata
                        ? TY_UNKNOWN
                        : row_major_load<uint>(
                              call_param_type,
                              fn_token,
                              PARAM_CACHE_STRIDE,
                              0u,
                              TY_UNKNOWN);
    uint param_slot = array_or_slice_generic_slot(param_ty);
    bool can_infer_from_single_array_arg = missing_param_metadata && param_ty == TY_UNKNOWN;

    uint arg_name = call_arg_record[callee_token].x;
    if (!valid_token(arg_name))
    {
        arg_name = name_token_for_expr(arg_node);
    }

    uint ret_ty = call_return_type[callee_token];
    if (ret_ty == TY_UNKNOWN)
        ret_ty = call_return_type[fn_token];
    uint ret_slot = plain_generic_slot(ret_ty);
    if (ret_slot != INVALID)
    {
        if (param_slot == INVALID)
        {
            if (!can_infer_from_single_array_arg)
                return;
            uint elem_ty = array_or_slice_element_type_for_name_token(arg_name);
            if (elem_ty != TY_UNKNOWN)
                call_return_type[callee_token] = elem_ty;
            return;
        }
        if (param_slot != ret_slot)
            return;

        uint elem_ty = array_or_slice_element_type_for_name_token(arg_name);
        if (elem_ty != TY_UNKNOWN)
            call_return_type[callee_token] = elem_ty;
        return;
    }

    uint ret_array_slot = array_or_slice_generic_slot(ret_ty);
    if (ret_array_slot == INVALID)
        return;
    if (param_slot == INVALID)
    {
        if (!can_infer_from_single_array_arg)
            return;
        uint array_ty = array_or_slice_type_for_name_token(arg_name);
        if (array_ty != TY_UNKNOWN)
            call_return_type[callee_token] = array_ty;
        return;
    }
    if (param_slot != ret_array_slot)
        return;

    uint array_ty = array_or_slice_type_for_name_token(arg_name);
    if (array_ty != TY_UNKNOWN)
        call_return_type[callee_token] = array_ty;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint callee_token = linear_thread_id(dtid);
    if (!valid_token(callee_token))
        return;

    infer_array_generic_return(callee_token);
}
