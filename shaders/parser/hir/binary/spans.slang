// Initialize parser-owned binary expression span links.
//
// Binary tail grammar rows start at the operator token. The HIR expression row
// represents the whole `left op right` expression. This pass seeds a left-edge
// relation that later pointer-jump steps resolve without in-shader chain walks.

struct Params
{
    uint n;
    uint uses_status_count;
};

ConstantBuffer<Params> gHirExpr;

StructuredBuffer<uint> tree_count_status;
StructuredBuffer<uint> hir_semantic_count;
StructuredBuffer<uint> hir_semantic_dense_node;
StructuredBuffer<uint> hir_node_dense_id;
StructuredBuffer<uint> hir_kind;
StructuredBuffer<uint> hir_expr_record;
StructuredBuffer<uint> hir_token_pos;

RWStructuredBuffer<uint> hir_binary_span_link_a;
RWStructuredBuffer<uint> hir_binary_span_start_a;

static const uint INVALID = 0xffffffffu;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

static const uint HIR_BINARY_EXPR = 16u;

static const uint HIR_EXPR_NONE = 0u;
static const uint HIR_EXPR_EQ = 7u;
static const uint HIR_EXPR_SHR = 25u;

static const uint HIR_EXPR_RECORD_STRIDE = 4u;
static const uint HIR_EXPR_RECORD_FORM = 0u;
static const uint HIR_EXPR_RECORD_LEFT = 1u;
// Compress a small, bounded portion of each binary-expression chain locally
// before the global pointer-jump passes. Work remains O(n) per round and no
// lane traverses an unbounded expression.
static const uint LOCAL_LINK_SPAN = 32u;

uint linear_thread_id(uint3 dtid)
{
    return dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE;
}

uint active_node_count()
{
    return gHirExpr.uses_status_count != 0u ? min(gHirExpr.n, tree_count_status[5u]) : gHirExpr.n;
}

bool valid_node(uint node)
{
    return node != INVALID && node < active_node_count();
}

uint active_semantic_count()
{
    return min(hir_semantic_count[0u], gHirExpr.n);
}

bool valid_semantic_row(uint row)
{
    return row != INVALID && row < active_semantic_count();
}

uint expr_record(uint node, uint field)
{
    return hir_expr_record[node * HIR_EXPR_RECORD_STRIDE + field];
}

bool binary_form(uint form)
{
    return form >= HIR_EXPR_EQ && form <= HIR_EXPR_SHR;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint row = linear_thread_id(dtid);
    if (row >= active_semantic_count())
        return;

    uint node = hir_semantic_dense_node[row];

    hir_binary_span_link_a[row] = INVALID;
    hir_binary_span_start_a[row] = valid_node(node) ? hir_token_pos[node] : INVALID;

    if (!valid_node(node) || hir_kind[node] != HIR_BINARY_EXPR)
        return;
    if (!binary_form(expr_record(node, HIR_EXPR_RECORD_FORM)))
        return;

    uint raw_link = expr_record(node, HIR_EXPR_RECORD_LEFT);
    uint start = hir_binary_span_start_a[row];
    for (uint hop = 0u; hop < LOCAL_LINK_SPAN && valid_node(raw_link) && raw_link != node; ++hop)
    {
        uint linked_start = hir_token_pos[raw_link];
        if (linked_start != INVALID && (start == INVALID || linked_start < start))
            start = linked_start;

        uint next = INVALID;
        if (hir_kind[raw_link] == HIR_BINARY_EXPR)
        {
            uint linked_form = expr_record(raw_link, HIR_EXPR_RECORD_FORM);
            if (binary_form(linked_form))
                next = expr_record(raw_link, HIR_EXPR_RECORD_LEFT);
        }
        raw_link = next == node ? INVALID : next;
    }

    uint dense_link = valid_node(raw_link) ? hir_node_dense_id[raw_link] : INVALID;
    hir_binary_span_link_a[row] = valid_semantic_row(dense_link) && dense_link != row
        ? dense_link
        : INVALID;
    hir_binary_span_start_a[row] = start;
}
