// Publish one byte-count/error contribution per root-sorted expression row.

import body_common;
import expr_tree_metadata_raw_common;
import expr_emission_common;

StructuredBuffer<uint> hir_expr_forest_root_node;
StructuredBuffer<uint> hir_expr_parent_node;
StructuredBuffer<uint> expr_order;
RWStructuredBuffer<uint4> expr_contribution;
RWStructuredBuffer<uint2> expr_node_emission;

static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint order_i = dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE;
    if (order_i >= gParams.n_hir_nodes)
        return;
    uint node = expr_order[order_i];
    uint root = hir_expr_forest_root_node[node];
    if (!valid_node(root))
    {
        expr_contribution[order_i] = uint4(0u, 0u, 0u, 0u);
        expr_node_emission[node] = wasm_expr_no_emission();
        return;
    }
    uint len = 0u;
    uint2 emission = wasm_expr_no_emission();
    uint parent_node = hir_expr_parent_node[node];
    bool aggregate_address_context = valid_node(parent_node) &&
        (hir_kind[parent_node] == HIR_MEMBER_EXPR ||
         hir_kind[parent_node] == HIR_CALL_EXPR);
    bool supported = raw_wasm_expr_node_contribution(
        node,
        aggregate_address_context,
        len,
        emission);
    // Non-expression rows share the sorted domain but do not invalidate it.
    uint form = expr_form(node);
    bool expression_row = hir_kind[node] == HIR_CALL_EXPR ||
                          hir_kind[node] == HIR_INDEX_EXPR ||
                          hir_kind[node] == HIR_MEMBER_EXPR ||
                          (hir_kind[node] == HIR_EXPR &&
                           form != HIR_EXPR_FORWARD && form != HIR_EXPR_NONE);
    uint generic_atom_len = 0u;
    bool projected_member = hir_kind[node] == HIR_MEMBER_EXPR &&
                            valid_token(hir_member_name_token[node]) &&
                            member_result_field_index[hir_member_name_token[node]] != INVALID;
    bool generic_compatible = !expression_row ||
                              projected_member ||
                              (hir_kind[node] == HIR_INDEX_EXPR && supported) ||
                              expr_non_call_atom_and_len(node, generic_atom_len) ||
                              form == HIR_EXPR_NOT ||
                              form == HIR_EXPR_NEG ||
                              (expr_binary_op_supported(form) &&
                               expr_binary_op_byte(form) != 0u);
    expr_contribution[order_i] = uint4(
        len,
        expression_row && !supported ? 1u : 0u,
        generic_compatible ? 0u : 1u,
        hir_kind[node] == HIR_MEMBER_EXPR &&
                valid_token(hir_member_name_token[node])
            ? 1u
            : 0u);
    expr_node_emission[node] = emission;
}
