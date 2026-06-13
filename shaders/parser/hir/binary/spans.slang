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
    uint node = linear_thread_id(dtid);
    if (node >= gHirExpr.n)
        return;

    hir_binary_span_link_a[node] = INVALID;
    hir_binary_span_start_a[node] = valid_node(node) ? hir_token_pos[node] : INVALID;

    if (!valid_node(node) || hir_kind[node] != HIR_BINARY_EXPR)
        return;
    if (!binary_form(expr_record(node, HIR_EXPR_RECORD_FORM)))
        return;

    uint left = expr_record(node, HIR_EXPR_RECORD_LEFT);
    if (!valid_node(left))
        return;

    hir_binary_span_link_a[node] = left;
}
