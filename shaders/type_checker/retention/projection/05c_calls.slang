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
import native_c_entry;
import type_checker.operator_operand_rules;
import type_checker.intrinsic_operand_rules;
import type_checker.calls.intrinsic_result;
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
void check_function_value(Row at, uint t, uint use)
{
    uint4 u0 = pj_use(at.rank,use,0u);
    uint4 r5 = pj_row(at.rank,at.row,5u);
    uint4 route = pj_routes[pj_instances[at.rank*PJ_INSTANCE_WORDS+1u].x+use];
    uint entry = pj_dir_entry(u0.w);
    if (entry == RT_INVALID || rt_dir[entry*RT_DIR_WORDS].y != 1u || u0.z != 8u ||
        r5.x != RT_BIND_DECL || r5.y != u0.w || t != SCALAR_PTR ||
        pj_use(at.rank,use,1u).y != t || pj_use(at.rank,use,1u).x != RT_NONE)
    { fail(at,PJ_E_USE,8u); return; }
    uint4 key = rt_decl_key[u0.w];
    if (any(route.xyz != uint3(key.x,key.y,key.w)) || route.w != rt_counts[RT_C_GENERATION])
    { fail(at,PJ_E_ROUTE,2u); return; }
    uint4 d1 = rt_dir[entry*RT_DIR_WORDS+1u];
    if (d1.y != 0u || d1.w > 6u || !native_c_entry_scalar(rt_sigs[d1.z],true))
    { fail(at,PJ_E_SIGNATURE,8u); return; }
    uint narrow = 0u;
    for (uint k = 0u; k < d1.w; k++)
    {
        uint param = rt_sigs[d1.z+1u+k];
        if (!native_c_entry_scalar(param,false)) { fail(at,PJ_E_SIGNATURE,k); return; }
        if (param == SCALAR_I32 || param == SCALAR_U32) narrow |= 1u << k;
    }
    pj_g_aux[at.g].y = narrow;
}

void check_call(Row at, uint4 p, uint t, uint use)
{
    uint4 u0 = pj_use(at.rank, use, 0u);
    uint form = u0.z & 0xffu;
    bool host = form == 6u;
    if ((form != USE_DIRECT && form != USE_METHOD && form != USE_CONSTRUCTOR && form != 5u && !host) ||
        (form != USE_METHOD && !host && (u0.z >> 8u) != 0u))
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
    if (args != 0u && (p.y > count || args > count - p.y))
    { fail(at,PJ_E_INCOMPLETE,args); return; }
    if (form == USE_CONSTRUCTOR)
    {
        uint entry = pj_dir_entry(u0.w);
        uint variant = pj_use(at.rank,use,2u).x;
        if (route.x != PJ_ROUTE_NONE || !rt_is_stored_term(t) || rt_term_kind(t) != RT_KIND_NAMED ||
            rt_term_words(t).x != u0.w || entry == RT_INVALID || rt_dir[entry*RT_DIR_WORDS].y != 6u)
        { fail(at,PJ_E_USE,form); return; }
        uint4 d1 = rt_dir[entry*RT_DIR_WORDS+1u];
        uint4 d2 = rt_dir[entry*RT_DIR_WORDS+2u];
        if (variant >= d1.w || variant >= d2.z)
        { fail(at,PJ_E_FIELD,variant); return; }
        uint4 v = rt_schema[d2.y+variant];
        if (v.x != u0.w || v.y != (RT_SCHEMA_VARIANT | (variant << 8u)) || v.z != args ||
            v.w > d2.z || v.z > d2.z-v.w)
        { fail(at,PJ_E_SIGNATURE,variant); return; }
        for (uint k = 0u; k < args; k++)
        {
            uint value = pj_side(at.rank,PJ_SIDE_CALL_ARGS,p.y+k,0u).y;
            if (value >= pj_inf(at.rank,1u).x || !pj_argument_compatible(pj_schema_type(t,v.w+k),
                row_type(at,value),pj_row(at.rank,value,6u).x & 0xffu))
            { fail(at,PJ_E_SIGNATURE,k); return; }
        }
        return;
    }
    if (form == 5u)
    {
        if (route.x != PJ_ROUTE_NONE) { fail(at,PJ_E_ROUTE,3u); return; }
        check_intrinsic(at,p,t,pj_use(at.rank,use,2u).x);
        return;
    }
    bool method = form == USE_METHOD || (host && (u0.z >> 8u) != 0u);
    uint receiver = RT_INVALID;
    if (method)
    {
        if (p.x >= pj_inf(at.rank,1u).x || pj_row(at.rank,p.x,0u).x != RT_HIR_MEMBER_EXPR)
        { fail(at,PJ_E_USE,0xfffcu); return; }
        uint source = pj_row(at.rank,p.x,2u).y;
        uint actual = row_type(at,source);
        uint matched = result_or_fail(at,pj_req_use_matched(at.rank,use));
        receiver = result_or_fail(at,pj_req_use_receiver(at.rank,use));
        if (failed) return;
        uint derefs = u0.z >> 16u;
        for (uint d = 0u; d < min(derefs,64u); d++)
        {
            if (!rt_is_stored_term(actual) || rt_term_kind(actual) != RT_KIND_REF)
            { fail(at,PJ_E_SIGNATURE,0xfff9u); return; }
            actual = rt_term_arg(actual,0u);
        }
        uint adjustment = (u0.z >> 8u) & 0xffu;
        if (derefs > 64u || actual != matched ||
            (adjustment == 1u ? receiver != matched : adjustment != 2u ||
                !rt_is_stored_term(receiver) || rt_term_kind(receiver) != RT_KIND_REF || rt_term_arg(receiver,0u) != matched))
        { fail(at,PJ_E_SIGNATURE,0xfff8u); return; }
        if (!supported_type(at,receiver) || !supported_type(at,matched)) return;
        args++;
    }
    uint callee=u0.w;
    uint declared=pj_dir_entry(callee);
    bool bound=declared!=RT_INVALID && rt_dir[declared*RT_DIR_WORDS].y==3u;
    uint2 selected=uint2(callee,RT_NONE);
    if (bound)
    {
        uint capacity; uint stride; pj_targets.GetDimensions(capacity,stride);
        if ((pj_readiness[0].y&4u)==0u || q1.x+use>=capacity) { fail(at,PJ_E_ROUTE,4u); return; }
        selected=pj_targets[q1.x+use]; callee=selected.x;
        uint entry=pj_dir_entry(callee);
        if (entry==RT_INVALID || rt_dir[entry*RT_DIR_WORDS].y!=2u || !rt_is_stored_term(selected.y) ||
            rt_term_kind(selected.y)!=RT_KIND_ENV || !rt_term_closed(selected.y) || rt_term_words(selected.y).x!=callee)
        { fail(at,PJ_E_ROUTE,5u); return; }
    }
    if (route.x == PJ_NATIVE_LIBRARY && route.y == PJ_NATIVE_NS_INSTANCE)
    {
        uint target = route.z;
        uint env = bound ? selected.y : result_or_fail(at, pj_req_use_env(at.rank, use));
        if (failed) return;
        if (target >= pj_instance_count() || pj_instances[target * PJ_INSTANCE_WORDS].x != callee ||
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
            uint value = method && k == 0u ? RT_INVALID : pj_side(at.rank, PJ_SIDE_CALL_ARGS, p.y + k - (method ? 1u : 0u), 0u).y;
            uint expected = result_or_fail(at, pj_req_param(target, k));
            if (failed) return;
            if (!pj_argument_compatible(expected, method && k == 0u ? receiver : row_type(at,value),
                method && k == 0u ? 0u : pj_row(at.rank,value,6u).x & 0xffu))
            {
                fail(at, PJ_E_SIGNATURE, k);
                return;
            }
        }
        return;
    }
    // An ordinary native callee: its own declaration key and closed
    // signature.
    uint4 key = rt_decl_key[callee];
    uint entry = pj_dir_entry(callee);
    if (entry == RT_INVALID || any(route.xyz != uint3(key.x, key.y, key.w)))
    {
        fail(at, PJ_E_ROUTE, 2u);
        return;
    }
    uint4 d1 = rt_dir[entry * RT_DIR_WORDS + 1u];
    if (host)
    {
        uint service = pj_use(at.rank,use,2u).x;
        // These are the semantic artifact's host-service slots. Slot 52
        // and 63..73 are language intrinsics/types, never host calls.
        if (rt_dir[entry*RT_DIR_WORDS].y != 4u ||
            !((service >= 20u && service <= 62u && service != 52u) || service == 74u))
        { fail(at,PJ_E_USE,service); return; }
    }
    if (d1.y != 0u || d1.w != args || rt_sigs[d1.z] != t)
    {
        fail(at, PJ_E_SIGNATURE, 0xfffeu);
        return;
    }
    for (uint k = 0u; k < args; k++)
    {
        uint value = method && k == 0u ? RT_INVALID : pj_side(at.rank, PJ_SIDE_CALL_ARGS, p.y + k - (method ? 1u : 0u), 0u).y;
        if (!pj_argument_compatible(rt_sigs[d1.z + 1u + k], method && k == 0u ? receiver : row_type(at,value),
            method && k == 0u ? 0u : pj_row(at.rank,value,6u).x & 0xffu))
        {
            fail(at, PJ_E_SIGNATURE, k);
            return;
        }
    }
}


[shader("compute")]
[numthreads(256,1,1)]
void main(uint3 dtid:SV_DispatchThreadID)
{
    uint g = pj_lane(dtid);
    if (g >= pj_total(PJ_C_ROWS) || pj_row_errors[g].x != 0u) return;
    Row at;
    at.g = g; at.rank = pj_rank_of(PJ_C_ROWS,g,0u,pj_instance_count());
    at.base = pj_base_at(at.rank,PJ_C_ROWS); at.row = g-at.base;
    uint kind = pj_row(at.rank,at.row,0u).x;
    uint4 r3 = pj_row(at.rank,at.row,3u);
    if (r3.z == RT_ROLE_BOUND || pj_g_aux[g].w != 0u || r3.y == RT_NONE) return;
    if (kind != RT_HIR_CALL_EXPR && kind != RT_HIR_NAME_EXPR && kind != RT_HIR_PATH_EXPR) return;
    if (r3.y >= pj_inf(at.rank,1u).w) return;
    failed = false;
    if ((pj_use(at.rank,r3.y,0u).z & 0xffu) == 8u)
    {
        check_function_value(at,row_type(at,at.row),r3.y);
        return;
    }
    check_call(at,kind == RT_HIR_CALL_EXPR ? pj_row(at.rank,at.row,2u) : uint4(0u,0u,0u,0u),
        row_type(at,at.row),r3.y);
}
