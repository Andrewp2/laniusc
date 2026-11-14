// Operand checks of the instance table's virtual rows (instance_table.slang):
// one lane per virtual row, after the rows realize (06a).
//
// conditions/compact_expr checks a template's operators, conditions,
// logical operands and indexing on the template's scalar types. An operand
// of type `T` has none there, so the check passes for every instance. This
// pass applies the same rules (operator_operand_rules) to the operand types
// each instance realizes: `add<bool>`'s `a + b`, `pick<i32>`'s `if (c)`,
// `neg<i32>`'s `!c`, `same<str>`'s `a == b` and `first<i32>`'s `a[0]`.
//
// The same lanes apply what the template could not check for a row whose
// type is a parameter: an unsuffixed literal with a symbolic context
// (literal_symbolic_context.slang) must be an integer or float literal of
// the instance's scalar kind, its magnitude must fit that scalar (a signed
// minimum under unary minus included) and a float's rounding status in that
// width must be exact-or-rounded, the HIR's own status for the width. A
// negation needs a numeric operand. A returned, declared or assigned value
// must have its destination's instance type.
//
// Operand types are classified from the complete realized reference
// (operator_operand_type): a struct, enum, array or slice instance is a
// resolved type with no arithmetic, condition or index role, not an unknown.
//
// A rule is applied only when an operand's type changed under the
// instance's environment; a row whose operands keep the template's types was
// checked with the template. An error is LNC0006 at the template operand's
// first token, the source location a replay of the body reports. Entries are
// the instances that calls of this job reach (instance_closure.slang), so
// each has a checked call; a capacity or closure flag leaves no rows to
// check.
import primitive_types;
import integer_words;
import hir_records;
import hir_expr_semantics;
import status;
import type_checker.checked_index_reference;
import type_checker.operator_operand_rules;
import type_checker.float_literal_selection;
import type_checker.literal_symbolic_context;
import type_checker.closure.instance_closure;
import type_checker.closure.instance_table;

StructuredBuffer<uint> compact_hir_count;
StructuredBuffer<HirCore> compact_hir_core;
StructuredBuffer<HirPayload> compact_hir_payload;
StructuredBuffer<HirSemanticFacts> compact_hir_semantic_facts;
StructuredBuffer<uint> compact_hir_expr_parent;
StructuredBuffer<uint> compact_hir_nearest_fn;
StructuredBuffer<uint> compact_fn_return_type;
StructuredBuffer<uint> literal_context_type_by_hir;
StructuredBuffer<uint> semantic_expr_ref_tag_by_hir;
StructuredBuffer<uint> semantic_expr_ref_payload_by_hir;
StructuredBuffer<uint> type_instance_kind;
StructuredBuffer<uint> type_instance_elem_ref_tag;
StructuredBuffer<uint> type_instance_elem_ref_payload;
RWStructuredBuffer<uint> status;

static const uint INVALID = 0xffffffffu;
static const uint ERR_ASSIGN_MISMATCH = 3u;
static const uint ERR_INTEGER_LITERAL_RANGE = 24u;
static const uint ERR_FLOAT_LITERAL = 25u;
static const uint TYPE_REF_SCALAR = 1u;
static const uint HIR_STMT = 7u;
static const uint HIR_LET_STMT = 8u;
static const uint HIR_RETURN_STMT = 9u;
static const uint HIR_ASSIGN_EXPR = 15u;
static const uint HIR_LITERAL_EXPR = 23u;
static const uint HIR_STMT_LET = 1u;
static const uint HIR_STMT_RETURN = 2u;
static const uint HIR_STMT_ASSIGN = 5u;
static const uint HIR_EXPR_FLOAT = 27u;
static const uint HIR_IF_STMT = 10u;
static const uint HIR_WHILE_STMT = 11u;
static const uint HIR_EXPR = 14u;
static const uint HIR_BINARY_EXPR = 16u;
static const uint HIR_UNARY_EXPR = 17u;
static const uint HIR_INDEX_EXPR = 20u;
static const uint HIR_STMT_IF = 3u;
static const uint HIR_STMT_WHILE = 6u;
static const uint HIR_EXPR_INT = 3u;
static const uint HIR_EXPR_CAST = 36u;

// One instance's view of a template row's operand.
struct Operand
{
    uint node;     // template row, or INVALID
    uint tag;      // realized reference; TYPE_REF_INVALID (0) when unknown
    uint payload;
    uint ty;       // operator_operand_type class, or OPR_TY_UNKNOWN
    bool changed;  // the environment changed the template's type
};

uint hir_count()
{
    uint rows; uint stride;
    compact_hir_core.GetDimensions(rows, stride);
    return min(compact_hir_count[0u], rows);
}

Operand operand_of(uint4 entry, uint node)
{
    Operand operand;
    operand.node = INVALID;
    operand.tag = 0u;
    operand.payload = 0u;
    operand.ty = OPR_TY_UNKNOWN;
    operand.changed = false;
    // An operand is a row of the template's subtree.
    if (node == INVALID || node < entry.x || node - entry.x >= entry.y) return operand;
    operand.node = node;
    uint2 realized = instance_row_refs[entry.w + (node - entry.x)];
    if (realized.x == 0u || realized.x == IT_ROW_FAILED) return operand;
    operand.tag = realized.x - 1u;
    operand.payload = realized.y;
    operand.changed = operand.tag != semantic_expr_ref_tag_by_hir[node] ||
        operand.payload != semantic_expr_ref_payload_by_hir[node];
    operand.ty = operator_operand_type(OPR_TY_UNKNOWN, operand.tag, operand.payload,
        type_instance_kind);
    return operand;
}

bool null_pointer_constant(uint node)
{
    return node < hir_count() && compact_hir_core[node].kind == HIR_LITERAL_EXPR &&
        compact_hir_payload[node].a == HIR_EXPR_INT &&
        compact_hir_payload[node].b == 0u && compact_hir_payload[node].c == 0u;
}

void record_mismatch(uint node, uint detail)
{
    record_min_token_error(status, compact_hir_core[node].token_start, ERR_ASSIGN_MISMATCH, detail);
}

// Whether literal `node`'s only expression owner above forwarding wrappers
// is a unary minus (compact_expr's literal_is_under_unary_minus).
bool literal_is_under_unary_minus(uint node)
{
    uint count = hir_count();
    for (uint step = 0u; step < count && node < count; step++)
    {
        uint parent = compact_hir_expr_parent[node];
        if (parent >= count || parent == node) return false;
        HirCore core = compact_hir_core[parent];
        HirPayload payload = compact_hir_payload[parent];
        if (payload.b != node) return false;
        if (core.kind == HIR_UNARY_EXPR && payload.a == OPR_EXPR_NEG) return true;
        if (!hir_is_forward_expression(core.kind, payload.a)) return false;
        node = parent;
    }
    return false;
}

// A literal whose template context is a type parameter, in this instance:
// its kind must match the realized scalar, and its value must be
// representable there. The default the template would have used (i32 or
// f32) is the found type of a kind mismatch, as for a concrete context.
void check_symbolic_literal(uint4 entry, uint node, HirCore core, HirPayload payload)
{
    if (core.kind != HIR_LITERAL_EXPR || (payload.a != HIR_EXPR_INT && payload.a != HIR_EXPR_FLOAT))
        return;
    if (!literal_context_is_symbolic(literal_context_type_by_hir[node])) return;
    Operand literal = operand_of(entry, node);
    if (literal.node == INVALID || literal.tag == 0u) return;
    bool floating = payload.a == HIR_EXPR_FLOAT;
    uint found = floating ? SCALAR_F32 : SCALAR_I32;
    uint scalar = literal.ty;
    if (floating ? !scalar_is_float(scalar) : !scalar_is_integer(scalar))
    {
        record_mismatch(node, operator_detail_code(scalar) * 256u + found);
        return;
    }
    if (!floating)
    {
        if (!integer_words_magnitude_fits(uint2(payload.b, payload.c), scalar,
            literal_is_under_unary_minus(node)))
            record_min_token_error(status, core.token_start, ERR_INTEGER_LITERAL_RANGE, scalar);
        return;
    }
    uint result;
    if (selected_float_literal_status(compact_hir_semantic_facts[node].literal_status, scalar, result) &&
        result != 0u)
        record_min_token_error(status, core.token_start, ERR_FLOAT_LITERAL, (scalar << 8u) | result);
}

void check_negation(uint4 entry, HirPayload payload)
{
    Operand operand = operand_of(entry, payload.b);
    uint detail;
    if (operand.changed && operator_negation_violation(operand.ty, detail))
        record_mismatch(operand.node, detail);
}

// A value stored to a destination of another instance type: compact_stmt's
// scalar pair rule (a null constant fits a pointer) and its scalar/aggregate
// rule, on the realized types. Two aggregates are not compared here.
void check_destination(Operand destination, Operand value)
{
    if (value.node == INVALID || (!destination.changed && !value.changed)) return;
    uint expected = destination.ty;
    uint actual = value.ty;
    if (expected == OPR_TY_UNKNOWN || actual == OPR_TY_UNKNOWN || expected == actual) return;
    if (actual == SCALAR_NEVER) return;
    if (operator_is_aggregate(expected) && operator_is_aggregate(actual)) return;
    if (expected == OPR_TY_POINTER && actual == OPR_TY_INT && null_pointer_constant(value.node)) return;
    record_mismatch(value.node, operator_detail_code(expected) * 256u + operator_detail_code(actual));
}

void check_statement(uint4 entry, uint node, HirCore core, HirPayload payload)
{
    if (core.kind != HIR_STMT && core.kind != HIR_LET_STMT &&
        core.kind != HIR_RETURN_STMT && core.kind != HIR_ASSIGN_EXPR) return;
    if (payload.a == HIR_STMT_RETURN)
    {
        uint function = compact_hir_nearest_fn[node];
        if (function >= hir_count()) return;
        check_destination(operand_of(entry, compact_fn_return_type[function]),
            operand_of(entry, payload.b));
    }
    else if (payload.a == HIR_STMT_LET)
        check_destination(operand_of(entry, payload.d), operand_of(entry, payload.c));
    else if (payload.a == HIR_STMT_ASSIGN)
    {
        Operand destination = operand_of(entry, payload.b);
        Operand value = operand_of(entry, payload.c);
        if (!operator_pointer_offset_assignment(payload.d, destination.ty, value.ty))
            check_destination(destination, value);
    }
}

void check_bool(Operand operand)
{
    uint detail;
    if (operand.changed && operator_bool_violation(operand.ty, detail))
        record_mismatch(operand.node, detail);
}

void check_binary(uint4 entry, HirPayload payload)
{
    Operand left = operand_of(entry, payload.b);
    Operand right = operand_of(entry, payload.c);
    if (!left.changed && !right.changed) return;
    uint detail;
    uint rejected = operator_binary_violation(payload.a, left.ty, right.ty,
        null_pointer_constant(payload.b), null_pointer_constant(payload.c), detail);
    if (rejected == OPR_OPERAND_LEFT && left.node != INVALID) record_mismatch(left.node, detail);
    else if (rejected == OPR_OPERAND_RIGHT && right.node != INVALID) record_mismatch(right.node, detail);
}

// compact_expr's validate_index: the base is an array or slice (a scalar
// code, or a checked array, slice or reference to one), the index an integer.
void check_index(uint4 entry, uint node, HirPayload payload)
{
    Operand base = operand_of(entry, payload.b);
    if (base.changed && base.ty != OPR_TY_UNKNOWN && !operator_is_array_type(base.ty))
    {
        uint container;
        if (!checked_index_container(base.tag, base.payload, type_instance_kind,
            type_instance_elem_ref_tag, type_instance_elem_ref_payload, container))
        {
            record_mismatch(node, operator_detail_code(base.ty));
            return;
        }
    }
    Operand index = operand_of(entry, payload.c);
    uint detail;
    if (index.changed && operator_index_violation(index.ty, detail))
        record_mismatch(index.node, detail);
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint row = dtid.x + dtid.y * 16776960u;
    uint rows = instance_table_counts[IT_COUNT_FLAGS] != 0u ? 0u
        : min(instance_table_counts[IT_COUNT_ROWS], it_row_capacity());
    if (row >= rows) return;
    uint index = it_entry_of_row(row, instance_table_counts[IT_COUNT_ENTRIES]);
    uint4 entry = instance_table[2u * index];
    if (instance_table[2u * index + 1u].z != IT_SOURCE_LOCAL) return;
    uint count = hir_count();
    uint node = entry.x + (row - entry.w);
    if (entry.x >= count || node >= count) return;
    HirCore core = compact_hir_core[node];
    HirPayload payload = compact_hir_payload[node];
    if (core.kind == HIR_INDEX_EXPR)
    {
        check_index(entry, node, payload);
        return;
    }
    check_symbolic_literal(entry, node, core, payload);
    check_statement(entry, node, core, payload);
    if (core.kind == HIR_UNARY_EXPR && payload.a == OPR_EXPR_NEG)
        check_negation(entry, payload);
    if (core.kind == HIR_BINARY_EXPR && payload.a != HIR_EXPR_CAST)
        check_binary(entry, payload);
    if (core.kind == HIR_IF_STMT || core.kind == HIR_WHILE_STMT ||
        (core.kind == HIR_STMT && (payload.a == HIR_STMT_IF || payload.a == HIR_STMT_WHILE)))
    {
        check_bool(operand_of(entry, payload.b));
        return;
    }
    if ((core.kind == HIR_EXPR || core.kind == HIR_BINARY_EXPR || core.kind == HIR_UNARY_EXPR) &&
        operator_logical_form(payload.a))
    {
        check_bool(operand_of(entry, payload.b));
        if (payload.a != OPR_EXPR_NOT) check_bool(operand_of(entry, payload.c));
    }
}
