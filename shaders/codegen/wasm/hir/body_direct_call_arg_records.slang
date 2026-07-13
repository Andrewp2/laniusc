// Build dense ABI argument records for plain scalar direct-call body fragments.

import atomics;
import body_common;

struct ScanParams
{
    uint n_items;
    uint n_blocks;
    uint scan_step;
    uint out_capacity;
};

ConstantBuffer<ScanParams> gScan;

RWStructuredBuffer<uint> wasm_agg_call_arg_len;
RWStructuredBuffer<uint4> wasm_agg_call_arg_meta;
RWStructuredBuffer<uint4> wasm_agg_call_arg_aux;

StructuredBuffer<uint4> body_fragment_meta;
StructuredBuffer<uint4> body_fragment_aux;
StructuredBuffer<uint> wasm_agg_call_arg_count_by_fragment;
StructuredBuffer<uint> wasm_agg_call_arg_count_local_prefix;
StructuredBuffer<uint> wasm_agg_call_arg_count_block_prefix;

static const uint ARG_WG_SIZE = 256u;

uint wasm_global_exclusive_prefix(
    uint item_i,
    uint workgroup_size,
    StructuredBuffer<uint> local_prefix,
    StructuredBuffer<uint> block_prefix)
{
    uint block_i = item_i / workgroup_size;
    uint prior_blocks = block_i == 0u ? 0u : block_prefix[block_i - 1u];
    return prior_blocks + local_prefix[item_i];
}

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
    return kind == BODY_FRAGMENT_PRINT_DIRECT_CALL_I64 ||
           kind == BODY_FRAGMENT_RETURN_DIRECT_CALL_I32 ||
           kind == BODY_FRAGMENT_DIRECT_CALL_VOID
               ? meta.y
               : meta.z;
}

bool direct_call_record_arg_expr_and_len(uint arg_node, uint param_ty, out uint len)
{
    len = 0u;
    uint resolved = resolve_expr_node(arg_node);
    if (valid_node(resolved) &&
        hir_kind[resolved] == HIR_CALL_EXPR &&
        param_ty != TY_STRING &&
        param_ty < TY_ARRAY_BASE)
    {
        return direct_call_expr_and_len(resolved, len);
    }
    return direct_call_arg_abi_expr_and_len(arg_node, param_ty, len);
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
    if (kind != BODY_FRAGMENT_PRINT_DIRECT_CALL_I64 &&
        kind != BODY_FRAGMENT_RETURN_DIRECT_CALL_I32 &&
        kind != BODY_FRAGMENT_LET_DIRECT_CALL_I32 &&
        kind != BODY_FRAGMENT_ASSIGN_DIRECT_CALL_I32 &&
        kind != BODY_FRAGMENT_ASSIGN_COMPOUND_DIRECT_CALL_I32 &&
        kind != BODY_FRAGMENT_DIRECT_CALL_VOID)
    {
        return;
    }

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
