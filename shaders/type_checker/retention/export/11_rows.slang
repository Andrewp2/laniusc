// Export step 11: one lane per row of a retained body. Writes the row's
// segment record (RT_ROW_WORDS uint4), every reference relative to its body:
//   r0 (kind, parent row, token start, token end)
//   r1 (first child, next sibling, subtree end, file id)
//   r2 payload: rows, tokens, side-table indices and contexts relative to the
//      body; item kinds, operator forms and literal words unchanged
//   r3 (type term, use index within the body or RT_NONE, 0, flags)
//   r4 (return-type row, constant-value row, array-element start, count)
// A reference outside the body becomes RT_REL_FOREIGN and is counted in the
// body's FOREIGN statistic; untranslated or unowned type terms are counted
// too. Nothing else of the job (canonical IDs, absolute rows) is written.
import hir_records;
import type_checker.retention.retention_store;
import type_checker.retention.retention_job;
import type_checker.retention.export.common;
import type_checker.retention.export.side_tables;
import type_checker.retention.export.body_common;
import type_checker.retention.export.type_rows;

StructuredBuffer<uint> compact_fn_return_type;
StructuredBuffer<uint> compact_const_value;
StructuredBuffer<uint> compact_array_element_start;
StructuredBuffer<uint> compact_array_element_count;

static const uint HIR_STMT = 7u;
static const uint HIR_LET_STMT = 8u;
static const uint HIR_RETURN_STMT = 9u;
static const uint HIR_IF_STMT = 10u;
static const uint HIR_WHILE_STMT = 11u;
static const uint HIR_BREAK_STMT = 12u;
static const uint HIR_CONTINUE_STMT = 13u;
static const uint HIR_INDEX_EXPR = 20u;
static const uint HIR_NAME_EXPR = 22u;
static const uint HIR_LITERAL_EXPR = 23u;
static const uint HIR_ARRAY_EXPR = 24u;
static const uint HIR_STRUCT_LITERAL_EXPR = 28u;
static const uint HIR_FOR_STMT = 30u;
static const uint HIR_MATCH_EXPR = 34u;
static const uint HIR_TRY_EXPR = 36u;
static const uint STMT_LET = 1u;
static const uint STMT_RETURN = 2u;
static const uint STMT_IF = 3u;
static const uint STMT_CONST = 4u;
static const uint STMT_ASSIGN = 5u;
static const uint STMT_WHILE = 6u;
static const uint STMT_FOR = 7u;
static const uint HIR_EXPR_INT = 3u;
static const uint HIR_EXPR_FLOAT = 27u;
static const uint HIR_EXPR_STRING = 28u;
static const uint HIR_EXPR_CHAR = 29u;

public static const uint RT_ROW_TYPED = 1u;
public static const uint RT_ROW_FOREIGN = 2u;

// Mirrors closure/09_exec_rows.slang payload_of: the same columns are rows,
// tokens, side indices and contexts.
HirPayload rel_payload(SegmentContext c, uint row, HirCore core, HirPayload p, inout uint f)
{
    BodySpan s = c.span;
    if (row == s.function) { p.b = rel_token(s, p.b, f); return p; }
    if (core.kind == HIR_PARAM)
    {
        p.a = rel_row(s, p.a, f); p.c = rel_token(s, p.c, f); p.d = rel_row(s, p.d, f);
        return p;
    }
    if (core.kind == HIR_TYPE)
    {
        p.b = rel_row(s, p.b, f); p.c = rel_token(s, p.c, f); p.d = rel_row(s, p.d, f);
        return p;
    }
    if (core.kind == HIR_STMT || core.kind == HIR_LET_STMT || core.kind == HIR_RETURN_STMT ||
        core.kind == HIR_IF_STMT || core.kind == HIR_WHILE_STMT || core.kind == HIR_BREAK_STMT ||
        core.kind == HIR_CONTINUE_STMT || core.kind == HIR_FOR_STMT)
    {
        if (p.a == STMT_LET || p.a == STMT_CONST || p.a == STMT_FOR)
        { p.b = rel_token(s, p.b, f); p.c = rel_row(s, p.c, f); p.d = rel_row(s, p.d, f); }
        else if (p.a == STMT_RETURN) { p.b = rel_row(s, p.b, f); p.d = rel_token(s, p.d, f); }
        else if (p.a == STMT_ASSIGN) { p.b = rel_row(s, p.b, f); p.c = rel_row(s, p.c, f); }
        else if (p.a == STMT_IF || p.a == STMT_WHILE)
        { p.b = rel_row(s, p.b, f); p.c = rel_row(s, p.c, f); p.d = rel_row(s, p.d, f); }
        return p;
    }
    if (core.kind == HIR_CALL_EXPR)
    {
        p.a = rel_row(s, p.a, f); p.b = rel_side(c, RT_SIDE_CALL_ARGS, p.b, f); p.d = rel_context(c, p.d, f);
        return p;
    }
    if (core.kind == HIR_INDEX_EXPR || core.kind == HIR_TRY_EXPR)
    {
        p.b = rel_row(s, p.b, f); p.c = rel_row(s, p.c, f); p.d = rel_token(s, p.d, f);
        return p;
    }
    if (core.kind == HIR_MEMBER_EXPR)
    {
        p.b = rel_row(s, p.b, f); p.c = rel_token(s, p.c, f); p.d = rel_token(s, p.d, f);
        return p;
    }
    if (core.kind == HIR_ARRAY_EXPR)
    {
        p.b = rel_row(s, p.b, f); p.c = rel_token(s, p.c, f); p.d = rel_context(c, p.d, f);
        return p;
    }
    if (core.kind == HIR_STRUCT_LITERAL_EXPR)
    {
        p.b = rel_side(c, RT_SIDE_FIELDS, p.b, f); p.d = rel_context(c, p.d, f);
        return p;
    }
    if (core.kind == HIR_MATCH_EXPR)
    {
        p.a = rel_row(s, p.a, f); p.b = rel_side(c, RT_SIDE_MATCH_ARMS, p.b, f);
        return p;
    }
    if (p.a == 0u || p.a == HIR_EXPR_FLOAT) return p;
    if (p.a == HIR_EXPR_INT || p.a == HIR_EXPR_CHAR) { p.d = rel_token(s, p.d, f); return p; }
    if (p.a == HIR_EXPR_STRING && core.kind == HIR_LITERAL_EXPR)
    {
        p.b = rel_side(c, RT_SIDE_STRINGS, p.b, f); p.c = rel_row(s, p.c, f); p.d = rel_token(s, p.d, f);
        return p;
    }
    if (core.kind != HIR_NAME_EXPR) p.b = rel_row(s, p.b, f);
    p.c = rel_row(s, p.c, f);
    p.d = rel_token(s, p.d, f);
    return p;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint row = export_lane(dtid);
    if (row >= hir_count() || rt_x_flags[row].x == 0u) return;
    uint function = body_function(row);
    if (function == 0xffffffffu) return;
    SegmentContext c = segment_context(function);
    if (c.segment == RT_INVALID || c.row_base == RT_INVALID) return;
    uint index = rt_x_counts[RT_X_BASE + RT_A_SEG_ROWS] + rt_x_scan[row].x;
    if (index - c.row_base != row - function)
    {
        rt_invariant(RT_INV_SEGMENT);
        return;
    }

    uint foreign = 0u;
    uint untranslated = 0u;
    uint unowned = 0u;
    HirCore core = compact_hir_core[row];
    HirLinks links = compact_hir_links[row];
    uint4 r0 = uint4(core.kind,
        row == function ? 0xffffffffu : rel_row(c.span, core.parent, foreign),
        rel_token(c.span, core.token_start, foreign),
        rel_token(c.span, core.token_end, foreign));
    uint4 r1 = uint4(rel_row(c.span, links.first_child, foreign),
        row == function ? 0xffffffffu : rel_row(c.span, links.next_sibling, foreign),
        rel_boundary(c.span, links.subtree_end, foreign),
        links.file_id);
    HirPayload p = rel_payload(c, row, core, compact_hir_payload[row], foreign);

    uint tag = semantic_expr_ref_tag_by_hir[row];
    uint term = body_term(c, tag, semantic_expr_ref_payload_by_hir[row], untranslated, unowned);
    uint use = rt_x_flags[row].y != 0u ? rt_x_scan[row].y - rt_x_scan[function].y : RT_NONE;
    uint before = foreign;
    uint elements = compact_array_element_count[row];
    uint4 r4 = uint4(rel_row(c.span, compact_fn_return_type[row], foreign),
        rel_row(c.span, compact_const_value[row], foreign),
        elements != 0u ? rel_side(c, RT_SIDE_ARRAY_ELEMENTS, compact_array_element_start[row], foreign) : 0xffffffffu,
        elements);
    uint flags = (rt_is_resolved(term) ? RT_ROW_TYPED : 0u) | (foreign != 0u ? RT_ROW_FOREIGN : 0u);
    uint4 r3 = uint4(term, use, 0u, flags);

    uint base = index * RT_ROW_WORDS;
    rt_seg_rows[base + 0u] = r0;
    rt_seg_rows[base + 1u] = r1;
    rt_seg_rows[base + 2u] = uint4(p.a, p.b, p.c, p.d);
    rt_seg_rows[base + 3u] = r3;
    rt_seg_rows[base + 4u] = r4;
    stat_add(function, RT_STAT_FOREIGN, foreign);
    stat_add(function, RT_STAT_UNTRANSLATED, untranslated);
    stat_add(function, RT_STAT_OWNERSHIP, unowned);
    if (unowned != 0u) rt_invariant(RT_INV_OWNERSHIP);
}
