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
import type_checker.float_literal_selection;
import type_checker.operator_operand_rules;
import type_checker.retention.projection.pj_types;
import type_checker.retention.projection.pj_schema;
import type_checker.retention.projection.pj_patterns;

static const uint STMT_LET = 1u;
static const uint STMT_RETURN = 2u;
static const uint STMT_IF = 3u;
static const uint STMT_ASSIGN = 5u;
static const uint STMT_WHILE = 6u;
static const uint EXPR_INT = 3u;
static const uint EXPR_FLOAT = 27u;
static const uint EXPR_STRING = 28u;
static const uint USE_DIRECT = 1u;
static const uint USE_METHOD = 2u;
static const uint USE_RECORD = 3u;
static const uint USE_CONSTRUCTOR = 4u;

import type_checker.retention.projection.pj_validation;

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
        uint status;
        uint packed = pj_row(at.rank, at.row, 6u).x >> 16u;
        if (selected_float_literal_status(packed, t, status) && status != 0u)
            rule(at, PJ_RULE_FLOAT_LITERAL, (t << 8u) | status);
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
        kind == RT_HIR_ASSIGN_EXPR || kind == RT_HIR_INDEX_EXPR || kind == RT_HIR_FOR_STMT ||
        kind == RT_HIR_MATCH_EXPR || kind == RT_HIR_TRY_EXPR)
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
    uint pattern_type = pj_g_aux[g].w;
    bool pattern = pattern_type != 0u;
    if (r3.z == RT_ROLE_PATTERN && !pattern)
    {
        fail(at, PJ_E_ROLE, r3.z);
        return;
    }
    if ((r3.w & 6u) != 0u || r5.x == RT_BIND_FOREIGN)
    {
        fail(at, PJ_E_INCOMPLETE, r3.w);
        return;
    }
    bool function_value = (kind == RT_HIR_NAME_EXPR || kind == RT_HIR_PATH_EXPR) &&
        r3.z != RT_ROLE_BOUND && r3.y != RT_NONE && r3.y < pj_inf(at.rank,1u).w &&
        (pj_use(at.rank,r3.y,0u).z & 0xffu) == 8u;
    if (!supported_form(kind, p) || (r4.w != 0u && kind != RT_HIR_ARRAY_EXPR) ||
        (r6.y != 0u && r6.y != RT_CONST_CONCRETE && r6.y != RT_CONST_SYMBOLIC && r6.y != RT_CONST_VARIANT && kind != RT_HIR_TYPE) ||
        (((r6.x >> 8u) & 0xffu) != 0u && kind != RT_HIR_FOR_STMT && !(kind == RT_HIR_STMT && p.x == 7u)) ||
        (r5.x == RT_BIND_PARAM && kind != RT_HIR_TYPE &&
            (!rt_is_param_leaf(r5.y) || (r5.y & RT_CONST_BIT) == 0u || r6.y != RT_CONST_SYMBOLIC)) ||
        (r5.x == RT_BIND_VARIANT && !pattern && r3.z != RT_ROLE_CALLEE && r3.y == RT_NONE) ||
        (r5.x == RT_BIND_DECL && r3.z != RT_ROLE_CALLEE && r6.y != RT_CONST_CONCRETE && !function_value))
    {
        fail(at, PJ_E_FORM, kind | (p.x << 8u));
        return;
    }
    uint t = RT_INVALID;
    if (pattern)
    {
        if (!supported_type(at,pattern_type)) return;
        uint variant = pj_pattern_variant(at.rank,at.row);
        uint children = pj_g_facts[g].w;
        if (variant != RT_INVALID)
        {
            uint4 schema = pj_variant_schema(pattern_type,variant);
            if (schema.x == RT_INVALID || schema.z != children ||
                (r5.x == RT_BIND_VARIANT && r5.y != schema.x))
            { fail(at,PJ_E_FIELD,variant); return; }
        }
        else if (children != 0u || (kind != RT_HIR_LITERAL_EXPR && r5.x != RT_BIND_LOCAL))
        { fail(at,PJ_E_ROLE,r3.z); return; }
    }
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
        if (pattern && pj_referent(t) != pattern_type)
        { fail(at,PJ_E_SIGNATURE,0xfffau); return; }
        if (pattern) t = pattern_type;
        if (!supported_type(at, t)) return;
        if (r5.x == RT_BIND_DECL && r3.z != RT_ROLE_CALLEE && !function_value)
        {
            // A folded constant name still names its declaration. Its
            // value and type must match that declaration's retained schema;
            // no declaration token is needed by native materialization.
            uint entry = pj_dir_entry(r5.y);
            if (entry == RT_INVALID || rt_dir[entry*RT_DIR_WORDS].y != 9u)
            { fail(at,PJ_E_DECL,r5.y); return; }
            uint4 d1 = rt_dir[entry*RT_DIR_WORDS+1u];
            uint4 d2 = rt_dir[entry*RT_DIR_WORDS+2u];
            if (d2.z != 1u || d1.z == RT_INVALID || rt_sigs[d1.z] != t ||
                any(rt_schema[d2.y] != uint4(r5.y,RT_SCHEMA_CONST | 0x100u,r6.zw)))
            { fail(at,PJ_E_SIGNATURE,r5.y); return; }
        }
        uint2 ref = pj_ref_of(t);
        pj_g_facts[g] = uint4(ref, pj_words(t), t < RT_FIRST_TERM ? t : 0u);
    }
    else if (pattern)
    {
        t = pattern_type;
        uint2 ref = pj_ref_of(t);
        pj_g_facts[g] = uint4(ref,pj_words(t),t < RT_FIRST_TERM ? t : 0u);
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
    if (kind == RT_HIR_TRY_EXPR)
    {
        uint operand = row_type(at,p.y);
        uint result = result_or_fail(at,pj_req_result(at.rank));
        if (failed) return;
        uint4 success = pj_variant_schema(operand,0u);
        uint4 failure = pj_variant_schema(operand,1u);
        uint4 returned = pj_variant_schema(result,1u);
        uint arity = rt_term_arity(operand);
        if (success.x == RT_INVALID || failure.x == RT_INVALID || returned.x != failure.x ||
            success.z != 1u || failure.z > 1u || returned.z != failure.z ||
            arity != 1u+failure.z || rt_term_arity(result) != arity ||
            pj_schema_type(operand,success.w) != t || rt_term_arg(operand,0u) != t ||
            (failure.z != 0u && (pj_schema_type(operand,failure.w) != pj_schema_type(result,returned.w) ||
                pj_schema_type(operand,failure.w) != rt_term_arg(operand,1u))))
        { fail(at,PJ_E_SIGNATURE,36u); return; }
    }
    else if (kind == RT_HIR_MATCH_EXPR)
    {
        uint arms = pj_side_len(at.rank,PJ_SIDE_MATCH_ARMS);
        if (p.x >= pj_inf(at.rank,1u).x || p.y > arms || p.z > arms-p.y)
        { fail(at,PJ_E_INCOMPLETE,p.y); return; }
        for (uint k = 0u; k < p.z; k++)
        {
            uint4 arm = pj_side(at.rank,PJ_SIDE_MATCH_ARMS,p.y+k,0u);
            uint result = row_type(at,arm.z);
            if (arm.x != at.row || arm.w != k || (result != t && result != SCALAR_NEVER))
            { fail(at,PJ_E_SIGNATURE,k); return; }
        }
    }
    else if (kind == RT_HIR_ARRAY_EXPR)
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
    if (pattern) return;
    uint use = r3.z != RT_ROLE_BOUND ? r3.y : RT_NONE;
    if (kind == RT_HIR_CALL_EXPR || kind == RT_HIR_STRUCT_LITERAL_EXPR)
    {
        if (use == RT_NONE || use >= pj_inf(at.rank, 1u).w)
        {
            fail(at, PJ_E_USE, 0xffffu);
            return;
        }
        if (kind == RT_HIR_STRUCT_LITERAL_EXPR) check_struct_literal(at, p, t, use);
    }
    else if (use != RT_NONE)
    {
        if ((kind == RT_HIR_NAME_EXPR || kind == RT_HIR_PATH_EXPR) && use < pj_inf(at.rank,1u).w &&
            ((pj_use(at.rank,use,0u).z & 0xffu) == USE_CONSTRUCTOR || function_value))
            return; // Constructor call validation follows in 05c.
        else fail(at, PJ_E_USE, kind);
    }
    else if (kind == RT_HIR_MEMBER_EXPR && r3.z != RT_ROLE_CALLEE)
        check_member(at, p, t, r5.w);
}
