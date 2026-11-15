// Common concrete row and type validation for projection and call checking.
import type_checker.operator_operand_rules;
import type_checker.inherited_expression_type;
__exported import type_checker.retention.projection.pj_types;

public struct Row
{
    public uint rank;
    public uint base;  // global row of the rank's function row
    public uint row;
    public uint g;
};

public static bool failed;

public void fail(Row at, uint code, uint detail)
{
    if (failed) return;
    failed = true;
    pj_row_fail(at.g, code, detail);
}

// A pointer context keeps literal-derived arithmetic at i32, matching
// expression_types/00_init and closure/table_rows. Pointer-valued operands
// still carry ptr. All consumers see this normalization.
public uint normalize_pointer_literal(Row at, uint row, uint type)
{
    if (type != SCALAR_PTR) return type;
    uint rows = pj_inf(at.rank,1u).x;
    for (uint step = 0u; step < rows && row < rows; step++)
    {
        uint kind = pj_row(at.rank,row,0u).x;
        uint4 payload = pj_row(at.rank,row,2u);
        if (!expression_inherits_operand_type(kind,payload.x))
            return kind == RT_HIR_LITERAL_EXPR && payload.x == 3u &&
                rt_is_param_leaf(pj_row(at.rank,row,3u).x) ? SCALAR_I32 : type;
        if (payload.y == row) break;
        row = payload.y;
    }
    return type;
}

// The closed substituted type of relative row `row`, or RT_INVALID.
public uint row_type(Row at, uint row)
{
    uint status;
    if (row == RT_INVALID || row >= pj_inf(at.rank, 1u).x) return RT_INVALID;
    if (!rt_is_resolved(pj_row(at.rank, row, 3u).x)) return RT_INVALID;
    uint t = pj_result(pj_req_row(at.rank, row), status);
    if (pj_row(at.rank, row, 6u).y == RT_CONST_SYMBOLIC && pj_row(at.rank, row, 0u).x != RT_HIR_TYPE)
        return rt_is_stored_term(t) && rt_term_kind(t) == RT_KIND_CC_VALUE ? rt_term_words(t).x : RT_INVALID;
    return normalize_pointer_literal(at,row,t);
}

public bool template_closed(Row at, uint row)
{
    return row != RT_INVALID && rt_term_closed(pj_row(at.rank, row, 3u).x);
}

// A closed runtime type with a complete lowering layout.
public bool supported_type(Row at, uint t)
{
    if (!rt_is_term(t))
    {
        fail(at, PJ_E_TYPE, 0u);
        return false;
    }
    if (t < RT_FIRST_TERM)
    {
        if (t == SCALAR_UNKNOWN)
        {
            fail(at, PJ_E_TYPE, t);
            return false;
        }
        return true;
    }
    uint kind = rt_term_kind(t);
    if (kind != RT_KIND_NAMED && kind != RT_KIND_ARRAY && kind != RT_KIND_SLICE && kind != RT_KIND_REF)
    {
        fail(at, PJ_E_TYPE, kind);
        return false;
    }
    if (pj_layout[t].x == RT_INVALID || pj_layout[t].y == 0u)
    {
        fail(at, PJ_E_LAYOUT, t);
        return false;
    }
    return true;
}

public uint result_or_fail(Row at, uint request)
{
    uint status;
    uint t = pj_result(request, status);
    if (t == RT_INVALID) fail(at, status == 0xffffu ? PJ_E_PUBLICATION : PJ_E_SUBST, status);
    return t;
}

public uint operand_class(uint t)
{
    if (!rt_is_term(t)) return OPR_TY_UNKNOWN;
    if (t < RT_FIRST_TERM) return scalar_is_known(t) ? t : OPR_TY_UNKNOWN;
    uint kind = rt_term_kind(t);
    if (kind == RT_KIND_NAMED) return OPR_TY_NAMED;
    if (kind == RT_KIND_ARRAY || kind == RT_KIND_SLICE) return OPR_TY_SEQUENCE;
    return OPR_TY_UNKNOWN;
}

public bool null_literal(Row at, uint row)
{
    if (row == RT_INVALID) return false;
    uint4 p = pj_row(at.rank, row, 2u);
    return pj_row(at.rank, row, 0u).x == RT_HIR_LITERAL_EXPR && p.x == 3u && p.y == 0u && p.z == 0u;
}

public void rule(Row at, uint code, uint detail) { fail(at, PJ_E_RULE, (code << 24u) | (detail & 0xffffffu)); }

// A value of type `value` stored where `expected` is required, when either
// side was symbolic in the template: the realized types must be equal (a
// null constant fits a pointer).
public void check_destination(Row at, uint expected, uint value_row, bool changed)
{
    if (!changed || value_row == RT_INVALID) return;
    uint actual = row_type(at, value_row);
    if (actual == RT_INVALID || expected == RT_INVALID || actual == expected) return;
    if (expected == SCALAR_PTR && null_literal(at, value_row)) return;
    rule(at, PJ_RULE_ASSIGN_MISMATCH,
        operator_detail_code(operand_class(expected)) * 256u + operator_detail_code(operand_class(actual)));
}

