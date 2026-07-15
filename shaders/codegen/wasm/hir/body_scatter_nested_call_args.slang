// Scatter every scalar ABI argument from the shared expression postorder.
// Each output byte performs O(log n) owner lookup; no lane walks an argument's
// expression depth. Strings and aggregate addresses remain in the narrow
// non-scalar scatter.

import gpu_index;
import body_common;
import expr_span_lookup;
import expr_emission_common;

struct ScanParams
{
    uint n_items;
    uint n_blocks;
    uint scan_step;
    uint out_capacity;
};

ConstantBuffer<ScanParams> gBodyScan;
ConstantBuffer<ScanParams> gArgScan;

StructuredBuffer<uint> status;
StructuredBuffer<uint4> body_fragment_meta;
StructuredBuffer<uint> body_scan_local_prefix;
StructuredBuffer<uint> body_scan_block_prefix;
StructuredBuffer<uint> wasm_agg_call_arg_count_by_fragment;
StructuredBuffer<uint> wasm_agg_call_arg_count_local_prefix;
StructuredBuffer<uint> wasm_agg_call_arg_count_block_prefix;
StructuredBuffer<uint> wasm_agg_call_arg_len;
StructuredBuffer<uint4> wasm_agg_call_arg_meta;
StructuredBuffer<uint4> wasm_agg_call_arg_aux;
StructuredBuffer<uint> wasm_agg_call_arg_byte_local_prefix;
StructuredBuffer<uint> wasm_agg_call_arg_byte_block_prefix;
StructuredBuffer<uint2> expr_node_emission;

RWStructuredBuffer<uint> body_words;

static const uint ARG_WG_SIZE = 256u;
static const uint WASM_F32_CONVERT_I32_S = 0xb2u;

uint arg_count_prefix_for_fragment(uint fragment_i)
{
    return wasm_global_exclusive_prefix(
        fragment_i,
        ARG_WG_SIZE,
        wasm_agg_call_arg_count_local_prefix,
        wasm_agg_call_arg_count_block_prefix);
}

uint arg_byte_prefix_for_record(uint record_i)
{
    return wasm_global_exclusive_prefix(
        record_i,
        ARG_WG_SIZE,
        wasm_agg_call_arg_byte_local_prefix,
        wasm_agg_call_arg_byte_block_prefix);
}

uint body_prefix_for_fragment(uint fragment_i)
{
    return wasm_global_exclusive_prefix(
        fragment_i,
        ARG_WG_SIZE,
        body_scan_local_prefix,
        body_scan_block_prefix);
}

uint arg_byte_base_for_fragment(uint4 fragment_meta)
{
    if (fragment_meta.x == BODY_FRAGMENT_RETURN_BINARY_DIRECT_CALL_I32 &&
        (fragment_meta.w >> 8u) != 0u)
    {
        uint side = resolve_expr_node(fragment_meta.z);
        uint2 total = valid_node(side) ? expr_subtree_total[side] : uint2(0u, 1u);
        return total.y == 0u ? total.x : 0u;
    }
    if (fragment_meta.x == BODY_FRAGMENT_ASSIGN_COMPOUND_DIRECT_CALL_I32)
        return local_get_len(fragment_meta.y);
    return 0u;
}

bool record_for_arg_global_byte(uint arg_global_byte, out uint record_i)
{
    record_i = INVALID;
    uint lo = 0u;
    uint hi = gArgScan.n_items;
    for (uint guard = 0u; guard < 32u && lo < hi; guard += 1u)
    {
        uint mid = lo + ((hi - lo) >> 1u);
        uint start = arg_byte_prefix_for_record(mid);
        uint end = start + wasm_agg_call_arg_len[mid];
        if (end <= arg_global_byte)
            lo = mid + 1u;
        else
            hi = mid;
    }
    if (lo >= gArgScan.n_items)
        return false;

    uint start = arg_byte_prefix_for_record(lo);
    uint len = wasm_agg_call_arg_len[lo];
    if (arg_global_byte < start || arg_global_byte >= start + len)
        return false;
    record_i = lo;
    return true;
}

uint body_byte_for_arg_byte(uint record_i, uint arg_global_byte)
{
    uint fragment_i = wasm_agg_call_arg_meta[record_i].x;
    if (fragment_i == INVALID)
        return INVALID;

    uint first_record = arg_count_prefix_for_fragment(fragment_i);
    uint fragment_arg_start = arg_byte_prefix_for_record(first_record);
    return body_prefix_for_fragment(fragment_i) +
           arg_byte_base_for_fragment(body_fragment_meta[fragment_i]) +
           (arg_global_byte - fragment_arg_start);
}

uint call_atom_contribution_byte(uint node, uint byte_i)
{
    node = resolve_expr_node(node);
    if (!valid_node(node))
        return 0u;

    uint form = expr_form(node);
    uint local_index = INVALID;
    if (form == HIR_EXPR_NAME && local_decl_token_for_name_expr(node, local_index))
        return local_get_byte(local_index, byte_i);

    uint value = 0u;
    if (form == HIR_EXPR_INT ||
        form == HIR_EXPR_TRUE ||
        form == HIR_EXPR_FALSE ||
        (form == HIR_EXPR_NAME && name_const_record_value(node, value)))
    {
        if (form == HIR_EXPR_INT)
            value = hir_expr_int_value[node];
        else if (form == HIR_EXPR_TRUE || form == HIR_EXPR_FALSE)
            value = form == HIR_EXPR_TRUE ? 1u : 0u;
        return i32_const_byte(value, byte_i);
    }
    if (form == HIR_EXPR_FLOAT)
        return f32_const_byte(hir_expr_float_bits[node], byte_i);
    return 0u;
}

uint call_expression_contribution_byte(uint node, uint byte_i)
{
    uint emission_byte = 0u;
    if (wasm_expr_emission_byte(expr_node_emission[node], byte_i, emission_byte))
        return emission_byte;

    uint atom_len = 0u;
    if (expr_non_call_atom_and_len(node, atom_len))
        return call_atom_contribution_byte(node, byte_i);
    if (string_value_expr_and_len(node, atom_len))
        return string_value_expr_byte(node, byte_i);

    uint form = expr_form(node);
    if (form == HIR_EXPR_NOT)
        return byte_i == 0u ? WASM_I32_EQZ : 0u;
    if (form == HIR_EXPR_NEG)
    {
        if (expr_neg_is_f32(node))
            return byte_i == 0u ? WASM_F32_NEG : 0u;
        if (byte_i < 2u)
            return i32_const_byte(0xffffffffu, byte_i);
        return byte_i == 2u ? WASM_I32_MUL : 0u;
    }
    return byte_i == 0u ? expr_binary_op_byte_for_node(node) : 0u;
}

uint scalar_arg_tree_byte(uint root_node, uint byte_i)
{
    uint2 total = expr_subtree_total[root_node];
    uint root_span_start = 0u;
    uint root_span_len = 0u;
    if (!wasm_expr_node_span(
            root_node,
            gParams.n_hir_nodes,
            root_span_start,
            root_span_len))
    {
        return 0u;
    }
    uint subtree_end = root_span_start + root_span_len;
    if (total.y != 0u || total.x == 0u || subtree_end < total.x || byte_i >= total.x)
        return 0u;

    uint owner = INVALID;
    uint owner_byte = 0u;
    uint forest_byte = subtree_end - total.x + byte_i;
    if (!wasm_expr_span_byte_owner(
            root_node,
            gParams.n_hir_nodes,
            forest_byte,
            owner,
            owner_byte))
    {
        return 0u;
    }
    return call_expression_contribution_byte(owner, owner_byte);
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    uint arg_global_byte = linear_dispatch_thread_id_2d(tid, DISPATCH_X_STRIDE);
    if (arg_global_byte >= gArgScan.out_capacity || status[2u] != 0u)
        return;

    uint record_i = INVALID;
    if (!record_for_arg_global_byte(arg_global_byte, record_i))
        return;

    uint4 arg_meta = wasm_agg_call_arg_meta[record_i];
    uint4 arg_aux = wasm_agg_call_arg_aux[record_i];
    uint root_node = resolve_expr_node(arg_meta.z);
    if (!valid_node(root_node) || arg_aux.y == TY_STRING)
    {
        return;
    }

    uint body_byte_i = body_byte_for_arg_byte(record_i, arg_global_byte);
    if (body_byte_i == INVALID || body_byte_i >= gBodyScan.out_capacity)
        return;

    uint record_start = arg_byte_prefix_for_record(record_i);
    body_words[body_byte_i] =
        scalar_arg_tree_byte(root_node, arg_global_byte - record_start);
}
