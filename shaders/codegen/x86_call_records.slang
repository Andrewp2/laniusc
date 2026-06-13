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
StructuredBuffer<uint> x86_node_func;
StructuredBuffer<uint> x86_tree_parent;
StructuredBuffer<uint> hir_call_callee_node;
StructuredBuffer<uint> hir_token_pos;
StructuredBuffer<uint> hir_call_arg_count;
StructuredBuffer<uint> hir_member_name_token;
StructuredBuffer<uint> call_fn_index;
StructuredBuffer<uint> call_return_type;
StructuredBuffer<uint> call_return_type_token;
StructuredBuffer<uint> method_decl_param_offset;

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
static const uint X86_ERR_CALL_ARG_COUNT = 56u;
static const uint X86_BACKEND_MAX_PACKED_CALL_ARGS = 6u;

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

uint callee_token_for_call(uint call_node)
{
    uint callee_node = expr_root_node(hir_call_callee_node[call_node]);
    if (valid_node(callee_node) && hir_kind[callee_node] == HIR_MEMBER_EXPR)
        return hir_member_name_token[callee_node];
    return valid_node(callee_node) ? expr_value_token(callee_node) : INVALID;
}

bool is_method_call(uint call_node)
{
    uint callee_node = expr_root_node(hir_call_callee_node[call_node]);
    return valid_node(callee_node) && hir_kind[callee_node] == HIR_MEMBER_EXPR &&
           valid_token(hir_member_name_token[callee_node]);
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

void write_call_type_record(uint call_node, uint return_ty, uint return_ty_token, uint callee_token)
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

void mark_call_arg_count_error(uint detail)
{
    publish_stage_error_min_detail4(
        call_record_status,
        X86_ERR_CALL_ARG_COUNT,
        detail);
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
    bool method_call = is_method_call(node_i);
    uint target_fn = valid_token(callee_token) ? call_fn_index[callee_token] : INVALID;
    uint return_ty = valid_token(callee_token) ? call_return_type[callee_token] : 0u;
    uint return_ty_token = valid_token(callee_token) ? call_return_type_token[callee_token] : INVALID;
    uint receiver_arg_count =
        method_call && valid_token(target_fn) && valid_token(method_decl_param_offset[target_fn])
            ? 1u
            : 0u;
    uint explicit_arg_count = hir_call_arg_count[node_i];
    uint arg_count = explicit_arg_count;
    if (receiver_arg_count != 0u)
        arg_count = explicit_arg_count < X86_BACKEND_MAX_PACKED_CALL_ARGS
                        ? explicit_arg_count + 1u
                        : X86_BACKEND_MAX_PACKED_CALL_ARGS + 1u;
    uint call_slot = hir_token_pos[node_i];
    if (arg_count > X86_BACKEND_MAX_PACKED_CALL_ARGS)
    {
        clear_call_record(node_i);
        mark_call_arg_count_error(valid_token(call_slot) ? call_slot : node_i);
        return;
    }

    x86_call_record[node_i] = uint4(
        owner_fn,
        target_fn,
        valid_token(call_slot) ? call_slot : INVALID,
        arg_count);
    write_call_type_record(node_i, return_ty, return_ty_token, callee_token);
    mark_call_callee_root(node_i, raw_callee_node);
    mark_call_callee_root(node_i, resolved_callee_node);
    mark_call_callee_name_wrapper(node_i, raw_callee_node);
    mark_call_callee_name_wrapper(node_i, resolved_callee_node);
}
