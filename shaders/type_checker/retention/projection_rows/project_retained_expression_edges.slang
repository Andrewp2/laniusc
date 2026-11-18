// Projection step 4b: one lane per global row. Publishes the expression
// parent of each operand the row owns, by the rules of the frontend's
// expression forest (parser/hir/canonical/build_expr_forest_edges.slang): unary
// and binary operands, a member's or try's base, an assignment's
// destination, a for statement's iterable, a call's callee and arguments
// and a struct literal's field values. An operand owned twice is an error.
import type_checker.retention.projection.retained_projection_workspace;

static const uint EXPR_NOT = 6u;
static const uint EXPR_NEG = 13u;
static const uint EXPR_CAST = 36u;
static const uint STMT_ASSIGN = 5u;

bool binary_form(uint form) { return (form >= 7u && form <= 12u) || (form >= 14u && form <= 26u); }

void publish(uint g, uint rows, uint base, uint child)
{
    if (child == RT_INVALID) return;
    if (child >= rows)
    {
        pj_row_fail(g, PJ_E_INCOMPLETE, child);
        return;
    }
    uint old;
    InterlockedCompareExchange(pj_g_aux[base + child].x, RT_INVALID, g, old);
    if (old != RT_INVALID && old != g) pj_row_fail(g, PJ_E_FORM, 0xffu);
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint g = pj_lane(dtid);
    uint n = pj_instance_count();
    // Every array-element record owns a distinct value row, so the element
    // count is bounded by the row dispatch. No array-sized lane walk.
    uint column = PJ_C_SIDE + PJ_SIDE_ARRAY_ELEMENTS;
    if (g < pj_total(column))
    {
        uint owner = pj_rank_of(column, g, 0u, n);
        uint4 element = pj_side(owner, PJ_SIDE_ARRAY_ELEMENTS, g - pj_base_at(owner, column), 0u);
        uint start = pj_base_at(owner, PJ_C_ROWS);
        publish(start + element.x, pj_inf(owner, 1u).x, start, element.y);
    }
    if (g >= pj_total(PJ_C_ROWS)) return;
    uint rank = pj_rank_of(PJ_C_ROWS, g, 0u, n);
    uint base = pj_base_at(rank, PJ_C_ROWS);
    uint row = g - base;
    uint rows = pj_inf(rank, 1u).x;
    if (row == 0u) return;
    uint kind = pj_row(rank, row, 0u).x;
    uint4 p = pj_row(rank, row, 2u);
    bool fixed = kind >= RT_HIR_EXPR && kind <= RT_HIR_LITERAL_EXPR &&
        kind != RT_HIR_CALL_EXPR && kind != RT_HIR_MEMBER_EXPR;
    if (fixed)
    {
        if (p.x == 1u || p.x == EXPR_NOT || p.x == EXPR_NEG || p.x == EXPR_CAST) publish(g, rows, base, p.y);
        else if (binary_form(p.x)) { publish(g, rows, base, p.y); publish(g, rows, base, p.z); }
    }
    if (kind == RT_HIR_ARRAY_EXPR && (p.x == 37u || p.x == 38u)) publish(g, rows, base, p.y);
    else if (kind == RT_HIR_INDEX_EXPR)
    {
        publish(g, rows, base, p.y);
        publish(g, rows, base, p.z);
    }
    else if (kind == RT_HIR_MEMBER_EXPR || kind == RT_HIR_TRY_EXPR) publish(g, rows, base, p.y);
    else if ((kind == RT_HIR_STMT || kind == RT_HIR_ASSIGN_EXPR) && p.x == STMT_ASSIGN) publish(g, rows, base, p.y);
    else if (kind == RT_HIR_FOR_STMT || (kind == RT_HIR_STMT && p.x == 7u)) publish(g, rows, base, p.z);
    else if (kind == RT_HIR_CALL_EXPR)
    {
        publish(g, rows, base, p.x);
        for (uint k = 0u; k < p.z && p.y + k < pj_side_len(rank, PJ_SIDE_CALL_ARGS); k++)
            publish(g, rows, base, pj_side(rank, PJ_SIDE_CALL_ARGS, p.y + k, 0u).y);
    }
    else if (kind == RT_HIR_STRUCT_LITERAL_EXPR)
    {
        for (uint k = 0u; k < p.z && p.y + k < pj_side_len(rank, PJ_SIDE_FIELDS); k++)
            publish(g, rows, base, pj_side(rank, PJ_SIDE_FIELDS, p.y + k, 0u).z);
    }
}
