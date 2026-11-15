// Projection step 5: one lane per global row. Checks that the row can be
// projected and is valid in its instance, and records its facts:
// - the row's form, role, binding and constant are supported, and the row
//   is complete (no MISSING or FOREIGN reference);
// - its term substitutes to a published, OK, closed type with a complete
//   layout (the function row checks the signature);
// - a call's use is DIRECT with no receiver adjustment, its route names the
//   use's callee at the substituted environment, and its arguments and
//   result equal the target's substituted signature; a struct literal's
//   use is a RECORD with no route, and its fields have the declared types;
// - the literal, operator, condition and destination rules of the
//   frontend (operator_operand_rules.slang, integer_words.slang,
//   closure/06c_table_operands.slang) hold where the template's types were
//   symbolic.
// pj_g_facts receives (reference tag, payload, native words, scalar) and a
// member row's field range goes to pj_g_aux.yz.
import integer_words;
import type_checker.operator_operand_rules;
import type_checker.intrinsic_operand_rules;
import type_checker.calls.intrinsic_result;
import type_checker.retention.projection.pj_types;
import type_checker.retention.projection.pj_schema;

static const uint STMT_LET = 1u;
static const uint STMT_RETURN = 2u;
static const uint STMT_IF = 3u;
static const uint STMT_ASSIGN = 5u;
static const uint STMT_WHILE = 6u;
static const uint EXPR_INT = 3u;
static const uint EXPR_FLOAT = 27u;
static const uint EXPR_STRING = 28u;
static const uint USE_DIRECT = 1u;
static const uint USE_RECORD = 3u;

struct Row
{
    uint rank;
    uint base;  // global row of the rank's function row
    uint row;
    uint g;
};

static bool failed;

void fail(Row at, uint code, uint detail)
{
    if (failed) return;
    failed = true;
    pj_row_fail(at.g, code, detail);
}

// The closed substituted type of relative row `row`, or RT_INVALID.
uint row_type(Row at, uint row)
{
    uint status;
    if (row == RT_INVALID || row >= pj_inf(at.rank, 1u).x) return RT_INVALID;
    if (!rt_is_resolved(pj_row(at.rank, row, 3u).x)) return RT_INVALID;
    uint t = pj_result(pj_req_row(at.rank, row), status);
    if (pj_row(at.rank, row, 6u).y == RT_CONST_SYMBOLIC && pj_row(at.rank, row, 0u).x != RT_HIR_TYPE)
        return rt_is_stored_term(t) && rt_term_kind(t) == RT_KIND_CC_VALUE ? rt_term_words(t).x : RT_INVALID;
    return t;
}

bool template_closed(Row at, uint row)
{
    return row != RT_INVALID && rt_term_closed(pj_row(at.rank, row, 3u).x);
}

// A closed runtime type with a complete lowering layout.
bool supported_type(Row at, uint t)
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

uint result_or_fail(Row at, uint request)
{
    uint status;
    uint t = pj_result(request, status);
    if (t == RT_INVALID) fail(at, status == 0xffffu ? PJ_E_PUBLICATION : PJ_E_SUBST, status);
    return t;
}

uint operand_class(uint t)
{
    if (!rt_is_term(t)) return OPR_TY_UNKNOWN;
    if (t < RT_FIRST_TERM) return scalar_is_known(t) ? t : OPR_TY_UNKNOWN;
    uint kind = rt_term_kind(t);
    if (kind == RT_KIND_NAMED) return OPR_TY_NAMED;
    if (kind == RT_KIND_ARRAY || kind == RT_KIND_SLICE) return OPR_TY_SEQUENCE;
    return OPR_TY_UNKNOWN;
}

bool null_literal(Row at, uint row)
{
    if (row == RT_INVALID) return false;
    uint4 p = pj_row(at.rank, row, 2u);
    return pj_row(at.rank, row, 0u).x == RT_HIR_LITERAL_EXPR && p.x == EXPR_INT && p.y == 0u && p.z == 0u;
}

void rule(Row at, uint code, uint detail) { fail(at, PJ_E_RULE, (code << 24u) | (detail & 0xffffffu)); }

// A value of type `value` stored where `expected` is required, when either
// side was symbolic in the template: the realized types must be equal (a
// null constant fits a pointer).
void check_destination(Row at, uint expected, uint value_row, bool changed)
{
    if (!changed || value_row == RT_INVALID) return;
    uint actual = row_type(at, value_row);
    if (actual == RT_INVALID || expected == RT_INVALID || actual == expected) return;
    if (expected == SCALAR_PTR && null_literal(at, value_row)) return;
    rule(at, PJ_RULE_ASSIGN_MISMATCH,
        operator_detail_code(operand_class(expected)) * 256u + operator_detail_code(operand_class(actual)));
}

// Whether literal `row`'s expression owner is a unary minus over it.
bool under_unary_minus(Row at, uint row)
{
    uint parent = pj_g_aux[at.base + row].x;
    if (parent == RT_INVALID || parent < at.base) return false;
    uint prow = parent - at.base;
    uint4 p = pj_row(at.rank, prow, 2u);
    return pj_row(at.rank, prow, 0u).x == RT_HIR_UNARY_EXPR && p.x == OPR_EXPR_NEG && p.y == row;
}

void check_literal(Row at, uint4 p, uint t, bool changed)
{
    if (!changed || t >= RT_FIRST_TERM) return;
    if (p.x == EXPR_INT)
    {
        // An integer literal in a pointer context keeps the i32 the
        // template gives it (06c_table_operands.slang).
        uint scalar = t == SCALAR_PTR ? SCALAR_I32 : t;
        if (!scalar_is_integer(scalar))
        {
            rule(at, PJ_RULE_ASSIGN_MISMATCH, operator_detail_code(t) * 256u + SCALAR_I32);
            return;
        }
        if (!integer_words_magnitude_fits(uint2(p.y, p.z), scalar, under_unary_minus(at, at.row)))
            rule(at, PJ_RULE_INTEGER_RANGE, scalar);
    }
    else if (p.x == EXPR_FLOAT)
    {
        if (!scalar_is_float(t))
        {
            rule(at, PJ_RULE_ASSIGN_MISMATCH, operator_detail_code(t) * 256u + SCALAR_F32);
            return;
        }
        // The f32 rounding of a finite literal overflows: its f32 word is
        // infinite while its f64 words are finite. (The frontend's other
        // literal statuses are not retained.)
        bool f32_infinite = (p.y & 0x7fffffffu) == 0x7f800000u;
        bool f64_finite = (p.w & 0x7ff00000u) != 0x7ff00000u;
        if (t == SCALAR_F32 && f32_infinite && f64_finite)
            rule(at, PJ_RULE_FLOAT_LITERAL, (t << 8u) | 1u);
    }
}

// Intrinsics have no declaration signature. Their accepted result is
// checked above, and their primitive contract is checked after substitution.
void check_intrinsic(Row at, uint4 p, uint t, uint tag)
{
    uint arity = tag == 11u ? 4u : (tag == 4u || tag == 7u || tag == 16u) ? 2u : 1u;
    if (tag == 0u || tag > 16u || p.z != arity)
    {
        fail(at, PJ_E_USE, tag);
        return;
    }
    if (tag == 4u || intrinsic_typed_view(tag))
    {
        if (!rt_is_stored_term(t) || rt_term_kind(t) != RT_KIND_SLICE ||
            (tag == 4u && rt_term_arg(t,0u) != SCALAR_I32) ||
            pj_words(rt_term_arg(t,0u)) == RT_INVALID)
        { fail(at,PJ_E_SIGNATURE,tag); return; }
    }
    else if (t != intrinsic_result_type(tag))
    { fail(at,PJ_E_SIGNATURE,tag); return; }

    for (uint k = 0u; k < arity; k++)
    {
        uint value = pj_side(at.rank,PJ_SIDE_CALL_ARGS,p.y+k,0u).y;
        uint actual = row_type(at,value);
        if (actual == SCALAR_NEVER) continue;
        uint scalar = actual < RT_FIRST_TERM ? actual : 0u;
        uint kind = rt_is_stored_term(actual) ? rt_term_kind(actual) : 0u;
        bool sequence = kind == RT_KIND_ARRAY || kind == RT_KIND_SLICE;
        uint detail = 0u;
        bool wrong = false;
        if (tag == 1u || tag == 9u || tag == 10u || intrinsic_is_bit_cast(tag))
            wrong = intrinsic_fixed_argument_violation(tag,scalar,sequence,detail);
        else if (tag == 3u || tag == 5u || tag == 8u)
        {
            wrong = !sequence;
            detail = LENGTH_ARGUMENT_TYPE | scalar;
        }
        else if (tag == 6u)
        {
            wrong = scalar != SCALAR_STR;
            detail = LENGTH_ARGUMENT_TYPE | 0x100u | scalar;
        }
        else if (tag == 4u || tag == 7u || tag == 16u || tag == 11u)
        {
            bool pointer = tag == 11u || k == 0u;
            wrong = pointer ? (scalar != SCALAR_PTR && !(null_literal(at,value) && (tag != 11u || k != 0u)))
                : !scalar_is_integer(scalar);
            detail = (pointer ? SCALAR_PTR : SCALAR_I32) * 256u + scalar;
        }
        // assert keeps the existing truth-test contract. Its original
        // frontend accepts the argument and its arity is checked above.
        if (wrong)
        {
            Row operand = at; operand.row = value; operand.g = at.base + value;
            rule(operand,PJ_RULE_ASSIGN_MISMATCH,detail);
            return;
        }
    }
}

// The instance-routed call at `at` (use `use`).
void check_call(Row at, uint4 p, uint t, uint use)
{
    uint4 u0 = pj_use(at.rank, use, 0u);
    uint form = u0.z & 0xffu;
    if ((form != USE_DIRECT && form != 5u) || ((u0.z >> 8u) & 0xffffu) != 0u)
    {
        fail(at, PJ_E_USE, u0.z);
        return;
    }
    // The use result is the accepted call result (export/14_uses: only a
    // unit or never call may take its row's term). It must be resolved: a
    // term, or a bare type parameter of the caller such as the `T` of
    // `keep(v)` in a body generic over T. Substituted under the instance
    // ENV, it must equal the row's type.
    if (!rt_is_resolved(pj_use(at.rank, use, 1u).y))
    {
        fail(at, PJ_E_USE, 0xfffeu);
        return;
    }
    uint accepted = result_or_fail(at, pj_req_use_result(at.rank, use));
    if (failed) return;
    if (accepted != t)
    {
        fail(at, PJ_E_SIGNATURE, 0xfffdu);
        return;
    }
    uint4 q1 = pj_instances[at.rank * PJ_INSTANCE_WORDS + 1u];
    uint4 route = pj_routes[q1.x + use];
    if (route.w != rt_counts[RT_C_GENERATION])
    {
        fail(at, PJ_E_ROUTE, 0u);
        return;
    }
    uint args = p.z;
    uint count = pj_side_len(at.rank,PJ_SIDE_CALL_ARGS);
    if (p.y > count || args > count - p.y)
    { fail(at,PJ_E_INCOMPLETE,args); return; }
    if (form == 5u)
    {
        if (route.x != PJ_ROUTE_NONE) { fail(at,PJ_E_ROUTE,3u); return; }
        check_intrinsic(at,p,t,pj_use(at.rank,use,2u).x);
        return;
    }
    if (route.x == PJ_NATIVE_LIBRARY && route.y == PJ_NATIVE_NS_INSTANCE)
    {
        uint target = route.z;
        uint env = result_or_fail(at, pj_req_use_env(at.rank, use));
        if (failed) return;
        if (target >= pj_instance_count() || pj_instances[target * PJ_INSTANCE_WORDS].x != u0.w ||
            pj_instances[target * PJ_INSTANCE_WORDS].y != env || pj_errors[target].x != 0u)
        {
            fail(at, PJ_E_ROUTE, 1u);
            return;
        }
        if (pj_inf(target, 1u).z != args)
        {
            fail(at, PJ_E_SIGNATURE, args);
            return;
        }
        uint result = result_or_fail(at, pj_req_result(target));
        if (failed) return;
        if (result != t)
        {
            fail(at, PJ_E_SIGNATURE, 0xffffu);
            return;
        }
        for (uint k = 0u; k < args; k++)
        {
            uint value = pj_side(at.rank, PJ_SIDE_CALL_ARGS, p.y + k, 0u).y;
            uint expected = result_or_fail(at, pj_req_param(target, k));
            if (failed) return;
            if (!pj_argument_compatible(expected, row_type(at, value), pj_row(at.rank, value, 6u).x & 0xffu))
            {
                fail(at, PJ_E_SIGNATURE, k);
                return;
            }
        }
        return;
    }
    // An ordinary native callee: its own declaration key and closed
    // signature.
    uint4 key = rt_decl_key[u0.w];
    uint entry = pj_dir_entry(u0.w);
    if (entry == RT_INVALID || any(route.xyz != uint3(key.x, key.y, key.w)))
    {
        fail(at, PJ_E_ROUTE, 2u);
        return;
    }
    uint4 d1 = rt_dir[entry * RT_DIR_WORDS + 1u];
    if (d1.y != 0u || d1.w != args || rt_sigs[d1.z] != t)
    {
        fail(at, PJ_E_SIGNATURE, 0xfffeu);
        return;
    }
    for (uint k = 0u; k < args; k++)
    {
        uint value = pj_side(at.rank, PJ_SIDE_CALL_ARGS, p.y + k, 0u).y;
        if (!pj_argument_compatible(rt_sigs[d1.z + 1u + k], row_type(at, value), pj_row(at.rank, value, 6u).x & 0xffu))
        {
            fail(at, PJ_E_SIGNATURE, k);
            return;
        }
    }
}

// Struct `t`'s field of declaration ordinal `ordinal`: its closed type,
// native word offset and words.
uint3 struct_field(uint t, uint ordinal)
{
    uint decl = rt_term_words(t).x;
    uint entry = pj_dir_entry(decl);
    if (entry == RT_INVALID) return uint3(RT_INVALID, RT_INVALID, RT_INVALID);
    uint4 d1 = rt_dir[entry * RT_DIR_WORDS + 1u];
    uint4 d2 = rt_dir[entry * RT_DIR_WORDS + 2u];
    uint types = d1.y & 0xffffu;
    uint offset = 0u;
    uint3 found = uint3(RT_INVALID, RT_INVALID, RT_INVALID);
    for (uint k = 0u; k < d2.z; k++)
    {
        uint4 record = rt_schema[d2.y + k];
        if ((record.y & 0xffu) != RT_SCHEMA_FIELD) continue;
        uint field = pj_schema_type(t,k);
        uint words = pj_words(field);
        uint o = record.y >> 8u;
        if (o == ordinal) found = uint3(field, 0u, words);
        else if (o < ordinal) offset += words;
    }
    if (found.x != RT_INVALID) found.y = offset;
    return found;
}

void check_struct_literal(Row at, uint4 p, uint t, uint use)
{
    uint4 u0 = pj_use(at.rank, use, 0u);
    uint4 q1 = pj_instances[at.rank * PJ_INSTANCE_WORDS + 1u];
    uint4 route = pj_routes[q1.x + use];
    if ((u0.z & 0xffu) != USE_RECORD || route.x != PJ_ROUTE_NONE || route.w != rt_counts[RT_C_GENERATION])
    {
        fail(at, PJ_E_USE, u0.z);
        return;
    }
    if (t < RT_FIRST_TERM || p.z != pj_layout[t].z)
    {
        fail(at, PJ_E_FIELD, p.z);
        return;
    }
    for (uint k = 0u; k < p.z; k++)
    {
        uint4 record = pj_side(at.rank, PJ_SIDE_FIELDS, p.y + k, 0u);
        uint ordinal = pj_side(at.rank, PJ_SIDE_FIELDS, p.y + k, 1u).x;
        uint3 field = struct_field(t, ordinal);
        if (field.x == RT_INVALID || row_type(at, record.z) != field.x)
        {
            fail(at, PJ_E_FIELD, ordinal);
            return;
        }
    }
}

void check_member(Row at, uint4 p, uint t, uint ordinal)
{
    uint receiver = pj_referent(row_type(at, p.y));
    if (receiver == RT_INVALID || receiver < RT_FIRST_TERM || rt_term_kind(receiver) != RT_KIND_NAMED)
    {
        fail(at, PJ_E_FIELD, 0xffffu);
        return;
    }
    uint3 field = struct_field(receiver, ordinal);
    if (field.x == RT_INVALID || field.x != t)
    {
        fail(at, PJ_E_FIELD, ordinal);
        return;
    }
    pj_g_aux[at.g].y = field.y;
    pj_g_aux[at.g].z = field.z;
}

bool supported_form(uint kind, uint4 p)
{
    if (kind == RT_HIR_PARAM || kind == RT_HIR_TYPE || kind == RT_HIR_BLOCK || kind == RT_HIR_LET_STMT ||
        kind == RT_HIR_RETURN_STMT || kind == RT_HIR_IF_STMT || kind == RT_HIR_WHILE_STMT ||
        kind == RT_HIR_BREAK_STMT || kind == RT_HIR_CONTINUE_STMT || kind == RT_HIR_BINARY_EXPR ||
        kind == RT_HIR_UNARY_EXPR || kind == RT_HIR_CALL_EXPR || kind == RT_HIR_MEMBER_EXPR ||
        kind == RT_HIR_NAME_EXPR || kind == RT_HIR_STRUCT_LITERAL_EXPR || kind == RT_HIR_PATH_EXPR ||
        kind == RT_HIR_ASSIGN_EXPR || kind == RT_HIR_INDEX_EXPR || kind == RT_HIR_FOR_STMT)
        return true;
    if (kind == RT_HIR_ARRAY_EXPR) return p.x == RT_INVALID || p.x == 37u || p.x == 38u;
    if (kind == RT_HIR_STMT)
        return p.x == STMT_LET || p.x == 4u || p.x == STMT_RETURN || p.x == STMT_IF || p.x == STMT_ASSIGN ||
            p.x == STMT_WHILE || p.x == 7u || p.x == 0u;
    if (kind == RT_HIR_LITERAL_EXPR) return true;
    if (kind == RT_HIR_EXPR) return p.x != EXPR_STRING;
    return false;
}

void check_signature(Row at)
{
    uint4 i1 = pj_inf(at.rank, 1u);
    uint result = result_or_fail(at, pj_req_result(at.rank));
    if (failed) return;
    if (result != SCALAR_UNIT && !supported_type(at, result)) return;
    for (uint k = 0u; k < i1.z; k++)
    {
        uint param = result_or_fail(at, pj_req_param(at.rank, k));
        if (failed || !supported_type(at, param)) return;
    }
    pj_g_facts[at.g] = uint4(PJ_REF_SCALAR, SCALAR_BOOL, 0u, 0u);
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    failed = false;
    uint g = pj_lane(dtid);
    uint n = pj_instance_count();
    if (g >= pj_total(PJ_C_ROWS)) return;
    Row at;
    at.rank = pj_rank_of(PJ_C_ROWS, g, 0u, n);
    at.base = pj_base_at(at.rank, PJ_C_ROWS);
    at.row = g - at.base;
    at.g = g;
    if (pj_errors[at.rank].x != 0u) return;
    uint4 r0 = pj_row(at.rank, at.row, 0u);
    uint4 p = pj_row(at.rank, at.row, 2u);
    uint4 r3 = pj_row(at.rank, at.row, 3u);
    uint4 r4 = pj_row(at.rank, at.row, 4u);
    uint4 r5 = pj_row(at.rank, at.row, 5u);
    uint4 r6 = pj_row(at.rank, at.row, 6u);
    uint kind = r0.x;
    if (at.row == 0u)
    {
        if (kind != RT_HIR_FN) fail(at, PJ_E_FORM, kind);
        else check_signature(at);
        return;
    }
    if (r3.z == RT_ROLE_BOUND)
    {
        uint4 info = pj_inf(at.rank,0u);
        uint4 block = rt_dir_trait[info.z];
        if ((pj_readiness[0u].y & PJ_READY_PROOFS) == 0u || r3.y >= block.y)
            fail(at,PJ_E_ROLE,r3.z);
        else
        {
            uint4 predicate = rt_traits[(block.x+r3.y)*RT_TRAIT_WORDS];
            if (predicate.x != info.x || predicate.y != (RT_TRAIT_PREDICATE | (r3.y << 8u))) fail(at,PJ_E_ROLE,r3.z);
        }
        return;
    }
    if (r3.z == RT_ROLE_PATTERN)
    {
        fail(at, PJ_E_ROLE, r3.z);
        return;
    }
    if ((r3.w & 6u) != 0u || r5.x == RT_BIND_FOREIGN)
    {
        fail(at, PJ_E_INCOMPLETE, r3.w);
        return;
    }
    if (!supported_form(kind, p) || (r4.w != 0u && kind != RT_HIR_ARRAY_EXPR) ||
        (r6.y != 0u && r6.y != RT_CONST_CONCRETE && r6.y != RT_CONST_SYMBOLIC && kind != RT_HIR_TYPE) ||
        (((r6.x >> 8u) & 0xffu) != 0u && kind != RT_HIR_FOR_STMT && !(kind == RT_HIR_STMT && p.x == 7u)) ||
        (r5.x == RT_BIND_PARAM && kind != RT_HIR_TYPE &&
            (!rt_is_param_leaf(r5.y) || (r5.y & RT_CONST_BIT) == 0u || r6.y != RT_CONST_SYMBOLIC)) || r5.x == RT_BIND_VARIANT ||
        (r5.x == RT_BIND_DECL && r3.z != RT_ROLE_CALLEE))
    {
        fail(at, PJ_E_FORM, kind | (p.x << 8u));
        return;
    }
    uint t = RT_INVALID;
    if (rt_is_resolved(r3.x))
    {
        t = result_or_fail(at, pj_req_row(at.rank, at.row));
        if (failed) return;
        if (r6.y == RT_CONST_SYMBOLIC && kind != RT_HIR_TYPE)
        {
            if (!rt_is_stored_term(t) || rt_term_kind(t) != RT_KIND_CC_VALUE || rt_term_words(t).x != r3.x)
            {
                fail(at, PJ_E_TYPE, t);
                return;
            }
            t = rt_term_words(t).x;
        }
        // An array annotation's count row is a constant operand, not a
        // runtime value. The enclosing array term owns its evaluated count.
        if (kind == RT_HIR_TYPE && rt_is_stored_term(t) &&
            (rt_term_kind(t) == RT_KIND_CC_COUNT || rt_term_kind(t) == RT_KIND_CC_VALUE)) return;
        if (!supported_type(at, t)) return;
        uint2 ref = pj_ref_of(t);
        pj_g_facts[g] = uint4(ref, pj_words(t), t < RT_FIRST_TERM ? t : 0u);
    }
    bool changed = rt_is_resolved(r3.x) && !rt_term_closed(r3.x);

    // Each element value validates its own array slot. The expression-parent
    // edge was published from that element's side record in step 4b.
    uint parent = pj_g_aux[g].x;
    bool array_operand = parent != RT_INVALID && parent >= at.base &&
        pj_row(at.rank, parent - at.base, 0u).x == RT_HIR_ARRAY_EXPR;
    if (array_operand)
    {
        uint4 array = pj_row(at.rank, parent - at.base, 2u);
        if ((array.x == 37u || array.x == 38u) && array.y == at.row) array_operand = false;
    }
    if (array_operand)
    {
        uint container = row_type(at, parent - at.base);
        if (!rt_is_stored_term(container) || rt_term_kind(container) != RT_KIND_ARRAY ||
            rt_term_arg(container, 0u) != t)
        {
            fail(at, PJ_E_SIGNATURE, 0xfffcu);
            return;
        }
    }
    if (kind == RT_HIR_ARRAY_EXPR)
    {
        uint count = pj_array_count(t);
        // Zero-repeat retains its literal element in HIR; lowering emits
        // a zero fill instead of evaluating that element.
        uint elements = p.x == 37u || p.x == 38u ? 1u : count;
        if (count == RT_INVALID || elements != r4.w ||
            (r4.w != 0u && (r4.z > pj_side_len(at.rank, PJ_SIDE_ARRAY_ELEMENTS) ||
             r4.w > pj_side_len(at.rank, PJ_SIDE_ARRAY_ELEMENTS) - r4.z)))
            fail(at, PJ_E_FORM, kind | (p.x << 8u));
    }
    else if (kind == RT_HIR_FOR_STMT || (kind == RT_HIR_STMT && p.x == 7u))
    {
        if (p.z >= pj_inf(at.rank,1u).x || !rt_is_term(t))
        { fail(at,PJ_E_INCOMPLETE,p.z); return; }
        uint source_kind = pj_row(at.rank,p.z,0u).x;
        uint4 source = pj_row(at.rank,p.z,2u);
        uint iterable = (r6.x >> 8u) & 0xffu;
        bool range = (source_kind == RT_HIR_EXPR || source_kind == RT_HIR_BINARY_EXPR) &&
            source.x >= 30u && source.x <= 35u;
        if (range)
        {
            bool left = source.x == 30u || source.x == 31u || source.x == 34u;
            bool right = source.x == 30u || source.x == 32u || source.x == 34u || source.x == 35u;
            if (iterable != 0u || !scalar_is_integer(t) ||
                (left && row_type(at,source.y) != t) || (right && row_type(at,source.z) != t))
                fail(at,PJ_E_SIGNATURE,7u);
        }
        else
        {
            uint container = row_type(at,p.z);
            uint container_kind = rt_is_stored_term(container) ? rt_term_kind(container) : 0u;
            if ((container_kind != RT_KIND_ARRAY && container_kind != RT_KIND_SLICE) ||
                rt_term_arg(container,0u) != t ||
                iterable != (container_kind == RT_KIND_ARRAY ? 3u : 0u))
                fail(at,PJ_E_SIGNATURE,7u);
        }
    }
    else if (kind == RT_HIR_INDEX_EXPR)
    {
        uint container = pj_referent(row_type(at, p.y));
        uint detail;
        if (!rt_is_stored_term(container) ||
            (rt_term_kind(container) != RT_KIND_ARRAY && rt_term_kind(container) != RT_KIND_SLICE))
            rule(at, PJ_RULE_ASSIGN_MISMATCH, 0u);
        else if (operator_index_violation(operand_class(row_type(at, p.z)), detail))
            rule(at, PJ_RULE_ASSIGN_MISMATCH, detail);
        else if (rt_term_arg(container, 0u) != t || pj_words(t) == RT_INVALID)
            fail(at, PJ_E_SIGNATURE, 0xfffbu);
    }

    else if (kind == RT_HIR_LITERAL_EXPR && p.x == EXPR_STRING)
    {
        if (t != SCALAR_STR || p.y >= pj_side_len(at.rank,PJ_SIDE_STRINGS))
            fail(at,PJ_E_FORM,kind | (p.x << 8u));
        else
        {
            uint4 record = pj_side(at.rank,PJ_SIDE_STRINGS,p.y,0u);
            uint words = (record.z + 4u) >> 2u;
            if (record.x != at.row || record.z >= 0xfffffffbu || record.y > rt_counts[RT_A_SEG_BYTES] ||
                words > rt_counts[RT_A_SEG_BYTES] - record.y)
                fail(at,PJ_E_INCOMPLETE,p.y);
        }
    }
    else if (kind == RT_HIR_LITERAL_EXPR || (kind == RT_HIR_EXPR && (p.x == EXPR_INT || p.x == EXPR_FLOAT)))
        check_literal(at, p, t, changed);
    else if (kind == RT_HIR_BINARY_EXPR)
    {
        bool symbolic = !template_closed(at, p.y) || !template_closed(at, p.z);
        uint detail;
        if (symbolic && operator_binary_violation(p.x, operand_class(row_type(at, p.y)),
            operand_class(row_type(at, p.z)), null_literal(at, p.y), null_literal(at, p.z), detail) != OPR_OPERAND_NONE)
            rule(at, PJ_RULE_ASSIGN_MISMATCH, detail);
    }
    else if (kind == RT_HIR_UNARY_EXPR)
    {
        uint detail;
        uint operand = operand_class(row_type(at, p.y));
        if (!template_closed(at, p.y))
        {
            if (p.x == OPR_EXPR_NEG && operator_negation_violation(operand, detail))
                rule(at, PJ_RULE_ASSIGN_MISMATCH, detail);
            else if (p.x == OPR_EXPR_NOT && operator_bool_violation(operand, detail))
                rule(at, PJ_RULE_ASSIGN_MISMATCH, detail);
        }
    }
    else if (kind == RT_HIR_IF_STMT || kind == RT_HIR_WHILE_STMT ||
        (kind == RT_HIR_STMT && (p.x == STMT_IF || p.x == STMT_WHILE)))
    {
        uint detail;
        if (!template_closed(at, p.y) && operator_bool_violation(operand_class(row_type(at, p.y)), detail))
            rule(at, PJ_RULE_ASSIGN_MISMATCH, detail);
    }
    else if (kind == RT_HIR_RETURN_STMT || (kind == RT_HIR_STMT && p.x == STMT_RETURN))
    {
        uint status;
        uint result = pj_result(pj_req_result(at.rank), status);
        bool symbolic = !rt_term_closed(rt_sigs[pj_inf(at.rank, 3u).w]) ||
            (p.y != RT_INVALID && !template_closed(at, p.y));
        check_destination(at, result, p.y, symbolic);
    }
    else if (kind == RT_HIR_LET_STMT || (kind == RT_HIR_STMT && p.x == STMT_LET))
        check_destination(at, t, p.z, changed || (p.z != RT_INVALID && !template_closed(at, p.z)));
    else if ((kind == RT_HIR_STMT || kind == RT_HIR_ASSIGN_EXPR) && p.x == STMT_ASSIGN)
        check_destination(at, row_type(at, p.y), p.z, !template_closed(at, p.y) || !template_closed(at, p.z));

    if (failed) return;
    uint use = r3.z != RT_ROLE_BOUND ? r3.y : RT_NONE;
    if (kind == RT_HIR_CALL_EXPR || kind == RT_HIR_STRUCT_LITERAL_EXPR)
    {
        if (use == RT_NONE || use >= pj_inf(at.rank, 1u).w)
        {
            fail(at, PJ_E_USE, 0xffffu);
            return;
        }
        if (kind == RT_HIR_CALL_EXPR) check_call(at, p, t, use);
        else check_struct_literal(at, p, t, use);
    }
    else if (use != RT_NONE)
        fail(at, PJ_E_USE, kind);
    else if (kind == RT_HIR_MEMBER_EXPR)
        check_member(at, p, t, r5.w);
}
