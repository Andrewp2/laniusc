import type_checker.checked_array_counts;
import type_checker.constant_parameter_slots;
// Publish per-call array-argument facts from compact argument rows.
//
// Conditions consume this fact instead of scanning a fixed argument window.
// Each compact argument row reads its expression's synthesized reference (the
// shared rule of inference_expression_reference.slang) and atomically marks
// the owning call when the argument is a complete bounded array that the
// callee returns unchanged.

import hir_records;
import primitive_types;
import atomics;
import hir_expr_semantics;
import type_checker.checked_index_reference;
import type_checker.checked_scoped_types;
import type_checker.checked_type_graph;

struct Params
{
    uint n_tokens;
    uint source_len;
    uint n_hir_nodes;
};

ConstantBuffer<Params> gParams;

StructuredBuffer<uint> token_count;
StructuredBuffer<uint> compact_hir_count;
StructuredBuffer<HirCore> compact_hir_core;
StructuredBuffer<HirPayload> compact_hir_payload;
StructuredBuffer<uint> call_fn_index;
StructuredBuffer<uint> call_param_row_count_out;
StructuredBuffer<uint> call_param_row_ref_tag;
StructuredBuffer<uint> call_param_row_ref_payload;
StructuredBuffer<uint> fn_return_ref_tag;
StructuredBuffer<uint> fn_return_ref_payload;
StructuredBuffer<uint> decl_type_ref_tag;
StructuredBuffer<uint> decl_type_ref_payload;
StructuredBuffer<uint> type_expr_ref_tag;
StructuredBuffer<uint> type_expr_ref_payload;
StructuredBuffer<uint> member_result_ref_tag;
StructuredBuffer<uint> member_result_ref_payload;
StructuredBuffer<uint> call_inference_result_tag;
StructuredBuffer<uint> call_inference_result_payload;
StructuredBuffer<uint> visible_decl;
StructuredBuffer<uint> call_arg_row_count_out;
StructuredBuffer<uint> call_arg_row_node;
StructuredBuffer<uint> call_arg_row_call_node;
StructuredBuffer<uint> call_arg_param_row;

RWStructuredBuffer<uint> call_result_instance;

#include "../inference_expression_reference.slang"

static const uint INVALID = 0xffffffffu;

static const uint HIR_CALL_EXPR = 19u;
static const uint HIR_MEMBER_EXPR = 21u;

static const uint TYPE_REF_SCALAR = 1u;
static const uint TYPE_REF_GENERIC_PARAM = 2u;
static const uint TYPE_REF_INSTANCE = 3u;
static const uint TYPE_INSTANCE_ARRAY = 2u;

static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

uint linear_thread_id(uint3 dtid)
{
    return dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE;
}

[ForceInline]
uint active_token_count()
{
    return min(token_count[0], gParams.n_tokens);
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
    return token != INVALID && token < active_token_count();
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

bool valid_array_instance_row(uint instance)
{
    uint capacity; uint stride;
    type_instance_kind.GetDimensions(capacity, stride);
    return instance < capacity;
}

uint bounded_array_instance_from_ref(uint tag, uint payload)
{
    return tag == TYPE_REF_INSTANCE &&
           valid_array_instance_row(payload) &&
           type_instance_kind[payload] == TYPE_INSTANCE_ARRAY &&
           checked_source_array_length_valid(type_instance_len_kind[payload],
               type_instance_len_payload[payload], gParams.n_tokens)
               ? payload
               : INVALID;
}

uint array_instance_from_callee_return(uint callee_token)
{
    if (!valid_token(callee_token))
        return INVALID;

    uint decl_token = call_fn_index[callee_token];
    if (!valid_token(decl_token))
        decl_token = visible_decl[callee_token];
    if (!valid_token(decl_token))
        decl_token = callee_token;

    return bounded_array_instance_from_ref(
        fn_return_ref_tag[decl_token],
        fn_return_ref_payload[decl_token]);
}

uint array_instance_from_call_param_row(uint param_row)
{
    if (param_row == INVALID || param_row >= call_param_row_count_out[0u])
        return INVALID;
    return bounded_array_instance_from_ref(
        call_param_row_ref_tag[param_row],
        call_param_row_ref_payload[param_row]);
}

bool same_type_ref(uint lhs_tag, uint lhs_payload, uint rhs_tag, uint rhs_payload)
{
    if (lhs_tag == TYPE_REF_SCALAR || rhs_tag == TYPE_REF_SCALAR)
        return lhs_tag == rhs_tag && lhs_payload == rhs_payload;
    if (lhs_tag == TYPE_REF_GENERIC_PARAM && rhs_tag == TYPE_REF_GENERIC_PARAM)
    {
        uint lhs_slot = valid_token(lhs_payload) ? type_generic_param_slot_by_token[lhs_payload] : INVALID;
        uint rhs_slot = valid_token(rhs_payload) ? type_generic_param_slot_by_token[rhs_payload] : INVALID;
        return lhs_slot != INVALID && lhs_slot == rhs_slot;
    }
    return lhs_tag == rhs_tag && lhs_payload == rhs_payload;
}

bool concrete_array_elem_ref(uint tag, uint payload)
{
    if (tag == TYPE_REF_SCALAR)
        return true;
    if (tag == TYPE_REF_GENERIC_PARAM)
        return false;
    return tag == TYPE_REF_INSTANCE && valid_array_instance_row(payload);
}

bool same_array_len(uint lhs, uint rhs)
{
    return checked_source_array_lengths_equal(
        uint2(type_instance_len_kind[lhs], type_instance_len_payload[lhs]),
        uint2(type_instance_len_kind[rhs], type_instance_len_payload[rhs]), gParams.n_tokens);
}

bool concrete_bounded_array_instance(uint instance)
{
    if (!valid_array_instance_row(instance) || type_instance_kind[instance] != TYPE_INSTANCE_ARRAY)
        return false;
    uint count;
    if (!checked_source_array_count(type_instance_len_kind[instance],
        type_instance_len_payload[instance], gParams.n_tokens, count)) return false;
    return concrete_array_elem_ref(
        type_instance_elem_ref_tag[instance],
        type_instance_elem_ref_payload[instance]);
}

bool same_bounded_array_instance(uint lhs, uint rhs)
{
    if (!valid_array_instance_row(lhs) || !valid_array_instance_row(rhs))
        return false;
    if (type_instance_kind[lhs] != TYPE_INSTANCE_ARRAY ||
        type_instance_kind[rhs] != TYPE_INSTANCE_ARRAY)
        return false;
    if (!same_array_len(lhs, rhs))
        return false;
    return same_type_ref(
        type_instance_elem_ref_tag[lhs],
        type_instance_elem_ref_payload[lhs],
        type_instance_elem_ref_tag[rhs],
        type_instance_elem_ref_payload[rhs]);
}

void mark_array_return_arg_instance(uint call_node, uint actual_instance, uint param_row)
{
    uint callee_token = call_callee_token(call_node);
    if (!valid_token(callee_token))
        return;

    uint declared_instance = array_instance_from_callee_return(callee_token);
    if (declared_instance == INVALID)
        return;

    uint expected_arg_instance = array_instance_from_call_param_row(param_row);
    if (!same_bounded_array_instance(declared_instance, expected_arg_instance))
        return;

    if (!concrete_bounded_array_instance(actual_instance))
        return;
    atomic_u32_min(call_result_instance, call_node, actual_instance);
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint row = linear_thread_id(dtid);
    uint row_count = min(call_arg_row_count_out[0u], active_hir_node_count());
    if (row >= row_count)
        return;

    uint arg_node = call_arg_row_node[row];
    uint call_node = call_arg_row_call_node[row];
    if (!valid_node(arg_node) || !valid_node(call_node))
        return;

    // The argument's synthesized reference: a complete bounded array instance
    // whatever its expression form (a name, a member, a call result, ...).
    uint tag; uint payload;
    if (!inference_value_reference(arg_node, tag, payload))
        return;
    uint actual_instance = bounded_array_instance_from_ref(tag, payload);
    if (actual_instance != INVALID)
        mark_array_return_arg_instance(call_node, actual_instance, call_arg_param_row[row]);
}
