import utils;
import gpu_index;
import status;

// Direct x86_64 call-record projection.
//
// This pass projects parser-owned call nodes, resolver-owned call targets, and
// type-check return metadata into backend call records. It deliberately does
// not lower calls yet; later x86 ABI and instruction planning passes consume
// these rows instead of rediscovering call syntax.

struct Params
{
    uint n_tokens;
    uint source_len;
    uint out_capacity;
    uint n_hir_nodes;
};

ConstantBuffer<Params> gParams;

StructuredBuffer<uint> hir_status;
StructuredBuffer<uint> hir_kind;
StructuredBuffer<uint> hir_expr_record;
StructuredBuffer<uint> hir_expr_result_root_node;
StructuredBuffer<uint> path_count_out;
StructuredBuffer<uint> path_id_by_owner_hir;
StructuredBuffer<uint> resolved_value_decl;
StructuredBuffer<uint> resolved_value_status;
StructuredBuffer<uint> decl_name_token;
StructuredBuffer<uint> hir_item_name_token;
StructuredBuffer<uint> x86_decl_node_by_token;
StructuredBuffer<uint> x86_node_func;
StructuredBuffer<uint> x86_tree_parent;
StructuredBuffer<uint> hir_call_callee_node;
StructuredBuffer<uint> hir_token_pos;
StructuredBuffer<uint> hir_call_arg_count;
StructuredBuffer<uint> hir_member_receiver_node;
StructuredBuffer<uint> hir_member_name_token;
StructuredBuffer<uint> call_fn_index;
StructuredBuffer<uint> call_return_type;
StructuredBuffer<uint> call_return_type_token;
StructuredBuffer<uint> method_decl_receiver_mode;

RWStructuredBuffer<uint4> x86_call_record;
RWStructuredBuffer<uint> x86_call_type_record;
RWStructuredBuffer<uint> x86_call_callee_root_call;
RWStructuredBuffer<uint> call_record_status;

static const uint INVALID = 0xffffffffu;
static const uint DISPATCH_X_STRIDE = 16776960u;
static const uint HIR_CALL_EXPR = 19u;
static const uint HIR_MEMBER_EXPR = 21u;
static const uint HIR_NAME_EXPR = 22u;
static const uint EXPR_RECORD_STRIDE = 4u;
static const uint EXPR_RECORD_VALUE_TOKEN = 3u;
static const uint X86_CALL_TYPE_STRIDE = 3u;
static const uint X86_CALL_RECORDS_OK = 1u;
static const uint PATH_RESOLVE_STATUS_OK = 0u;
static const uint METHOD_RECEIVER_SELF = 1u;
static const uint METHOD_RECEIVER_REF_SELF = 2u;
static const uint METHOD_RECEIVER_EXPLICIT = 3u;

uint linear_dispatch_id(uint3 tid)
{
    return linear_dispatch_thread_id_2d(tid, DISPATCH_X_STRIDE);
}

uint active_hir_node_count()
{
    return active_count_from_status(gParams.n_hir_nodes, hir_status, 5u);
}

bool valid_node(uint node_i)
{
    return valid_index_or_invalid(node_i, active_hir_node_count(), INVALID);
}

bool valid_token(uint token_i)
{
    return valid_index_or_invalid(token_i, gParams.n_tokens, INVALID);
}

uint expr_record_slot(uint node, uint slot)
{
    return row_major_load<uint>(
        hir_expr_record,
        node,
        EXPR_RECORD_STRIDE,
        slot,
        INVALID);
}

uint expr_value_token(uint node)
{
    return valid_node(node) ? expr_record_slot(node, EXPR_RECORD_VALUE_TOKEN) : INVALID;
}

uint expr_root_node(uint node)
{
    return valid_node(node) ? hir_expr_result_root_node[node] : INVALID;
}

uint active_path_count()
{
    return min(path_count_out[0], gParams.n_hir_nodes);
}

uint resolved_function_token_for_node(uint node)
{
    if (!valid_node(node))
        return INVALID;
    uint path_i = path_id_by_owner_hir[node];
    if (path_i >= active_path_count() ||
        resolved_value_status[path_i] != PATH_RESOLVE_STATUS_OK)
        return INVALID;
    uint decl_i = resolved_value_decl[path_i];
    if (decl_i >= gParams.n_hir_nodes)
        return INVALID;
    uint fn_token = decl_name_token[decl_i];
    return valid_token(fn_token) ? fn_token : INVALID;
}

uint resolved_function_token_for_call(uint raw_callee_node, uint resolved_callee_node)
{
    uint fn_token = resolved_function_token_for_node(raw_callee_node);
    if (valid_token(fn_token))
        return fn_token;
    return resolved_function_token_for_node(resolved_callee_node);
}

uint callee_token_for_call(uint call_node)
{
    uint callee_node = hir_call_callee_node[call_node];
    if (valid_node(callee_node) && valid_node(hir_member_receiver_node[callee_node]))
        return hir_member_name_token[callee_node];

    callee_node = expr_root_node(callee_node);
    if (valid_node(callee_node) && hir_kind[callee_node] == HIR_MEMBER_EXPR)
        return hir_member_name_token[callee_node];
    return valid_node(callee_node) ? expr_value_token(callee_node) : INVALID;
}

bool is_method_call(uint call_node)
{
    uint callee_node = hir_call_callee_node[call_node];
    if (valid_node(callee_node) && valid_node(hir_member_receiver_node[callee_node]))
        return valid_token(hir_member_name_token[callee_node]);

    callee_node = expr_root_node(callee_node);
    return valid_node(callee_node) &&
           valid_node(hir_member_receiver_node[callee_node]) &&
           valid_token(hir_member_name_token[callee_node]);
}

bool method_takes_receiver(uint fn_token)
{
    uint mode = valid_token(fn_token) ? method_decl_receiver_mode[fn_token] : 0u;
    return mode == METHOD_RECEIVER_SELF ||
           mode == METHOD_RECEIVER_REF_SELF ||
           mode == METHOD_RECEIVER_EXPLICIT;
}

uint call_metadata_token(uint callee_token, uint call_slot, uint resolved_fn_token)
{
    if (valid_token(callee_token) && valid_token(call_fn_index[callee_token]))
        return callee_token;
    if (valid_token(call_slot) && valid_token(call_fn_index[call_slot]))
        return call_slot;
    if (valid_token(resolved_fn_token))
        return resolved_fn_token;
    return callee_token;
}

uint method_member_node_for_call(uint call_node)
{
    uint callee_node = hir_call_callee_node[call_node];
    if (valid_node(callee_node) && valid_node(hir_member_receiver_node[callee_node]))
        return callee_node;

    callee_node = expr_root_node(callee_node);
    return valid_node(callee_node) && valid_node(hir_member_receiver_node[callee_node])
               ? callee_node
               : INVALID;
}

bool method_call_has_value_receiver(uint call_node)
{
    uint member_node = method_member_node_for_call(call_node);
    uint receiver_node = valid_node(member_node) ? hir_member_receiver_node[member_node] : INVALID;
    return valid_node(receiver_node);
}

void mark_call_callee_root(uint call_node, uint root)
{
    if (valid_node(call_node) && valid_node(root))
        x86_call_callee_root_call[root] = call_node + 1u;
}

void mark_call_callee_name_wrapper(uint call_node, uint callee_node)
{
    if (!valid_node(callee_node))
        return;
    uint parent = x86_tree_parent[callee_node];
    if (valid_node(parent) && hir_kind[parent] == HIR_NAME_EXPR)
        mark_call_callee_root(call_node, parent);
}

void write_call_type_record(
    uint call_node,
    uint return_ty,
    uint return_ty_token,
    uint callee_token)
{
    row_major_store<uint>(x86_call_type_record, call_node, X86_CALL_TYPE_STRIDE, 0u, return_ty);
    row_major_store<uint>(
        x86_call_type_record,
        call_node,
        X86_CALL_TYPE_STRIDE,
        1u,
        return_ty_token);
    row_major_store<uint>(
        x86_call_type_record,
        call_node,
        X86_CALL_TYPE_STRIDE,
        2u,
        callee_token);
}

void clear_call_record(uint call_node)
{
    x86_call_record[call_node] = uint4(INVALID, INVALID, INVALID, INVALID);
    write_call_type_record(call_node, INVALID, INVALID, INVALID);
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    uint node_i = linear_dispatch_id(tid);
    if (node_i == 0u)
    {
        call_record_status[0u] = X86_CALL_RECORDS_OK;
        call_record_status[1u] = 0u;
        call_record_status[2u] = INVALID;
    }

    if (node_i >= active_hir_node_count() || hir_kind[node_i] != HIR_CALL_EXPR)
        return;

    uint owner_fn = x86_node_func[node_i];
    uint raw_callee_node = hir_call_callee_node[node_i];
    uint resolved_callee_node = expr_root_node(raw_callee_node);
    uint callee_token = callee_token_for_call(node_i);
    uint resolved_fn_token = resolved_function_token_for_call(raw_callee_node, resolved_callee_node);
    uint abi_name_token = valid_token(resolved_fn_token) ? resolved_fn_token : callee_token;
    bool method_call = is_method_call(node_i);
    uint call_slot = hir_token_pos[node_i];
    uint metadata_token = call_metadata_token(callee_token, call_slot, resolved_fn_token);
    uint target_fn = valid_token(metadata_token) ? call_fn_index[metadata_token] : INVALID;
    if (!valid_token(target_fn) && valid_token(resolved_fn_token))
        target_fn = resolved_fn_token;
    uint target_fn_node = valid_token(target_fn) ? x86_decl_node_by_token[target_fn] : INVALID;
    uint target_name_token = valid_node(target_fn_node)
                                 ? hir_item_name_token[target_fn_node]
                                 : INVALID;
    if (valid_token(target_name_token))
        abi_name_token = target_name_token;
    uint return_ty = valid_token(metadata_token) ? call_return_type[metadata_token] : 0u;
    uint return_ty_token = valid_token(metadata_token) ? call_return_type_token[metadata_token] : INVALID;
    uint receiver_arg_count =
        method_call && method_takes_receiver(target_fn) && method_call_has_value_receiver(node_i)
            ? 1u
            : 0u;
    uint explicit_arg_count = hir_call_arg_count[node_i];
    uint arg_count = explicit_arg_count + receiver_arg_count;

    x86_call_record[node_i] = uint4(
        owner_fn,
        target_fn,
        valid_token(call_slot) ? call_slot : INVALID,
        arg_count);
    write_call_type_record(node_i, return_ty, return_ty_token, abi_name_token);
    mark_call_callee_root(node_i, raw_callee_node);
    mark_call_callee_root(node_i, resolved_callee_node);
    mark_call_callee_name_wrapper(node_i, raw_callee_node);
    mark_call_callee_name_wrapper(node_i, resolved_callee_node);
}
