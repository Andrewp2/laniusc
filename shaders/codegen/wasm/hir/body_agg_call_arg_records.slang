// Build dense ABI argument records for direct-call body fragments.

import atomics;
import body_arg_byte_common;
import call_relocation;

struct ScanParams
{
    uint n_items;
    uint n_blocks;
    uint scan_step;
    uint out_capacity;
};

ConstantBuffer<ScanParams> gScan;

StructuredBuffer<uint4> body_fragment_meta;
StructuredBuffer<uint4> body_fragment_aux;
StructuredBuffer<uint> wasm_agg_call_arg_count_by_fragment;
StructuredBuffer<uint> wasm_agg_call_arg_count_local_prefix;
StructuredBuffer<uint> wasm_agg_call_arg_count_block_prefix;

RWStructuredBuffer<uint> wasm_agg_call_arg_len;
RWStructuredBuffer<uint4> wasm_agg_call_arg_meta;
RWStructuredBuffer<uint4> wasm_agg_call_arg_aux;
RWStructuredBuffer<uint> wasm_func_invalid_count_by_token;
RWStructuredBuffer<uint> wasm_func_detail_by_token;

static const uint BODY_FRAGMENT_PRINT_DIRECT_CALL_I64 = 23u;
static const uint BODY_FRAGMENT_RETURN_DIRECT_CALL_I32 = 24u;
static const uint BODY_FRAGMENT_LET_DIRECT_CALL_I32 = 25u;
static const uint BODY_FRAGMENT_ASSIGN_DIRECT_CALL_I32 = 26u;
static const uint BODY_FRAGMENT_ASSIGN_COMPOUND_DIRECT_CALL_I32 = 27u;
static const uint BODY_FRAGMENT_RETURN_BINARY_DIRECT_CALL_I32 = 29u;
static const uint BODY_FRAGMENT_LET_AGG_DIRECT_CALL_I32 = 44u;
static const uint BODY_FRAGMENT_RETURN_AGG_DIRECT_CALL_I32 = 45u;
static const uint BODY_FRAGMENT_LET_BINARY_DIRECT_CALL_I32 = 46u;
static const uint BODY_FRAGMENT_DIRECT_CALL_VOID = 59u;
static const uint ARG_WG_SIZE = 256u;
static const uint TY_BOOL = 2u;

uint arg_count_prefix_for_fragment(uint fragment_i)
{
    return wasm_global_exclusive_prefix(
        fragment_i,
        ARG_WG_SIZE,
        wasm_agg_call_arg_count_local_prefix,
        wasm_agg_call_arg_count_block_prefix);
}

bool fragment_for_arg_record(uint record_i, out uint fragment_i, out uint ordinal)
{
    fragment_i = INVALID;
    ordinal = 0u;

    uint lo = 0u;
    uint hi = gScan.n_items;
    for (uint guard = 0u; guard < 32u; guard += 1u)
    {
        if (lo >= hi)
            break;
        uint mid = lo + ((hi - lo) >> 1u);
        uint start = arg_count_prefix_for_fragment(mid);
        uint end = start + wasm_agg_call_arg_count_by_fragment[mid];
        if (end <= record_i)
            lo = mid + 1u;
        else
            hi = mid;
    }

    if (lo >= gScan.n_items)
        return false;

    uint start = arg_count_prefix_for_fragment(lo);
    uint count = wasm_agg_call_arg_count_by_fragment[lo];
    if (record_i < start || record_i >= start + count)
        return false;

    fragment_i = lo;
    ordinal = record_i - start;
    return true;
}

uint direct_fragment_call_node(uint kind, uint4 meta)
{
    return kind == BODY_FRAGMENT_RETURN_AGG_DIRECT_CALL_I32 ||
           kind == BODY_FRAGMENT_RETURN_BINARY_DIRECT_CALL_I32 ||
           kind == BODY_FRAGMENT_PRINT_DIRECT_CALL_I64 ||
           kind == BODY_FRAGMENT_RETURN_DIRECT_CALL_I32 ||
           kind == BODY_FRAGMENT_DIRECT_CALL_VOID
               ? meta.y
               : meta.z;
}

bool direct_record_fragment_kind(uint kind)
{
    return kind == BODY_FRAGMENT_LET_AGG_DIRECT_CALL_I32 ||
           kind == BODY_FRAGMENT_RETURN_AGG_DIRECT_CALL_I32 ||
           kind == BODY_FRAGMENT_LET_BINARY_DIRECT_CALL_I32 ||
           kind == BODY_FRAGMENT_RETURN_BINARY_DIRECT_CALL_I32 ||
           kind == BODY_FRAGMENT_PRINT_DIRECT_CALL_I64 ||
           kind == BODY_FRAGMENT_RETURN_DIRECT_CALL_I32 ||
           kind == BODY_FRAGMENT_LET_DIRECT_CALL_I32 ||
           kind == BODY_FRAGMENT_ASSIGN_DIRECT_CALL_I32 ||
           kind == BODY_FRAGMENT_ASSIGN_COMPOUND_DIRECT_CALL_I32 ||
           kind == BODY_FRAGMENT_DIRECT_CALL_VOID;
}

bool type_is_i32_abi_param(uint fn_token, uint ordinal, uint ty)
{
    if (ty == TY_BOOL || ty == TY_INT || ty == TY_UINT || ty == TY_STRING || ty >= TY_ARRAY_BASE)
        return true;
    return method_receiver_param(fn_token, ordinal);
}

bool direct_call_expr_and_len(uint node, out uint len)
{
    len = 0u;
    node = resolve_expr_node(node);
    if (!valid_node(node) || hir_kind[node] != HIR_CALL_EXPR)
        return false;

    uint callee_token = call_callee_token(node);
    uint fn_token = call_fn_token_for_call(node, callee_token);
    if (!supported_function_token(fn_token))
        return false;

    uint tail_len = 1u + wasm_call_index_len(wasm_func_slot_by_token[fn_token] + 31u);
    uint2 total = expr_subtree_total[node];
    if (total.y != 0u || total.x < tail_len)
        return false;
    len = total.x;
    return true;
}

bool direct_call_record_arg_expr_and_len(uint arg_node, uint param_ty, out uint len)
{
    len = 0u;
    uint resolved = resolve_expr_node(arg_node);
    if (param_ty != TY_STRING)
    {
        if (!valid_node(resolved))
            return false;
        uint2 total = expr_subtree_total[resolved];
        if (total.y != 0u || total.x == 0u)
            return false;
        len = total.x;
        return true;
    }
    return string_value_expr_and_len(arg_node, len);
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    uint record_i = linear_dispatch_id(tid);
    uint record_capacity = gParams.n_hir_nodes * 2u;
    if (record_i >= record_capacity)
        return;

    wasm_agg_call_arg_len[record_i] = 0u;
    wasm_agg_call_arg_meta[record_i] = uint4(INVALID, INVALID, INVALID, 0u);
    wasm_agg_call_arg_aux[record_i] = uint4(INVALID, TY_UNKNOWN, 0u, 0u);

    uint fragment_i = INVALID;
    uint ordinal = 0u;
    if (!fragment_for_arg_record(record_i, fragment_i, ordinal))
        return;

    uint4 meta = body_fragment_meta[fragment_i];
    uint kind = meta.x;
    if (!direct_record_fragment_kind(kind))
        return;

    uint4 aux = body_fragment_aux[fragment_i];
    uint call_node = direct_fragment_call_node(kind, meta);
    uint fn_token = aux.z;
    uint arg_node = direct_call_abi_arg_node(call_node, fn_token, ordinal);
    uint param_ty = call_param_type_value(fn_token, ordinal);
    uint len = 0u;
    bool param_ok = type_is_i32_abi_param(fn_token, ordinal, param_ty) || param_ty == TY_FLOAT;
    bool ok = param_ok && direct_call_record_arg_expr_and_len(arg_node, param_ty, len);
    if (!ok || len == 0u)
    {
        uint owner_fn = node_enclosing_fn_token(call_node);
        if (valid_token(owner_fn))
        {
            atomic_u32_add(wasm_func_invalid_count_by_token, owner_fn, 1u);
            atomic_u32_min(
                wasm_func_detail_by_token,
                owner_fn,
                valid_node(arg_node) ? hir_token_pos[arg_node] : hir_token_pos[call_node]);
        }
        len = 0u;
    }

    wasm_agg_call_arg_len[record_i] = len;
    wasm_agg_call_arg_meta[record_i] = uint4(fragment_i, call_node, arg_node, ordinal);
    wasm_agg_call_arg_aux[record_i] = uint4(fn_token, param_ty, 0u, 0u);
}
