// Normalize parser-owned index expression spans after expression edges are known.
//
// The grammar row for a postfix index starts at `[`. The HIR expression row
// represents `base[index]`: it must include the base but not any later postfix
// tail such as `(...)` in `base[index](...)`.

struct Params
{
    uint n;
    uint uses_status_count;
};

ConstantBuffer<Params> gHirExpr;

StructuredBuffer<uint> tree_count_status;
StructuredBuffer<uint> hir_kind;
StructuredBuffer<uint> hir_semantic_dense_node;
StructuredBuffer<uint> hir_semantic_count;
StructuredBuffer<uint> hir_expr_record;

RWStructuredBuffer<uint> hir_token_pos;
RWStructuredBuffer<uint> hir_token_end;

static const uint INVALID = 0xffffffffu;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

static const uint HIR_INDEX_EXPR = 20u;
static const uint HIR_EXPR_INDEX = 26u;

static const uint HIR_EXPR_RECORD_STRIDE = 4u;
static const uint HIR_EXPR_RECORD_FORM = 0u;
static const uint HIR_EXPR_RECORD_LEFT = 1u;
static const uint HIR_EXPR_RECORD_RIGHT = 2u;

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
    return min(hir_semantic_count[0u], active_node_count());
}

uint semantic_row_node(uint row)
{
    if (row >= active_semantic_count())
        return INVALID;
    uint node = hir_semantic_dense_node[row];
    return valid_node(node) ? node : INVALID;
}

uint expr_record(uint node, uint field)
{
    return hir_expr_record[node * HIR_EXPR_RECORD_STRIDE + field];
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint row = linear_thread_id(dtid);
    uint node = semantic_row_node(row);
    if (node == INVALID || hir_kind[node] != HIR_INDEX_EXPR)
        return;
    if (expr_record(node, HIR_EXPR_RECORD_FORM) != HIR_EXPR_INDEX)
        return;

    uint base = expr_record(node, HIR_EXPR_RECORD_LEFT);
    if (!valid_node(base))
        return;

    uint base_start = hir_token_pos[base];
    uint index_start = hir_token_pos[node];
    if (base_start != INVALID &&
        (index_start == INVALID || base_start < index_start))
        hir_token_pos[node] = base_start;

    uint index_expr = expr_record(node, HIR_EXPR_RECORD_RIGHT);
    if (!valid_node(index_expr))
        return;

    uint index_expr_end = hir_token_end[index_expr];
    if (index_expr_end != INVALID)
        hir_token_end[node] = index_expr_end + 1u;
}
