// Migration counterpart to expr_contribution. This is compiled against only
// dense HIR identities until fragment producers and consumers move atomically.

import compact_expr_common;
import expr_tree_metadata_common;
import expr_emission_common;

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
    if (!valid_node(node))
    {
        expr_contribution[order_i] = uint4(0u, 0u, 0u, 0u);
        return;
    }
    uint root = compact_expr_root[node];
    if (!valid_node(root))
    {
        expr_contribution[order_i] = uint4(0u, 0u, 0u, 0u);
        expr_node_emission[node] = wasm_expr_no_emission();
        return;
    }
    uint len = 0u;
    uint2 emission = wasm_expr_no_emission();
    uint parent_node = compact_expr_parent[node];
    uint parent_kind = valid_node(parent_node)
        ? compact_hir_core[parent_node].kind
        : INVALID;
    bool aggregate_address_context = valid_node(parent_node) &&
        (parent_kind == HIR_MEMBER_EXPR ||
         parent_kind == HIR_INDEX_EXPR ||
         parent_kind == HIR_CALL_EXPR ||
         expr_form(parent_node) == HIR_EXPR_INDEX_FORM);
    bool supported = wasm_expr_node_contribution(
        node,
        aggregate_address_context,
        len,
        emission);
    uint form = expr_form(node);
    uint kind = compact_hir_core[node].kind;
    bool expression_row = kind == HIR_CALL_EXPR ||
                          kind == HIR_INDEX_EXPR ||
                          kind == HIR_MEMBER_EXPR ||
                          (kind == HIR_EXPR &&
                           form != HIR_EXPR_FORWARD && form != HIR_EXPR_NONE);
    // The compact forest already owns call arguments, method receivers, and
    // call nodes in postorder. A supported node contribution is therefore the
    // complete compatibility contract; no statement-shape classifier is
    // needed for call-bearing trees.
    bool generic_compatible = !expression_row || supported;
    expr_contribution[order_i] = uint4(
        len,
        expression_row && !supported ? 1u : 0u,
        generic_compatible ? 0u : 1u,
        kind == HIR_MEMBER_EXPR && valid_token(compact_hir_payload[node].c) ? 1u : 0u);
    expr_node_emission[node] = emission;
}
