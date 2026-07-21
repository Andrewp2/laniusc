// Dense-HIR lookup over GPU-computed expression postorder byte spans.

StructuredBuffer<uint> compact_expr_root;
StructuredBuffer<uint> expr_order;
StructuredBuffer<uint2> expr_root_order_range;
StructuredBuffer<uint2> expr_node_span;

static const uint EXPR_SPAN_INVALID = 0xffffffffu;

bool compact_expr_span_valid_node(uint node, uint hir_count)
{
    return node != EXPR_SPAN_INVALID && node < hir_count;
}

public bool compact_expr_node_span(
    uint node,
    uint hir_count,
    out uint span_start,
    out uint span_len)
{
    span_start = 0u;
    span_len = 0u;
    if (!compact_expr_span_valid_node(node, hir_count)) return false;
    uint2 span = expr_node_span[node];
    span_start = span.x;
    span_len = span.y;
    return true;
}

public bool compact_expr_span_byte_owner(
    uint resolved_root,
    uint hir_count,
    uint byte_i,
    out uint owner_node,
    out uint owner_byte_i)
{
    owner_node = EXPR_SPAN_INVALID;
    owner_byte_i = 0u;
    if (!compact_expr_span_valid_node(resolved_root, hir_count)) return false;
    uint forest_root = compact_expr_root[resolved_root];
    if (!compact_expr_span_valid_node(forest_root, hir_count)) return false;
    uint2 range = expr_root_order_range[forest_root];
    uint lo = range.x;
    uint hi = range.y;
    for (uint guard = 0u; guard < 32u && lo < hi; guard += 1u)
    {
        uint mid = lo + ((hi - lo) >> 1u);
        uint node = expr_order[mid];
        uint2 span = expr_node_span[node];
        if (span.x + span.y <= byte_i) lo = mid + 1u;
        else hi = mid;
    }
    if (lo >= range.y) return false;
    uint node = expr_order[lo];
    uint2 span = expr_node_span[node];
    if (span.y == 0u || byte_i < span.x || byte_i >= span.x + span.y)
        return false;
    owner_node = node;
    owner_byte_i = byte_i - span.x;
    return true;
}
