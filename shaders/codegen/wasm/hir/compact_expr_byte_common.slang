// Shared dense-HIR expression byte lookup for all migrated fragment scatters.

import compact_expr_common;
import expr_emission_common;
import compact_expr_span_lookup;

StructuredBuffer<uint2> expr_node_emission;

public uint compact_expr_node_contribution_byte(uint node, uint byte_i)
{
    if (!valid_node(node)) return 0u;
    uint emission_byte = 0u;
    if (wasm_expr_emission_byte(expr_node_emission[node], byte_i, emission_byte))
        return emission_byte;
    uint atom_len = 0u;
    if (expr_non_call_atom_and_len(node, atom_len))
        return byte_i < atom_len ? expr_non_call_atom_byte(node, byte_i) : 0u;
    if (string_value_expr_and_len(node, atom_len))
        return byte_i < atom_len ? string_value_expr_byte(node, byte_i) : 0u;
    uint form = expr_form(node);
    if (form == HIR_EXPR_NOT)
        return byte_i == 0u ? 0x45u : 0u;
    if (form == HIR_EXPR_NEG)
    {
        if (expr_neg_is_f32(node)) return byte_i == 0u ? WASM_F32_NEG : 0u;
        if (byte_i == 0u) return WASM_I32_CONST;
        if (byte_i == 1u) return 0x7fu;
        return byte_i == 2u ? WASM_I32_MUL : 0u;
    }
    return byte_i == 0u ? expr_binary_op_byte_for_node(node) : 0u;
}

public uint compact_expr_tree_len(uint root)
{
    if (!valid_node(root)) return 0u;
    uint2 total = expr_subtree_total[root];
    uint2 features = expr_subtree_features[root];
    return total.y == 0u && features.x == 0u ? total.x : 0u;
}

public uint compact_expr_tree_byte(uint root, uint byte_i)
{
    if (!valid_node(root)) return 0u;
    uint2 total = expr_subtree_total[root];
    uint2 features = expr_subtree_features[root];
    if (total.y != 0u || features.x != 0u || byte_i >= total.x) return 0u;
    uint span_start = 0u;
    uint span_len = 0u;
    if (!compact_expr_node_span(
            root,
            active_hir_node_count(),
            span_start,
            span_len))
        return 0u;
    uint subtree_end = span_start + span_len;
    if (subtree_end < total.x) return 0u;
    uint owner = INVALID;
    uint owner_byte = 0u;
    if (!compact_expr_span_byte_owner(
            root,
            active_hir_node_count(),
            subtree_end - total.x + byte_i,
            owner,
            owner_byte))
        return 0u;
    return compact_expr_node_contribution_byte(owner, owner_byte);
}
