// Export step 11: one lane per row of a retained body. Writes the row's
// segment record (RT_ROW_WORDS uint4), every reference relative to its body:
//   r0 (kind, parent row, token start, token end)
//   r1 (first child, next sibling, subtree end, file id)
//   r2 payload, each word encoded by its class (row_classes.slang)
//   r3 (type term, use index within the body or RT_NONE, role, flags)
//   r4 (return-type row, constant-value row, array-element start, count)
//   r5 (binding kind, binding value, binding aux, member field ordinal)
//   r6 (argument mode | iterable kind << 8 | float status << 16, constant flags, value lo, value hi)
// A type row's term is its checked type (type_row_term); a variant
// constructor's callee keeps none; every other row's is its checked
// expression reference. A variant pattern typed with its enum's declared
// application keeps none either. A VALUE or TYPE row without a resolved term is
// counted UNTYPED; BOUND, PATTERN and CALLEE rows denote no value. A reference outside the body becomes
// RT_REL_FOREIGN and is counted FOREIGN; untranslated and unowned terms are
// counted too. Nothing else of the job (canonical IDs, absolute rows or
// tokens, declaration tokens) is written.
import hir_records;
import type_checker.retention.retention_store;
import type_checker.retention.retention_job;
import type_checker.retention.row_classes;
import type_checker.retention.export.common;
import type_checker.retention.export.side_tables;
import type_checker.retention.export.body_common;
import type_checker.retention.export.type_rows;
import type_checker.retention.export.source_tables;

StructuredBuffer<HirSemanticFacts> compact_hir_semantic_facts;
StructuredBuffer<uint> compact_fn_return_type;
StructuredBuffer<uint> compact_const_value;
StructuredBuffer<uint> compact_array_element_start;
StructuredBuffer<uint> compact_array_element_count;
StructuredBuffer<uint> semantic_value_decl_by_hir;
StructuredBuffer<uint> semantic_argument_mode_by_hir;
StructuredBuffer<uint> semantic_iterable_kind_by_hir;
StructuredBuffer<uint> semantic_member_field_ordinal_by_hir;

public static const uint RT_ROW_TYPED = 1u;
public static const uint RT_ROW_FOREIGN = 2u;
public static const uint RT_ROW_MISSING = 4u;

uint rel_word(SegmentContext c, uint cls, uint word, inout uint f)
{
    if (cls == RT_CLASS_ROW) return rel_row(c.span, word, f);
    if (cls == RT_CLASS_TOKEN) return rel_token(c.span, word, f);
    if (cls == RT_CLASS_CONTEXT) return rel_context(c, word, f);
    if (cls >= RT_CLASS_SIDE) return rel_side(c, cls - RT_CLASS_SIDE, word, f);
    return word;
}

HirPayload rel_payload(SegmentContext c, uint row, HirCore core, HirPayload p, inout uint f)
{
    uint classes = rt_payload_classes(core.kind, p.a, row == c.span.function);
    p.a = rel_word(c, rt_word_class(classes, 0u), p.a, f);
    p.b = rel_word(c, rt_word_class(classes, 1u), p.b, f);
    p.c = rel_word(c, rt_word_class(classes, 2u), p.c, f);
    p.d = rel_word(c, rt_word_class(classes, 3u), p.d, f);
    return p;
}

// Whether `row` is the wildcard `_`: one token spelled `_`. A wildcard
// pattern binds and constructs nothing, at an arm or in a payload.
bool wildcard(uint row)
{
    RtJobToken token = job_token(compact_hir_core[row].token_start);
    return token.len == 1u && job_source_byte(token.start) == 0x5fu;
}

// Direct range syntax is the control input of a for, not a runtime range
// value. Its endpoints carry values; the owning for carries the binder type.
bool direct_for_range(uint row)
{
    uint kind = compact_hir_core[row].kind;
    uint form = compact_hir_payload[row].a;
    uint parent = compact_hir_core[row].parent;
    if ((kind != RT_HIR_EXPR && kind != RT_HIR_BINARY_EXPR) || form < 30u || form > 35u || !valid_row(parent)) return false;
    uint parent_kind = compact_hir_core[parent].kind;
    HirPayload p = compact_hir_payload[parent];
    return (parent_kind == RT_HIR_FOR_STMT || (parent_kind == RT_HIR_STMT && p.a == 7u)) && p.c == row;
}

uint row_role(uint row, uint function, uint kind)
{
    if (row == function || direct_for_range(row)) return RT_ROLE_STRUCTURAL;
    if (kind == RT_HIR_TYPE)
    {
        uint semantic = compact_hir_semantic_facts[row].semantic_kind;
        bool bound = semantic == HIR_SEMANTIC_BOUND_PATH || semantic == HIR_SEMANTIC_BOUND_REFERENCE;
        return bound ? RT_ROLE_BOUND : RT_ROLE_TYPE;
    }
    if (callee_position(row)) return RT_ROLE_CALLEE;
    if (variant_pattern(row, semantic_value_decl_by_hir[row], semantic_value_const_present_by_hir[row]) ||
        (pattern_position(row) && (kind == RT_HIR_NAME_EXPR || kind == RT_HIR_PATH_EXPR) && wildcard(row)))
        return RT_ROLE_PATTERN;
    return rt_value_kind(kind) ? RT_ROLE_VALUE : RT_ROLE_STRUCTURAL;
}

static const uint HIR_TYPE_FORM_ARRAY = 2u;
static const uint RT_STMT_FORM_LET = 1u;
static const uint RT_STMT_FORM_CONST = 4u;

// Rows whose semantic_expr_ref is a checked reference (01_expression_refs):
// expressions, let/const storage, and for binders (01b_array_index_refs). Function,
// parameter, block and other statement rows hold the per-row scalar cache,
// which is not a type.
bool checked_value_row(uint row, uint function, uint kind, uint form)
{
    if (row == function || direct_for_range(row)) return false;
    if (rt_value_kind(kind) || kind == RT_HIR_LET_STMT || kind == RT_HIR_FOR_STMT) return true;
    return kind == RT_HIR_STMT && (form == RT_STMT_FORM_LET || form == RT_STMT_FORM_CONST || form == 7u);
}

// A type row with no type of its own that is an array type's length (a
// constant parameter or expression in type position): the array term's
// length operand, which is the constant count the row denotes.
uint array_length_term(uint row, uint parent)
{
    if (!valid_row(parent) || compact_hir_core[parent].kind != RT_HIR_TYPE) return RT_NONE;
    HirPayload p = compact_hir_payload[parent];
    if (p.a != HIR_TYPE_FORM_ARRAY || p.d != row) return RT_NONE;
    uint array = type_row_term(parent);
    if (!rt_is_term(array) || rt_term_kind(array) != RT_KIND_ARRAY || rt_term_arity(array) < 2u) return RT_NONE;
    return rt_term_arg(array, 1u);
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

    uint role = row_role(row, function, core.kind);
    uint term = RT_NONE;
    if (core.kind == RT_HIR_TYPE)
    {
        term = type_row_term(row);
        if (term == RT_NONE) term = array_length_term(row, core.parent);
        if (term == RT_UNKNOWN) untranslated++;
        else if (!owned_by(term, c.decl, c.parent)) unowned++;
    }
    else if (role == RT_ROLE_PATTERN && (semantic_value_const_present_by_hir[row] & RT_CONST_VARIANT) != 0u)
    {
        // An imported variant pattern's external canonical reference names
        // the enum's declaration schema, not a value instantiated in this
        // body. Keep its accepted variant ordinal. The arm/payload edges
        // provide the matched type, including every nested type argument;
        // projection checks the ordinal and payloads against that schema.
    }
    else if (role == RT_ROLE_CALLEE && (binding_target(semantic_value_decl_by_hir[row]) & RT_X_VARIANT_BIT) != 0u)
    {
        // A variant constructor's callee (`Wrap::Value` in `Wrap::Value(e)`)
        // is callable syntax. The checker types it with the enum's declared
        // self application over the enum's own parameters, a schema fact
        // (rt_schema, the enum's binders), not a value of this body. The
        // caller-scoped instance is the call row's term and its use's
        // result and environment. The row keeps no term; its variant is its
        // binding. The producer's term must still be the enum's or the
        // caller's, so a term naming any other binder stays an error.
        uint variant = binding_target(semantic_value_decl_by_hir[row]) & ~RT_X_VARIANT_BIT;
        uint enum_row = compact_variants[variant].owner;
        uint enum_decl = valid_row(enum_row) ? rt_x_row[enum_row].x : RT_INVALID;
        uint declared = translate_checked(semantic_expr_ref_tag_by_hir[row], semantic_expr_ref_payload_by_hir[row]);
        if (declared == RT_UNKNOWN || declared == RT_FIT_FAILED) untranslated++;
        else if (!owned_by(declared, c.decl, c.parent) &&
            (enum_decl == RT_INVALID || !owned_by(declared, enum_decl, 0u))) unowned++;
    }
    else if (role == RT_ROLE_PATTERN && (binding_target(semantic_value_decl_by_hir[row]) & RT_X_VARIANT_BIT) != 0u)
    {
        // A qualified variant pattern (`core::range::Bound::Unbounded`) is
        // typed with the enum's declared self application, a schema fact
        // over the enum's own parameters. Projection takes the matched
        // type from the scrutinee or the enclosing payload, so such a row
        // keeps no term. A term in the caller's scope is kept and checked
        // against the matched type; a term naming any other binder stays
        // an error.
        uint variant = binding_target(semantic_value_decl_by_hir[row]) & ~RT_X_VARIANT_BIT;
        uint enum_row = compact_variants[variant].owner;
        uint enum_decl = valid_row(enum_row) ? rt_x_row[enum_row].x : RT_INVALID;
        uint checked = translate_checked(semantic_expr_ref_tag_by_hir[row], semantic_expr_ref_payload_by_hir[row]);
        if (checked == RT_UNKNOWN || checked == RT_FIT_FAILED) untranslated++;
        else if (owned_by(checked, c.decl, c.parent)) term = checked;
        else if (enum_decl == RT_INVALID || !owned_by(checked, enum_decl, 0u)) unowned++;
    }
    else if (checked_value_row(row, function, core.kind, compact_hir_payload[row].a))
        term = body_term(c, semantic_expr_ref_tag_by_hir[row], semantic_expr_ref_payload_by_hir[row],
            untranslated, unowned);
    bool for_binding = core.kind == RT_HIR_FOR_STMT || (core.kind == RT_HIR_STMT && p.a == 7u);
    bool missing = (role == RT_ROLE_VALUE || role == RT_ROLE_TYPE || for_binding) && !rt_is_resolved(term);
    uint use = rt_x_flags[row].y != 0u ? rt_x_scan[row].y - rt_x_scan[function].y : RT_NONE;
    uint elements = compact_array_element_count[row];
    uint4 r4 = uint4(rel_row(c.span, compact_fn_return_type[row], foreign),
        rel_row(c.span, compact_const_value[row], foreign),
        elements != 0u ? rel_side(c, RT_SIDE_ARRAY_ELEMENTS, compact_array_element_start[row], foreign) : 0xffffffffu,
        elements);

    // Checked facts that no environment changes: the exact binding, the
    // member's field, the argument mode, the iterable kind and the
    // constant value (a constant parameter's value is its leaf).
    uint4 binding = resolve_binding(c.span, semantic_value_decl_by_hir[row]);
    foreign += binding.w;
    uint4 r5 = uint4(binding.xyz, semantic_member_field_ordinal_by_hir[row]);
    uint present = semantic_value_const_present_by_hir[row];
    uint2 value = semantic_value_const_by_hir[row];
    if ((present & RT_CONST_SYMBOLIC) != 0u)
    {
        uint param = param_map_find(value.x);
        if (param == RT_INVALID) { foreign++; value.x = RT_REL_FOREIGN; }
        else value.x = rt_param_leaf(param);
    }
    uint float_status = core.kind == RT_HIR_LITERAL_EXPR && p.a == 27u
        ? compact_hir_semantic_facts[row].literal_status & 0xffffu : 0u;
    uint4 r6 = uint4((semantic_argument_mode_by_hir[row] & 0xffu) | ((semantic_iterable_kind_by_hir[row] & 0xffu) << 8u) | (float_status << 16u),
        present, value.x, value.y);

    uint flags = (rt_is_resolved(term) ? RT_ROW_TYPED : 0u) | (foreign != 0u ? RT_ROW_FOREIGN : 0u) |
        (missing ? RT_ROW_MISSING : 0u);
    uint4 r3 = uint4(term, use, role, flags);

    uint base = index * RT_ROW_WORDS;
    rt_seg_rows[base + 0u] = r0;
    rt_seg_rows[base + 1u] = r1;
    rt_seg_rows[base + 2u] = uint4(p.a, p.b, p.c, p.d);
    rt_seg_rows[base + 3u] = r3;
    rt_seg_rows[base + 4u] = r4;
    rt_seg_rows[base + 5u] = r5;
    rt_seg_rows[base + 6u] = r6;
    stat_add(function, RT_STAT_UNTYPED, missing ? 1u : 0u);
    stat_add(function, RT_STAT_FOREIGN, foreign);
    stat_add(function, RT_STAT_UNTRANSLATED, untranslated);
    stat_add(function, RT_STAT_OWNERSHIP, unowned);
    if (unowned != 0u) rt_invariant(RT_INV_OWNERSHIP);
}
