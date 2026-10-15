// HIR array-return projection.
//
// This pass consumes compact return statements and call arguments, visible-decl records,
// declaration type refs,
// and function return type refs. It publishes the array-return sentinel for `return values;` and
// bounded one-argument `return copy(values);` call results only when the returned declaration or
// declaration-backed call argument has the same bounded array instance as the
// enclosing function return type. It does not inspect token kinds, token
// spelling, source bytes, helper names, callee bodies, or expression
// punctuation.

import hir_records;
import type_checker.checked_array_counts;
import status;
import type_checker.checked_type_graph;
import type_checker.canonical.canonical_api;
import type_checker.canonical.canonical_checked_rows;
import type_checker.substitution.ct_checked;

struct Params
{
    uint n_tokens;
    uint source_len;
    uint n_hir_nodes;
};

ConstantBuffer<Params> gParams;


StructuredBuffer<uint> visible_decl;
StructuredBuffer<uint> decl_type_ref_tag;
StructuredBuffer<uint> decl_type_ref_payload;
StructuredBuffer<uint> fn_return_ref_tag;
StructuredBuffer<uint> fn_return_ref_payload;
StructuredBuffer<uint> enclosing_fn;
StructuredBuffer<uint> compact_hir_count;
StructuredBuffer<HirCore> compact_hir_core;
StructuredBuffer<HirPayload> compact_hir_payload;
StructuredBuffer<uint> compact_call_arg_count;
StructuredBuffer<HirCallArg> compact_call_args;

RWStructuredBuffer<uint> call_return_type;
RWStructuredBuffer<uint> status;

static const uint INVALID = 0xffffffffu;
static const uint ARRAY_RETURN_OK = 0xfffffffeu;
static const uint ERR_ASSIGN_MISMATCH = 3u;

static const uint HIR_RETURN_STMT = 9u;
static const uint HIR_CALL_EXPR = 19u;
static const uint HIR_NAME_EXPR = 22u;

static const uint STMT_RECORD_KIND_RETURN = 2u;

static const uint TYPE_REF_INSTANCE = 3u;
static const uint TYPE_REF_SCALAR = 1u;
static const uint TYPE_REF_GENERIC_PARAM = 2u;
static const uint TYPE_INSTANCE_ARRAY = 2u;

static const uint TY_ARRAY_BASE = 128u;
static const uint TY_STRUCT_BASE = 4096u;
static const uint TY_GENERIC_BASE = 8192u;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

uint linear_thread_id(uint3 dtid)
{
    return dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE;
}

bool valid_token(uint token)
{
    return token != INVALID && token < gParams.n_tokens;
}

uint enclosing_function_decl_token(uint token)
{
    uint encoded_fn = valid_token(token) ? enclosing_fn[token] : 0u;
    uint fn_node = encoded_fn == 0u ? INVALID : encoded_fn - 1u;
    uint count = min(compact_hir_count[0u], gParams.n_hir_nodes);
    if (fn_node == INVALID || fn_node >= count)
        return INVALID;
    uint fn_token = compact_hir_payload[fn_node].b;
    return valid_token(fn_token) ? fn_token : INVALID;
}

uint active_compact_hir_count()
{
    return min(compact_hir_count[0u], gParams.n_hir_nodes);
}

HirPayload stmt_payload(uint node)
{
    HirPayload payload;
    payload.a = 0u;
    payload.b = INVALID;
    payload.c = INVALID;
    payload.d = INVALID;
    return node < active_compact_hir_count() ? compact_hir_payload[node] : payload;
}

uint name_token_for_expr(uint node)
{
    if (node >= active_compact_hir_count() || compact_hir_core[node].kind != HIR_NAME_EXPR)
        return INVALID;
    uint token = compact_hir_payload[node].d;
    return valid_token(token) ? token : compact_hir_core[node].token_start;
}

uint bounded_array_instance_from_ref(uint tag, uint payload)
{
    if (tag != TYPE_REF_INSTANCE || payload >= checked_type_capacity())
        return INVALID;
    if (type_instance_kind[payload] != TYPE_INSTANCE_ARRAY)
        return INVALID;
    if (!checked_source_array_length_valid(type_instance_len_kind[payload],
        type_instance_len_payload[payload], gParams.n_tokens))
        return INVALID;
    return payload;
}

uint function_return_array_instance(uint return_node)
{
    uint return_token = return_node < active_compact_hir_count()
        ? compact_hir_core[return_node].token_start
        : INVALID;
    if (!valid_token(return_token))
        return INVALID;

    uint fn_token = enclosing_function_decl_token(return_token);
    if (!valid_token(fn_token))
        return INVALID;

    return bounded_array_instance_from_ref(
        fn_return_ref_tag[fn_token],
        fn_return_ref_payload[fn_token]);
}

uint declaration_array_instance(uint value_token)
{
    if (!valid_token(value_token))
        return INVALID;

    uint decl_token = visible_decl[value_token];
    if (!valid_token(decl_token))
        return INVALID;

    return bounded_array_instance_from_ref(
        decl_type_ref_tag[decl_token],
        decl_type_ref_payload[decl_token]);
}

bool is_array_type(uint ty)
{
    return (ty >= TY_ARRAY_BASE && ty < TY_STRUCT_BASE) ||
           ty >= TY_ARRAY_BASE + TY_GENERIC_BASE;
}

uint call_callee_token(uint call_node)
{
    if (call_node >= active_compact_hir_count() || compact_hir_core[call_node].kind != HIR_CALL_EXPR)
        return INVALID;

    uint callee_hir = compact_hir_payload[call_node].a;
    if (callee_hir >= active_compact_hir_count())
        return INVALID;

    HirCore callee = compact_hir_core[callee_hir];
    uint token = callee.kind == 21u
        ? compact_hir_payload[callee_hir].c
        : callee.token_start;
    return valid_token(token) ? token : INVALID;
}

uint call_argument_count(uint call_node)
{
    if (call_node >= active_compact_hir_count() || compact_hir_core[call_node].kind != HIR_CALL_EXPR)
        return 0u;
    return compact_hir_payload[call_node].c;
}

uint direct_array_return_call_node(uint return_node)
{
    uint call_node = stmt_payload(return_node).b;
    if (call_node >= active_compact_hir_count() || compact_hir_core[call_node].kind != HIR_CALL_EXPR)
        return INVALID;

    if (call_argument_count(call_node) != 1u)
        return INVALID;

    uint callee_token = call_callee_token(call_node);
    return valid_token(callee_token) && is_array_type(call_return_type[callee_token])
               ? call_node
               : INVALID;
}

uint call_arg_node_for_call(uint call_node, uint ordinal)
{
    if (call_node >= active_compact_hir_count())
        return INVALID;

    HirPayload call = compact_hir_payload[call_node];
    uint start = call.b;
    uint count = call.c;
    if (start == INVALID || ordinal >= count)
        return INVALID;

    uint row = start + ordinal;
    uint active_args = min(compact_call_arg_count[0u], gParams.n_hir_nodes);
    if (row >= active_args)
        return INVALID;
    HirCallArg arg = compact_call_args[row];
    return arg.call == call_node && arg.ordinal == ordinal ? arg.value : INVALID;
}

uint returned_call_arg_array_instance(uint return_node)
{
    uint call_node = direct_array_return_call_node(return_node);
    if (call_node >= active_compact_hir_count())
        return INVALID;

    uint arg_node = call_arg_node_for_call(call_node, 0u);
    uint arg_token = name_token_for_expr(arg_node);
    return declaration_array_instance(arg_token);
}

// Publish the array-return sentinel of one return statement. A returned
// declaration (`return values;`) or the declaration passed to a one-argument
// array call (`return copy(values);`) must have the function's bounded array
// type: the same canonical ID, interned at one call site for all three rows.
void publish_array_return(uint return_node)
{
    HirPayload stmt = stmt_payload(return_node);
    if (return_node >= active_compact_hir_count() ||
        compact_hir_core[return_node].kind != HIR_RETURN_STMT ||
        stmt.a != STMT_RECORD_KIND_RETURN)
        return;
    uint return_token = compact_hir_core[return_node].token_start;
    if (!valid_token(return_token))
        return;
    uint dst_instance = function_return_array_instance(return_node);
    uint declared = declaration_array_instance(stmt.d);
    uint argument = dst_instance != INVALID ? returned_call_arg_array_instance(return_node) : INVALID;
    uint expected = CT_NONE;
    uint spare = CT_NONE;
    // Step 0 interns the return type; steps 1 and 2 check the returned
    // declaration and the call argument, in that order.
    for (uint step = 0u; step < 3u; step++)
    {
        uint source = step == 0u ? dst_instance : step == 1u ? declared : argument;
        if (source == INVALID) continue;
        uint id = ct_intern_checked<CtCheckedRows>(3u, source, spare);
        if (step == 0u) { expected = id; continue; }
        if (dst_instance != INVALID && ct_is_resolved(expected) && id == expected)
            call_return_type[return_token] = ARRAY_RETURN_OK;
        // A returned declaration mismatches a bounded array return; a call
        // argument is only checked against one.
        else if (dst_instance != INVALID)
            record_min_token_error(status, return_token, ERR_ASSIGN_MISMATCH, 0u);
    }
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint node = linear_thread_id(dtid);
    if (node >= active_compact_hir_count())
        return;

    publish_array_return(node);
}
