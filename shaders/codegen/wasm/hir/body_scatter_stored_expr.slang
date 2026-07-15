// Scatter complex array-element and aggregate-field expression stores.
// Expression bytes come from the GPU-computed postorder forest; each output
// lane finds its owning expression node independently.

import body_arg_byte_common;
import prefix_scan;
import expr_span_lookup;
import expr_emission_common;

struct ScanParams
{
    uint n_items;
    uint n_blocks;
    uint scan_step;
    uint out_capacity;
};

ConstantBuffer<ScanParams> gScan;

StructuredBuffer<uint> status;
StructuredBuffer<uint> body_fragment_len;
StructuredBuffer<uint4> body_fragment_meta;
StructuredBuffer<uint> body_scan_local_prefix;
StructuredBuffer<uint> body_scan_block_prefix;

RWStructuredBuffer<uint> body_words;

static const uint BODY_FRAGMENT_ARRAY_STORE_I32 = 31u;
static const uint BODY_FRAGMENT_AGG_FIELD_STORE_I32 = 40u;
static const uint WASM_I32_STORE = 0x36u;
static const uint WASM_F32_STORE = 0x38u;
static const uint WG_SIZE = 256u;

uint body_prefix_for_token(uint token_i)
{
    return global_exclusive_prefix(
        token_i,
        WG_SIZE,
        body_scan_local_prefix,
        body_scan_block_prefix);
}

uint stored_expr_len(uint root_node)
{
    root_node = resolve_expr_node(root_node);
    if (!valid_node(root_node))
        return 0u;
    uint2 total = expr_subtree_total[root_node];
    return total.y == 0u ? total.x : 0u;
}

uint stored_expr_node_contribution_byte(uint node, uint byte_i)
{
    node = resolve_expr_node(node);
    if (!valid_node(node))
        return 0u;

    uint emission_byte = 0u;
    if (wasm_expr_emission_byte(expr_node_emission[node], byte_i, emission_byte))
        return emission_byte;

    uint atom_len = 0u;
    if (expr_non_call_atom_and_len(node, atom_len))
        return byte_i < atom_len ? expr_non_call_atom_byte(node, byte_i) : 0u;

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

uint stored_expr_byte(uint root_node, uint byte_i)
{
    root_node = resolve_expr_node(root_node);
    if (!valid_node(root_node))
        return 0u;

    uint2 total = expr_subtree_total[root_node];
    uint span_start = 0u;
    uint span_len = 0u;
    if (total.y != 0u || total.x == 0u || byte_i >= total.x ||
        !wasm_expr_node_span(root_node, gParams.n_hir_nodes, span_start, span_len))
    {
        return 0u;
    }

    uint subtree_end = span_start + span_len;
    if (subtree_end < total.x)
        return 0u;

    uint owner_node = INVALID;
    uint owner_byte_i = 0u;
    if (!wasm_expr_span_byte_owner(
            root_node,
            gParams.n_hir_nodes,
            subtree_end - total.x + byte_i,
            owner_node,
            owner_byte_i))
    {
        return 0u;
    }
    return stored_expr_node_contribution_byte(owner_node, owner_byte_i);
}

uint store_memarg_byte(uint op, uint byte_i)
{
    if (byte_i == 0u)
        return op;
    if (byte_i == 1u)
        return 2u;
    return 0u;
}

bool stored_expr_fragment(uint4 meta)
{
    return meta.x == BODY_FRAGMENT_ARRAY_STORE_I32 ||
           meta.x == BODY_FRAGMENT_AGG_FIELD_STORE_I32;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    uint body_byte_i = linear_dispatch_id(tid);
    if (body_byte_i >= gScan.out_capacity || status[2u] != 0u)
        return;

    uint lo = 0u;
    uint hi = gScan.n_items;
    for (uint guard = 0u; guard < 32u; guard += 1u)
    {
        if (lo >= hi)
            break;
        uint mid = lo + ((hi - lo) >> 1u);
        uint mid_start = body_prefix_for_token(mid);
        uint mid_end = mid_start + body_fragment_len[mid];
        if (mid_end <= body_byte_i)
            lo = mid + 1u;
        else
            hi = mid;
    }

    uint token_i = lo;
    if (token_i >= gScan.n_items)
        return;

    uint len = body_fragment_len[token_i];
    uint offset = body_prefix_for_token(token_i);
    if (body_byte_i < offset || body_byte_i >= offset + len)
        return;

    uint4 meta = body_fragment_meta[token_i];
    if (!stored_expr_fragment(meta))
        return;

    uint byte_i = body_byte_i - offset;
    uint address_len = 1u + i32_sleb_len(meta.y);
    uint expr_len = stored_expr_len(meta.z);
    if (expr_len == 0u || address_len + expr_len + 3u != len)
        return;

    if (byte_i < address_len)
    {
        body_words[offset + byte_i] = i32_const_byte(meta.y, byte_i);
        return;
    }
    if (byte_i < address_len + expr_len)
    {
        body_words[offset + byte_i] =
            stored_expr_byte(meta.z, byte_i - address_len);
        return;
    }

    uint store_op = expr_operand_result_is_f32(meta.z)
                        ? WASM_F32_STORE
                        : WASM_I32_STORE;
    body_words[offset + byte_i] =
        store_memarg_byte(store_op, byte_i - address_len - expr_len);
}
