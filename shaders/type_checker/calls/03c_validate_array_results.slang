// Compact-HIR array call-result validation.
//
// This pass runs after bounded generic array call inference. It keeps
// array-valued call results length-aware by comparing the annotated destination
// declaration's array instance with either the callee's declared return array
// instance or the declaration-backed actual array argument instance. It consumes
// dense statement/call payloads and type-instance refs; it does not inspect
// source bytes, token spelling, helper
// names, or callee function bodies. Over-width call/parameter windows fail
// closed before bounded cache slots are consumed.
//
// Types compare by canonical ID (docs/canonical-type-ids.md). Rows written
// during inference are interned on demand, from one site per lane. An
// argument's declared parameter array is substituted under the call's value
// environment (call_env.slang) and compared with the actual array as a whole:
// element and length count class.

import hir_records;
import status;
import type_checker.checked_array_counts;
import type_checker.checked_type_graph;
import type_checker.checked_slots;
import type_checker.calls.claim_lookup;
import type_checker.calls.checked_call_environment;
import type_checker.calls.checked_constant_environment;
import type_checker.canonical.canonical_api;
import type_checker.canonical.canonical_checked_rows;
import type_checker.substitution.ct_checked;
import type_checker.substitution.ct_subst;
import type_checker.substitution.call_env;

struct Params
{
    uint n_tokens;
    uint source_len;
    uint n_hir_nodes;
};

ConstantBuffer<Params> gParams;

StructuredBuffer<uint> compact_hir_count;
StructuredBuffer<HirCore> compact_hir_core;
StructuredBuffer<HirPayload> compact_hir_payload;
StructuredBuffer<uint4> call_arg_record;
StructuredBuffer<uint> call_arg_row_node;
StructuredBuffer<uint> call_arg_row_call_node;
StructuredBuffer<uint> call_arg_row_ordinal;
StructuredBuffer<uint> call_arg_row_start;
StructuredBuffer<uint> call_arg_row_count;
StructuredBuffer<uint> call_arg_param_row;
RWStructuredBuffer<uint> call_result_instance;
StructuredBuffer<uint> call_fn_index;
StructuredBuffer<uint> call_param_count;
StructuredBuffer<uint> call_param_row_count_out;
StructuredBuffer<uint> call_param_row_ref_tag;
StructuredBuffer<uint> call_param_row_ref_payload;
StructuredBuffer<uint> call_generic_slot_type;
StructuredBuffer<uint> call_generic_claim_type;
StructuredBuffer<uint> visible_decl;
StructuredBuffer<uint> visible_type;
StructuredBuffer<uint> decl_type_ref_tag;
StructuredBuffer<uint> decl_type_ref_payload;
StructuredBuffer<uint> fn_return_ref_tag;
StructuredBuffer<uint> fn_return_ref_payload;
StructuredBuffer<uint> method_call_name_id;

StructuredBuffer<uint> call_return_generic_slot;

RWStructuredBuffer<uint> status;
// The status words before the final validation passes.
StructuredBuffer<uint> status_prior;
RWStructuredBuffer<uint> call_return_type;

static const uint INVALID = 0xffffffffu;

static const uint ERR_ASSIGN_MISMATCH = 3u;
static const uint ERR_CALL_MISMATCH = 10u;

static const uint HIR_CALL_EXPR = 19u;
static const uint HIR_MEMBER_EXPR = 21u;
static const uint HIR_NAME_EXPR = 22u;
static const uint HIR_EXPR_NAME = 2u;

static const uint STMT_RECORD_STRIDE = 4u;
static const uint STMT_RECORD_KIND_LET = 1u;

static const uint HIR_EXPR_RECORD_STRIDE = 4u;
static const uint HIR_EXPR_RECORD_VALUE_TOKEN = 3u;

static const uint TYPE_REF_SCALAR = 1u;
static const uint TYPE_REF_GENERIC_PARAM = 2u;
static const uint TYPE_REF_INSTANCE = 3u;

static const uint TYPE_INSTANCE_ARRAY = 2u;


static const uint TY_UNKNOWN = 0u;
static const uint TY_ARRAY_BASE = 128u;
static const uint TY_STRUCT_BASE = 4096u;
static const uint TY_GENERIC_BASE = 8192u;
static const uint CALL_MISMATCH_ARITY = 0xffffff05u;
static const uint PARAM_CACHE_STRIDE = 4u;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

uint linear_thread_id(uint3 dtid)
{
    return dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE;
}

uint active_hir_node_count()
{
    return min(gParams.n_hir_nodes, compact_hir_count[0u]);
}

bool valid_node(uint node)
{
    return node != INVALID && node < active_hir_node_count();
}

bool valid_token(uint token)
{
    return token != INVALID && token < gParams.n_tokens;
}

uint type_capacity()
{
    uint capacity; uint stride;
    type_instance_kind.GetDimensions(capacity, stride);
    return capacity;
}

bool valid_instance(uint instance) { return instance < type_capacity(); }

uint stmt_slot(uint node, uint slot)
{
    if (!valid_node(node)) return INVALID;
    HirPayload payload = compact_hir_payload[node];
    if (slot == 0u) return payload.a;
    if (slot == 1u) return payload.b;
    if (slot == 2u) return payload.c;
    return payload.d;
}

uint expr_slot(uint node, uint slot)
{
    if (!valid_node(node)) return INVALID;
    HirPayload payload = compact_hir_payload[node];
    if (slot == 0u) return payload.a;
    if (slot == 1u) return payload.b;
    if (slot == 2u) return payload.c;
    return payload.d;
}

uint resolve_expr(uint node)
{
    if (!valid_node(node))
        return INVALID;
    return node;
}

uint name_token_for_expr(uint root)
{
    uint node = resolve_expr(root);
    if (!valid_node(node) ||
        (compact_hir_core[node].kind != HIR_NAME_EXPR &&
         expr_slot(node, 0u) != HIR_EXPR_NAME))
        return INVALID;

    uint token = expr_slot(node, HIR_EXPR_RECORD_VALUE_TOKEN);
    return valid_token(token) ? token : compact_hir_core[node].token_start;
}

bool is_array_type(uint ty)
{
    return (ty >= TY_ARRAY_BASE && ty < TY_STRUCT_BASE) ||
           ty >= TY_ARRAY_BASE + TY_GENERIC_BASE;
}

bool is_symbolic_array_type(uint ty)
{
    return ty == TY_ARRAY_BASE + TY_UNKNOWN ||
           ty >= TY_ARRAY_BASE + TY_GENERIC_BASE;
}

uint call_callee_token(uint call_node)
{
    if (!valid_node(call_node) || compact_hir_core[call_node].kind != HIR_CALL_EXPR)
        return INVALID;

    uint callee_node = compact_hir_payload[call_node].a;
    // A member's leaf owns this call; its span can begin in a receiver call.
    if (valid_node(callee_node) && compact_hir_core[callee_node].kind == HIR_MEMBER_EXPR)
    {
        uint member_token = compact_hir_payload[callee_node].c;
        return valid_token(member_token) ? member_token : INVALID;
    }
    uint call_token = compact_hir_core[call_node].token_start;
    if (valid_token(call_token) && valid_token(call_fn_index[call_token]))
        return call_token;

    if (!valid_node(callee_node))
        return INVALID;

    HirCore callee = compact_hir_core[callee_node];
    HirPayload payload = compact_hir_payload[callee_node];
    uint token = payload.d;
    if (!valid_token(token)) token = callee.token_start;
    return valid_token(token) ? token : INVALID;
}

uint call_arg_node_for_call(uint call_node, uint ordinal)
{
    if (!valid_node(call_node))
        return INVALID;

    uint start = call_arg_row_start[call_node];
    uint count = call_arg_row_count[call_node];
    if (start == INVALID || ordinal >= count)
        return INVALID;

    uint row = start + ordinal;
    return row < active_hir_node_count() ? call_arg_row_node[row] : INVALID;
}

uint first_call_arg_name_token(uint callee_token, uint call_node)
{
    uint arg_node = call_arg_node_for_call(call_node, 0u);
    uint arg_node_token = name_token_for_expr(arg_node);
    if (valid_token(arg_node_token))
        return arg_node_token;

    if (valid_token(callee_token))
    {
        uint arg_token = call_arg_record[callee_token].x;
        if (valid_token(arg_token))
            return arg_token;
    }

    return INVALID;
}

uint call_arg_count_for_callee(uint callee_token, uint call_node)
{
    if (!valid_token(callee_token))
        return 0u;
    uint record_count = call_arg_record[callee_token].w;
    if (!valid_node(call_node))
        return record_count;
    return max(max(record_count, compact_hir_payload[call_node].c), call_arg_row_count[call_node]);
}

bool call_window_fits_cache(uint callee_token, uint call_node)
{
    uint fn_token = valid_token(callee_token) ? call_fn_index[callee_token] : INVALID;
    if (!valid_token(fn_token))
        return true;

    uint param_count = call_param_count[fn_token];
    uint arg_count = call_arg_count_for_callee(callee_token, call_node);
    if (param_count == arg_count)
        return true;

    call_return_type[callee_token] = TY_UNKNOWN;
    record_min_token_error(
        status,
        callee_token,
        ERR_CALL_MISMATCH,
        CALL_MISMATCH_ARITY);
    return false;
}

// Bounded-array lookups. A candidate is an array instance row whose length
// descriptor is not checked yet; bounded_arrays keeps the candidates with a
// valid descriptor, from one check site per lane.
uint array_candidate(uint tag, uint payload)
{
    if (tag != TYPE_REF_INSTANCE || !valid_instance(payload))
        return INVALID;
    return type_instance_kind[payload] == TYPE_INSTANCE_ARRAY ? payload : INVALID;
}

uint decl_array_candidate(uint decl_token)
{
    if (!valid_token(decl_token))
        return INVALID;
    return array_candidate(decl_type_ref_tag[decl_token], decl_type_ref_payload[decl_token]);
}

uint callee_return_candidate(uint callee_token)
{
    if (!valid_token(callee_token))
        return INVALID;

    uint decl_token = call_fn_index[callee_token];
    if (!valid_token(decl_token))
        decl_token = visible_decl[callee_token];
    if (!valid_token(decl_token))
        decl_token = callee_token;

    return array_candidate(fn_return_ref_tag[decl_token], fn_return_ref_payload[decl_token]);
}

uint call_param_row_candidate(uint param_row)
{
    if (param_row == INVALID || param_row >= call_param_row_count_out[0u])
        return INVALID;
    return array_candidate(call_param_row_ref_tag[param_row], call_param_row_ref_payload[param_row]);
}

// A name's candidates: its visible declaration's (.x) and its own (.y).
uint2 name_array_candidates(uint name_token)
{
    if (!valid_token(name_token))
        return uint2(INVALID, INVALID);
    return uint2(decl_array_candidate(visible_decl[name_token]), decl_array_candidate(name_token));
}

uint4 bounded_arrays(uint4 candidates)
{
    uint4 bounded = uint4(INVALID, INVALID, INVALID, INVALID);
    [loop]
    for (uint index = 0u; index < 4u; index++)
    {
        uint row = candidates[index];
        if (row != INVALID && checked_source_array_length_valid(type_instance_len_kind[row],
                type_instance_len_payload[row], gParams.n_tokens))
            bounded[index] = row;
    }
    return bounded;
}

// The bounded array declared for a name: its visible declaration's, else
// its own when the name is not its own declaration. `bounded` holds the
// checked name_array_candidates.
uint name_bounded_array(uint name_token, uint2 bounded)
{
    if (!valid_token(name_token))
        return INVALID;
    return bounded.x != INVALID || visible_decl[name_token] == name_token ? bounded.x : bounded.y;
}

bool concrete_array_elem_ref(uint tag, uint payload)
{
    if (tag == TYPE_REF_SCALAR)
        return true;
    if (tag == TYPE_REF_GENERIC_PARAM)
        return false;
    return tag == TYPE_REF_INSTANCE && valid_instance(payload);
}

uint type_code_for_ref(uint tag, uint payload)
{
    if (tag == TYPE_REF_SCALAR)
        return payload;
    if (tag == TYPE_REF_GENERIC_PARAM)
    {
        uint slot = valid_token(payload) ? type_generic_param_slot_by_token[payload] : INVALID;
        return slot == INVALID ? TY_UNKNOWN : TY_GENERIC_BASE + slot;
    }
    return TY_UNKNOWN;
}

uint array_type_code_from_instance(uint instance)
{
    if (!valid_instance(instance) || type_instance_kind[instance] != TYPE_INSTANCE_ARRAY)
        return TY_UNKNOWN;
    uint elem_ty = type_code_for_ref(
        type_instance_elem_ref_tag[instance],
        type_instance_elem_ref_payload[instance]);
    return elem_ty == TY_UNKNOWN ? TY_UNKNOWN : TY_ARRAY_BASE + elem_ty;
}

bool concrete_bounded_array_instance(uint instance)
{
    if (!valid_instance(instance) || type_instance_kind[instance] != TYPE_INSTANCE_ARRAY)
        return false;
    uint count;
    if (!checked_source_array_count(type_instance_len_kind[instance],
        type_instance_len_payload[instance], gParams.n_tokens, count)) return false;
    return concrete_array_elem_ref(
        type_instance_elem_ref_tag[instance],
        type_instance_elem_ref_payload[instance]);
}

uint direct_generic_array_result(uint callee)
{
    uint function = call_fn_index[callee];
    if (!valid_token(function)) return INVALID;
    uint slot = call_return_generic_slot[function];
    uint count = call_generic_claim_count_out[0u];
    if (slot == INVALID || count == 0u) return INVALID;
    uint link = call_generic_claim_lookup_head[call_claim_lookup_bucket(callee, slot, count)];
    uint accepted = INVALID;
    for (uint step = 0u; step < count && link != 0u; step++)
    {
        uint row = link - 1u;
        if (row >= count) break;
        if (call_generic_claim_callee[row] == callee && call_generic_claim_slot[row] == slot &&
            call_generic_claim_ref_tag[row] == TYPE_REF_INSTANCE)
            accepted = min(accepted, row);
        link = call_generic_claim_lookup_next[row];
    }
    if (accepted == INVALID) return INVALID;
    uint instance = call_generic_claim_ref_payload[accepted];
    return valid_instance(instance) && type_instance_kind[instance] == TYPE_INSTANCE_ARRAY
        ? instance : INVALID;
}

// One lane validates the let statement at its index and then the argument
// row at its index. Each check first applies the old pre-comparison effects,
// then names the rows it compares; the lane interns them from one site and
// finishes the check with their IDs.
static const uint CHECK_NONE = 0u;
// The let's expected array against the checked call result (`other`).
static const uint CHECK_LET_CHECKED = 1u;
// Against the direct generic array claim (`other`); a match publishes it.
static const uint CHECK_LET_GENERIC = 2u;
// Against the declared return (`other`), then the actual result (`actual`).
static const uint CHECK_LET_DECLARED = 3u;
// The parameter array (`expected`) under the call's value environment
// against the actual argument array (`other`).
static const uint CHECK_ARGUMENT = 4u;

struct ArrayCheck
{
    uint mode;
    uint call_node;
    uint callee_token;
    uint decl_token;
    uint expected;
    uint other;
    uint actual;
    uint actual_ty;
}

ArrayCheck no_check()
{
    ArrayCheck check;
    check.mode = CHECK_NONE;
    check.call_node = INVALID;
    check.callee_token = INVALID;
    check.decl_token = INVALID;
    check.expected = INVALID;
    check.other = INVALID;
    check.actual = INVALID;
    check.actual_ty = TY_UNKNOWN;
    return check;
}

// An array row that a same-array comparison may read, or INVALID.
uint comparable_array(uint instance)
{
    return valid_instance(instance) && type_instance_kind[instance] == TYPE_INSTANCE_ARRAY
        ? instance : INVALID;
}

bool same_id(uint left, uint right)
{
    return ct_is_resolved(left) && left == right;
}

// The let's candidates: expected (.x), declared return (.y) and the first
// argument name's (.zw).
uint4 let_candidates(uint node)
{
    uint4 candidates = uint4(INVALID, INVALID, INVALID, INVALID);
    if (!valid_node(node) || stmt_slot(node, 0u) != STMT_RECORD_KIND_LET)
        return candidates;
    candidates.x = decl_array_candidate(stmt_slot(node, 1u));
    uint call_node = resolve_expr(stmt_slot(node, 2u));
    if (!valid_node(call_node) || compact_hir_core[call_node].kind != HIR_CALL_EXPR)
        return candidates;
    uint callee_token = call_callee_token(call_node);
    if (!valid_token(callee_token))
        return candidates;
    candidates.y = callee_return_candidate(callee_token);
    candidates.zw = name_array_candidates(first_call_arg_name_token(callee_token, call_node));
    return candidates;
}

ArrayCheck prepare_let(uint node, uint4 bounded)
{
    ArrayCheck check = no_check();
    if (!valid_node(node) ||
        stmt_slot(node, 0u) != STMT_RECORD_KIND_LET)
        return check;

    uint decl_token = stmt_slot(node, 1u);
    uint expected_ty = valid_token(decl_token) ? visible_type[decl_token] : TY_UNKNOWN;
    uint expected_instance = bounded.x;
    if (expected_instance != INVALID)
    {
        uint instance_ty = array_type_code_from_instance(expected_instance);
        if (instance_ty != TY_UNKNOWN)
            expected_ty = instance_ty;
    }
    if (expected_instance == INVALID && !is_array_type(expected_ty))
        return check;

    uint expr_node = stmt_slot(node, 2u);
    uint call_node = resolve_expr(expr_node);
    if (!valid_node(call_node) || compact_hir_core[call_node].kind != HIR_CALL_EXPR)
        return check;

    uint callee_token = call_callee_token(call_node);
    if (!valid_token(callee_token))
        return check;
    if (method_call_name_id[callee_token] != INVALID)
        return check;
    if (!call_window_fits_cache(callee_token, call_node))
        return check;
    check.call_node = call_node;
    check.callee_token = callee_token;
    check.decl_token = decl_token;
    check.expected = expected_instance;
    uint checked_result = call_result_instance[call_node];
    if (expected_instance != INVALID && valid_instance(checked_result) &&
        type_instance_kind[checked_result] == TYPE_INSTANCE_ARRAY)
    {
        // Complete local/imported return materialization is authoritative.
        // A dependency callee has no local fn_return_ref row to compare.
        check.mode = CHECK_LET_CHECKED;
        check.other = checked_result;
        return check;
    }
    uint generic_instance = direct_generic_array_result(callee_token);
    if (generic_instance != INVALID && expected_instance != INVALID)
    {
        check.mode = CHECK_LET_GENERIC;
        check.other = generic_instance;
        return check;
    }
    if (!is_array_type(call_return_type[callee_token]))
        return no_check();

    uint actual_ty = call_return_type[callee_token];
    bool specialize_symbolic_result = is_symbolic_array_type(actual_ty);
    if (specialize_symbolic_result && expected_ty != TY_UNKNOWN)
        call_return_type[callee_token] = expected_ty;
    if (expected_instance == INVALID)
        return no_check();

    uint declared_instance = bounded.y;
    uint actual_instance = INVALID;
    if (declared_instance != INVALID)
    {
        actual_instance = call_result_instance[call_node];
    }
    else if (specialize_symbolic_result)
    {
        actual_instance =
            name_bounded_array(first_call_arg_name_token(callee_token, call_node), bounded.zw);
    }
    check.mode = CHECK_LET_DECLARED;
    check.other = comparable_array(declared_instance);
    check.actual = comparable_array(actual_instance);
    check.actual_ty = actual_ty;
    return check;
}

// A call result mismatch, unless an error already recorded inside the call
// explains it (an argument that does not match its parameter, such as a
// length that does not fit): that error is the diagnostic.
void record_result_error(ArrayCheck check, uint token, uint detail)
{
    HirCore call = compact_hir_core[check.call_node];
    if (!error_recorded_within(status_prior, call.token_start, call.token_end))
        record_min_token_error(status, token, ERR_ASSIGN_MISMATCH, detail);
}

void finish_let(ArrayCheck check, uint3 ids)
{
    uint callee_token = check.callee_token;
    if (check.mode == CHECK_LET_CHECKED)
    {
        if (!same_id(ids.x, ids.y))
            record_result_error(check, callee_token, TY_ARRAY_BASE * 256u + call_return_type[callee_token]);
        return;
    }
    if (check.mode == CHECK_LET_GENERIC)
    {
        if (same_id(ids.x, ids.y))
        {
            call_result_instance[check.call_node] = check.other;
            return;
        }
        record_result_error(check, callee_token, TY_ARRAY_BASE * 256u + call_return_type[callee_token]);
        return;
    }
    if (check.mode != CHECK_LET_DECLARED) return;
    if (check.other != INVALID && same_id(ids.x, ids.y))
        return;
    if (check.actual != INVALID && same_id(ids.x, ids.z))
        return;

    record_result_error(check, valid_token(callee_token) ? callee_token : check.decl_token,
        TY_ARRAY_BASE * 256u + check.actual_ty);
}

// The argument row's candidates: its parameter (.x) and its name's (.zw).
uint4 argument_candidates(uint row)
{
    uint4 candidates = uint4(INVALID, INVALID, INVALID, INVALID);
    if (row >= call_arg_row_count_out[0])
        return candidates;
    candidates.x = call_param_row_candidate(call_arg_param_row[row]);
    candidates.zw = name_array_candidates(name_token_for_expr(call_arg_row_node[row]));
    return candidates;
}

ArrayCheck prepare_argument(uint row, uint4 bounded)
{
    ArrayCheck check = no_check();
    if (row >= call_arg_row_count_out[0])
        return check;

    uint call_node = call_arg_row_call_node[row];
    if (!valid_node(call_node) || compact_hir_core[call_node].kind != HIR_CALL_EXPR)
        return check;

    uint callee_token = call_callee_token(call_node);
    if (!valid_token(callee_token))
        return check;
    if (method_call_name_id[callee_token] != INVALID)
        return check;

    uint expected_instance = bounded.x;
    if (expected_instance == INVALID)
        return check;
    if (!call_window_fits_cache(callee_token, call_node))
        return check;

    uint arg_node = call_arg_row_node[row];
    uint actual_instance = name_bounded_array(name_token_for_expr(arg_node), bounded.zw);
    if (!concrete_bounded_array_instance(actual_instance))
        return check;
    check.mode = CHECK_ARGUMENT;
    check.call_node = call_node;
    check.callee_token = callee_token;
    check.expected = expected_instance;
    check.other = actual_instance;
    return check;
}

void finish_argument(ArrayCheck check, uint3 ids)
{
    if (check.mode != CHECK_ARGUMENT) return;
    // Parameter inference has accepted complete bindings. The whole
    // parameter array, including nominal arguments, nested elements and its
    // length, is substituted under them; scalar cache codes cannot represent
    // these facts. A missing substitution is a mismatch.
    uint expected = ids.x;
    uint environment = ct_is_resolved(expected) && !ct_closed(expected)
        ? ct_call_env(check.callee_token).x : CT_NONE;
    CtSpare spare = ct_spare_none();
    uint substituted = environment == CT_NONE || ct_is_record(environment)
        ? ct_subst(CheckedSlots(), environment, expected, false, spare) : CT_UNKNOWN;
    if (same_id(substituted, ids.y))
        return;

    record_result_error(check, check.callee_token, TY_ARRAY_BASE * 256u + TY_UNKNOWN);
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint lane = linear_thread_id(dtid);
    uint spare = CT_NONE;
    [loop]
    for (uint phase = 0u; phase < 2u; phase++)
    {
        uint4 candidates;
        if (phase == 0u) candidates = let_candidates(lane);
        else candidates = argument_candidates(lane);
        uint4 bounded = bounded_arrays(candidates);
        ArrayCheck check;
        if (phase == 0u) check = prepare_let(lane, bounded);
        else check = prepare_argument(lane, bounded);
        uint3 ids = uint3(CT_UNKNOWN, CT_UNKNOWN, CT_UNKNOWN);
        [loop]
        for (uint index = 0u; index < 3u; index++)
        {
            uint row = index == 0u ? check.expected : index == 1u ? check.other : check.actual;
            if (check.mode == CHECK_NONE || row == INVALID) continue;
            uint id = ct_intern_checked<CtCheckedRows>(TYPE_REF_INSTANCE, row, spare);
            if (index == 0u) ids.x = id;
            else if (index == 1u) ids.y = id;
            else ids.z = id;
        }
        if (phase == 0u) finish_let(check, ids);
        else finish_argument(check, ids);
    }
}
