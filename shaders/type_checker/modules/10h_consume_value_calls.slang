// GPU HIR-qualified value call consumer.
//
// This pass consumes resolver rows, HIR call records, and function return
// metadata. It does not inspect token kinds, source bytes, helper names, or
// function-body shapes to decide whether a resolved declaration is callable.
//
// Argument lookup and generic binding are handled by the row-dispatched call
// argument passes after this pass publishes call_fn_index for qualified calls.

import hir_records;
import status;

struct Params
{
    uint n_tokens;
    uint source_len;
    uint n_hir_nodes;
};

ConstantBuffer<Params> gParams;

StructuredBuffer<uint> path_count_out;
StructuredBuffer<uint> path_segment_count;
StructuredBuffer<uint> path_segment_base;
StructuredBuffer<uint> path_segment_token;
StructuredBuffer<uint> path_owner_hir;
StructuredBuffer<uint> path_owner_token;
StructuredBuffer<uint> resolved_type_decl;
StructuredBuffer<uint> resolved_value_decl;
StructuredBuffer<uint> resolved_value_status;
StructuredBuffer<uint> decl_token_start;
StructuredBuffer<uint> parent;
StructuredBuffer<uint> next_sibling;
StructuredBuffer<uint> hir_kind;
StructuredBuffer<uint> hir_call_callee_node;
StructuredBuffer<uint> hir_member_name_token;
StructuredBuffer<uint> hir_call_arg_count;
StructuredBuffer<uint4> call_arg_record;
StructuredBuffer<uint> call_arg_row_count;
StructuredBuffer<uint> call_param_count;

StructuredBuffer<uint> module_value_path_call_head;
StructuredBuffer<uint> module_value_path_call_open;
StructuredBuffer<uint> module_value_path_associated_method_token;
StructuredBuffer<uint> method_call_name_id;

RWStructuredBuffer<uint> module_value_path_status;
RWStructuredBuffer<uint> call_fn_index;
RWStructuredBuffer<uint> call_return_type;
RWStructuredBuffer<uint> call_return_type_token;
RWStructuredBuffer<uint> status;

static const uint INVALID = 0xffffffffu;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;
static const uint MAX_PATH_SEGMENTS = 9u;

static const uint PATH_RESOLVE_STATUS_OK = 0u;

static const uint TY_UNKNOWN = 0u;
static const uint TY_GENERIC_BASE = 8192u;

static const uint HIR_CALL_EXPR = 19u;
static const uint HIR_NAME_EXPR = 22u;
static const uint HIR_MEMBER_EXPR = 21u;
static const uint HIR_PATH_EXPR = 33u;

static const uint ERR_CALL_MISMATCH = 10u;
static const uint CALL_MISMATCH_ARITY = 0xffffff05u;

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

bool is_generic_type(uint ty)
{
    return ty >= TY_GENERIC_BASE;
}

void record_error(uint token_i, uint code, uint detail)
{
    record_min_token_error(status, token_i, code, detail);
}

uint call_node_for_callee_token(uint callee_i)
{
    if (!valid_token(callee_i))
        return INVALID;
    return call_arg_record[callee_i].z;
}

uint call_node_for_marked_head(uint owner_token)
{
    if (!valid_token(owner_token))
        return INVALID;

    uint encoded = module_value_path_call_head[owner_token];
    if (encoded <= 1u)
        return INVALID;

    uint call_node = encoded - 1u;
    return valid_node(call_node) && hir_kind[call_node] == HIR_CALL_EXPR
        ? call_node
        : INVALID;
}

uint normalized_path_owner_hir(uint owner_hir)
{
    uint node = owner_hir;
    for (uint step = 0u; step < 8u; step += 1u)
    {
        if (!valid_node(node))
            return INVALID;
        uint kind = hir_kind[node];
        if (kind == HIR_PATH_EXPR || kind == HIR_NAME_EXPR)
            return node;
        uint next = parent[node];
        if (!valid_node(next) || next == node)
            return node;
        node = next;
    }
    return node;
}

uint call_node_for_owner_hir(uint path_i)
{
    uint owner_hir = path_i < active_path_count() ? path_owner_hir[path_i] : INVALID;
    if (!valid_node(owner_hir))
        return INVALID;

    uint callee_anchor = normalized_path_owner_hir(owner_hir);
    if (!valid_node(callee_anchor))
        return INVALID;
    uint name_parent = parent[callee_anchor];

    if (hir_kind[callee_anchor] == HIR_PATH_EXPR &&
        valid_node(name_parent) &&
        hir_kind[name_parent] == HIR_NAME_EXPR)
    {
        callee_anchor = name_parent;
        name_parent = parent[name_parent];
    }

    if (valid_node(name_parent) && hir_kind[name_parent] == HIR_CALL_EXPR &&
        hir_call_callee_node[name_parent] == callee_anchor)
        return name_parent;

    uint call_expr = valid_node(callee_anchor) ? next_sibling[callee_anchor] : INVALID;
    return valid_node(call_expr) && hir_kind[call_expr] == HIR_CALL_EXPR ? call_expr : INVALID;
}

uint path_leaf_token(uint path_i, uint owner_token)
{
    uint count = path_i < active_path_count() ? path_segment_count[path_i] : 0u;
    if (count <= 1u)
        return owner_token;
    count = min(count, MAX_PATH_SEGMENTS);
    uint leaf_i = path_segment_base[path_i] + count - 1u;
    uint leaf_token =
        leaf_i < gParams.n_tokens * MAX_PATH_SEGMENTS ? path_segment_token[leaf_i] : INVALID;
    return valid_token(leaf_token) ? leaf_token : owner_token;
}

bool method_resolver_owns_path_call(uint path_i, uint owner_token)
{
    if (method_call_name_id[owner_token] != INVALID)
        return true;

    uint leaf_token = path_leaf_token(path_i, owner_token);
    if (leaf_token != owner_token && method_call_name_id[leaf_token] != INVALID)
        return true;

    uint method_token = module_value_path_associated_method_token[owner_token];
    if (!valid_token(method_token) && valid_token(leaf_token))
        method_token = module_value_path_associated_method_token[leaf_token];
    return valid_token(method_token) && method_call_name_id[method_token] != INVALID;
}

uint call_node_for_owner_token(uint path_i, uint owner_token)
{
    uint call_node = call_node_for_marked_head(owner_token);
    if (valid_node(call_node))
        return call_node;

    call_node = call_node_for_owner_hir(path_i);
    if (valid_node(call_node))
        return call_node;

    call_node = call_node_for_callee_token(owner_token);
    if (valid_node(call_node))
        return call_node;

    uint leaf_token = path_leaf_token(path_i, owner_token);
    if (leaf_token != owner_token)
    {
        call_node = call_node_for_callee_token(leaf_token);
        if (valid_node(call_node))
            return call_node;
    }

    uint call_head = module_value_path_call_open[owner_token];
    return valid_token(call_head) ? call_node_for_callee_token(call_head) : INVALID;
}

uint call_arg_count_for_call(uint owner_token, uint call_node)
{
    uint record_count = valid_token(owner_token) ? call_arg_record[owner_token].w : 0u;
    if (!valid_node(call_node))
        return record_count;
    uint compact_count = call_arg_row_count[call_node];
    return max(max(record_count, hir_call_arg_count[call_node]), compact_count);
}

bool valid_function_decl(uint decl_i, out uint fn_token)
{
    fn_token = INVALID;
    if (decl_i >= gParams.n_hir_nodes)
        return false;

    uint token_i = decl_token_start[decl_i];
    if (!valid_token(token_i) || call_fn_index[token_i] != token_i)
        return false;

    fn_token = token_i;
    return true;
}

bool validate_and_infer_call(
    uint path_i,
    uint owner_token,
    uint fn_token)
{
    uint call_node = call_node_for_owner_token(path_i, owner_token);

    uint expected_count = 0u;
    uint actual_count = 0u;
    expected_count = valid_token(fn_token) ? call_param_count[fn_token] : 0u;
    actual_count = valid_node(call_node)
        ? call_arg_count_for_call(owner_token, call_node)
        : INVALID;
    if (actual_count == INVALID)
    {
        call_return_type[owner_token] = TY_UNKNOWN;
        record_error(owner_token, ERR_CALL_MISMATCH, 0u);
        return false;
    }
    if (expected_count != actual_count)
    {
        call_return_type[owner_token] = TY_UNKNOWN;
        record_error(owner_token, ERR_CALL_MISMATCH, CALL_MISMATCH_ARITY);
        return false;
    }

    call_return_type[owner_token] = call_return_type[fn_token];
    call_return_type_token[owner_token] = call_return_type_token[fn_token];
    return true;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint path_i = linear_thread_id(dtid);
    if (path_i >= active_path_count())
        return;

    uint owner_token = path_owner_token[path_i];
    if (!valid_token(owner_token) || module_value_path_call_open[owner_token] == INVALID)
        return;
    if (method_resolver_owns_path_call(path_i, owner_token))
        return;
    if (resolved_type_decl[path_i] != INVALID)
        return;
    if (valid_token(call_fn_index[owner_token]))
        return;

    if (resolved_value_status[path_i] != PATH_RESOLVE_STATUS_OK)
    {
        module_value_path_status[owner_token] = resolved_value_status[path_i];
        return;
    }

    uint fn_token;
    if (!valid_function_decl(resolved_value_decl[path_i], fn_token))
        return;

    uint ret_ty = call_return_type[owner_token];
    if (!validate_and_infer_call(path_i, owner_token, fn_token))
    {
        module_value_path_status[owner_token] = INVALID;
        return;
    }

    if (call_return_type[owner_token] != TY_UNKNOWN)
        ret_ty = call_return_type[owner_token];
    else if (ret_ty == TY_UNKNOWN)
    {
        uint decl_ret_ty = call_return_type[fn_token];
        if (!is_generic_type(decl_ret_ty))
            ret_ty = decl_ret_ty;
    }

    call_fn_index[owner_token] = fn_token;
    if (ret_ty != TY_UNKNOWN)
        call_return_type[owner_token] = ret_ty;
    uint leaf_token = path_leaf_token(path_i, owner_token);
    if (leaf_token != owner_token)
    {
        call_fn_index[leaf_token] = fn_token;
        call_return_type[leaf_token] = call_return_type[owner_token];
        call_return_type_token[leaf_token] = call_return_type_token[owner_token];
    }
    module_value_path_status[owner_token] = INVALID;
}
