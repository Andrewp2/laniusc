// Scatter scalar return-expression fragments into the WASM body byte stream.

import body_arg_byte_common;
import prefix_scan;

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

static const uint BODY_FRAGMENT_RETURN_EXPR_I32 = 13u;
static const uint WASM_RETURN = 0x0fu;
static const uint MAX_RETURN_EXPR_EMIT_STACK = 16u;
static const uint MAX_RETURN_EXPR_EMIT_STEPS = 48u;
static const uint WG_SIZE = 256u;

uint body_prefix_for_token(uint token_i)
{
    return global_exclusive_prefix(
        token_i,
        WG_SIZE,
        body_scan_local_prefix,
        body_scan_block_prefix);
}

uint return_expr_len(uint root_node)
{
    root_node = resolve_expr_node(root_node);
    if (!valid_node(root_node))
        return 0u;

    uint nodes[MAX_RETURN_EXPR_EMIT_STACK];
    uint states[MAX_RETURN_EXPR_EMIT_STACK];
    uint lens[MAX_RETURN_EXPR_EMIT_STACK];
    uint sp = 1u;
    uint lsp = 0u;
    nodes[0u] = root_node;
    states[0u] = 0u;

    for (uint step = 0u; step < MAX_RETURN_EXPR_EMIT_STEPS; step += 1u)
    {
        if (sp == 0u)
            break;

        uint node = nodes[sp - 1u];
        if (!valid_node(node))
            return 0u;

        uint atom_len = 0u;
        uint state = states[sp - 1u];
        if (state == 0u && expr_non_call_atom_and_len(node, atom_len))
        {
            if (lsp >= MAX_RETURN_EXPR_EMIT_STACK)
                return 0u;
            lens[lsp] = atom_len;
            lsp += 1u;
            sp -= 1u;
            continue;
        }

        node = resolve_expr_node(node);
        if (!valid_node(node))
            return 0u;
        nodes[sp - 1u] = node;

        uint form = expr_form(node);
        if (form == HIR_EXPR_NOT || form == HIR_EXPR_NEG)
        {
            if (state == 0u)
            {
                if (sp >= MAX_RETURN_EXPR_EMIT_STACK)
                    return 0u;
                states[sp - 1u] = 1u;
                nodes[sp] = expr_record_slot(node, EXPR_RECORD_LEFT);
                states[sp] = 0u;
                sp += 1u;
                continue;
            }
            if (lsp < 1u)
                return 0u;
            lens[lsp - 1u] += form == HIR_EXPR_NOT ? 1u : (expr_neg_is_f32(node) ? 1u : 3u);
            sp -= 1u;
            continue;
        }

        if (expr_binary_op_byte_for_node(node) == 0u)
            return 0u;
        if (state == 0u)
        {
            if (sp >= MAX_RETURN_EXPR_EMIT_STACK)
                return 0u;
            states[sp - 1u] = 1u;
            nodes[sp] = expr_record_slot(node, EXPR_RECORD_LEFT);
            states[sp] = 0u;
            sp += 1u;
            continue;
        }
        if (state == 1u)
        {
            if (sp >= MAX_RETURN_EXPR_EMIT_STACK)
                return 0u;
            states[sp - 1u] = 2u;
            nodes[sp] = expr_record_slot(node, EXPR_RECORD_RIGHT);
            states[sp] = 0u;
            sp += 1u;
            continue;
        }
        if (lsp < 2u)
            return 0u;
        uint right_len = lens[lsp - 1u];
        uint left_len = lens[lsp - 2u];
        lsp -= 1u;
        lens[lsp - 1u] = left_len + right_len + 1u;
        sp -= 1u;
    }

    return sp == 0u && lsp == 1u ? lens[0u] : 0u;
}

uint return_expr_byte(uint node, uint byte_i)
{
    for (uint step = 0u; step < MAX_RETURN_EXPR_EMIT_STEPS; step += 1u)
    {
        if (!valid_node(node))
            return 0u;

        uint atom_len = 0u;
        if (expr_non_call_atom_and_len(node, atom_len))
            return expr_non_call_atom_byte(node, byte_i);

        node = resolve_expr_node(node);
        if (!valid_node(node))
            return 0u;

        uint form = expr_form(node);
        if (form == HIR_EXPR_NOT)
        {
            uint inner = expr_record_slot(node, EXPR_RECORD_LEFT);
            uint inner_len = return_expr_len(inner);
            if (byte_i < inner_len)
            {
                node = inner;
                continue;
            }
            return byte_i == inner_len ? WASM_I32_EQZ : 0u;
        }
        if (form == HIR_EXPR_NEG)
        {
            uint inner = expr_record_slot(node, EXPR_RECORD_LEFT);
            uint inner_len = return_expr_len(inner);
            if (expr_neg_is_f32(node))
            {
                if (byte_i < inner_len)
                {
                    node = inner;
                    continue;
                }
                return byte_i == inner_len ? WASM_F32_NEG : 0u;
            }
            if (byte_i < 2u)
                return i32_const_byte(0u, byte_i);
            if (byte_i < 2u + inner_len)
            {
                node = inner;
                byte_i -= 2u;
                continue;
            }
            return byte_i == 2u + inner_len ? WASM_I32_SUB : 0u;
        }

        uint left = expr_record_slot(node, EXPR_RECORD_LEFT);
        uint right = expr_record_slot(node, EXPR_RECORD_RIGHT);
        uint left_len = return_expr_len(left);
        uint right_len = return_expr_len(right);
        if (byte_i < left_len)
        {
            node = left;
            continue;
        }
        if (byte_i < left_len + right_len)
        {
            node = right;
            byte_i -= left_len;
            continue;
        }
        return byte_i == left_len + right_len ? expr_binary_op_byte_for_node(node) : 0u;
    }
    return 0u;
}

uint return_expr_fragment_byte(uint expr_node, uint byte_i)
{
    uint expr_len = return_expr_len(expr_node);
    if (byte_i < expr_len)
        return return_expr_byte(expr_node, byte_i);
    return WASM_RETURN;
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
    if (meta.x != BODY_FRAGMENT_RETURN_EXPR_I32)
        return;

    uint byte_i = body_byte_i - offset;
    body_words[offset + byte_i] = return_expr_fragment_byte(meta.y, byte_i);
}
