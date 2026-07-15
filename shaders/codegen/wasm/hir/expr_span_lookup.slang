// Shared lookup over GPU-computed expression postorder byte spans.
//
// Target scatter shaders keep ownership of node-local opcode selection because
// their supported atom surfaces differ. This module centralizes root sizing
// and the binary search that maps an output byte to its contributing node.

StructuredBuffer<uint> hir_expr_forest_root_node;
StructuredBuffer<uint> expr_order;
StructuredBuffer<uint2> expr_root_order_range;
StructuredBuffer<uint2> expr_node_span;

static const uint EXPR_SPAN_INVALID = 0xffffffffu;

bool expr_span_valid_node(uint node, uint n_hir_nodes)
{
    return node != EXPR_SPAN_INVALID && node < n_hir_nodes;
}

public uint wasm_expr_span_len(uint resolved_root, uint n_hir_nodes)
{
    if (!expr_span_valid_node(resolved_root, n_hir_nodes))
        return 0u;
    uint forest_root = hir_expr_forest_root_node[resolved_root];
    if (!expr_span_valid_node(forest_root, n_hir_nodes))
        return 0u;
    uint2 range = expr_root_order_range[forest_root];
    if (range.x >= range.y || range.y > n_hir_nodes)
        return 0u;
    uint last_node = expr_order[range.y - 1u];
    uint2 last_span = expr_node_span[last_node];
    return last_span.x + last_span.y;
}

public bool wasm_expr_node_span(
    uint node,
    uint n_hir_nodes,
    out uint span_start,
    out uint span_len)
{
    span_start = 0u;
    span_len = 0u;
    if (!expr_span_valid_node(node, n_hir_nodes))
        return false;
    uint2 span = expr_node_span[node];
    span_start = span.x;
    span_len = span.y;
    return true;
}

public bool wasm_expr_span_byte_owner(
    uint resolved_root,
    uint n_hir_nodes,
    uint byte_i,
    out uint owner_node,
    out uint owner_byte_i)
{
    owner_node = EXPR_SPAN_INVALID;
    owner_byte_i = 0u;
    if (!expr_span_valid_node(resolved_root, n_hir_nodes))
        return false;
    uint forest_root = hir_expr_forest_root_node[resolved_root];
    if (!expr_span_valid_node(forest_root, n_hir_nodes))
        return false;
    uint2 range = expr_root_order_range[forest_root];
    uint lo = range.x;
    uint hi = range.y;
    for (uint guard = 0u; guard < 32u && lo < hi; guard += 1u)
    {
        uint mid = lo + ((hi - lo) >> 1u);
        uint node = expr_order[mid];
        uint2 span = expr_node_span[node];
        if (span.x + span.y <= byte_i)
            lo = mid + 1u;
        else
            hi = mid;
    }
    if (lo >= range.y)
        return false;
    uint node = expr_order[lo];
    uint2 span = expr_node_span[node];
    if (span.y == 0u || byte_i < span.x || byte_i >= span.x + span.y)
        return false;
    owner_node = node;
    owner_byte_i = byte_i - span.x;
    return true;
}
