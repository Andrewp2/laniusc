import type_checker.constant_constraints;
import type_checker.constant_publication;
import type_checker.argument_context;
import type_checker.argument_borrow;
import type_checker.calls.explicit_call_environment;
import type_checker.constant_parameter_slots;
import type_checker.calls.parameter_pattern_page;
// Emit complete generic bindings from compact per-argument claim spans.
// Collection records each parameter pattern's slot mask. One lane per argument
// matches its complete pattern once and publishes that span; other lanes leave
// it untouched. All call forms use this same relation and conflict validator.

import external_type_identity;
import dependency_interface;
import hir_records;
import atomics;
import hir_expr_semantics;
import type_checker.checked_index_reference;
import type_checker.generic_result_type_origin;
import type_checker.concrete_type_closure;
import type_checker.instance_arguments;
import status;

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
StructuredBuffer<uint> compact_hir_expr_parent;
StructuredBuffer<uint> call_arg_row_count_out;
StructuredBuffer<uint> call_arg_row_count;
StructuredBuffer<uint> call_arg_row_node;
StructuredBuffer<uint> call_arg_row_call_node;
StructuredBuffer<uint> call_arg_param_row;
StructuredBuffer<uint> call_generic_claim_count_out;
StructuredBuffer<uint> call_generic_claim_scan_input;
StructuredBuffer<uint> call_generic_claim_pattern_mask;
StructuredBuffer<uint> call_generic_claim_prefix;
StructuredBuffer<uint> call_const_claim_scan_input;
StructuredBuffer<uint> call_const_claim_pattern_mask;
StructuredBuffer<uint> call_const_claim_prefix;
StructuredBuffer<uint> call_intrinsic_tag;
StructuredBuffer<uint> call_fn_index;
StructuredBuffer<uint> call_dependency_library_id;
StructuredBuffer<uint> call_dependency_unit_id;
StructuredBuffer<uint> call_dependency_local_index;
RWStructuredBuffer<uint> call_return_type;
StructuredBuffer<uint> call_return_type_token;
StructuredBuffer<uint> call_return_generic_slot;
StructuredBuffer<uint> call_generic_return_arg_node;
StructuredBuffer<uint> visible_decl;
StructuredBuffer<uint> visible_type;
StructuredBuffer<uint> decl_type_ref_tag;
StructuredBuffer<uint> decl_type_ref_payload;
StructuredBuffer<uint> member_result_ref_tag;
StructuredBuffer<uint> member_result_ref_payload;
StructuredBuffer<uint> semantic_expr_ref_tag_by_hir;
StructuredBuffer<uint> semantic_expr_ref_payload_by_hir;
StructuredBuffer<uint> method_call_name_id;
StructuredBuffer<uint> call_param_row_type;
StructuredBuffer<uint> call_param_row_ref_tag;
StructuredBuffer<uint> call_param_row_ref_payload;
StructuredBuffer<uint> type_generic_param_slot_by_token;
StructuredBuffer<uint> type_instance_kind;
StructuredBuffer<uint> type_instance_decl_token;
StructuredBuffer<uint> type_instance_arg_start;
StructuredBuffer<uint> type_instance_arg_count;
StructuredBuffer<uint> type_instance_arg_ref_tag;
StructuredBuffer<uint> type_instance_arg_ref_payload;
StructuredBuffer<uint> type_instance_arg_row_start;
StructuredBuffer<uint> type_instance_arg_row_count_out;
StructuredBuffer<uint> type_instance_arg_row_ref_tag;
StructuredBuffer<uint> type_instance_arg_row_ref_payload;
StructuredBuffer<uint> type_instance_elem_ref_tag;
StructuredBuffer<uint> type_instance_elem_ref_payload;
StructuredBuffer<uint> type_instance_len_kind;
StructuredBuffer<uint> type_instance_len_payload;

RWStructuredBuffer<uint> call_generic_claim_callee;
RWStructuredBuffer<uint> call_generic_claim_slot;
RWStructuredBuffer<uint> call_generic_claim_type;
RWStructuredBuffer<uint> call_generic_claim_ref_tag;
RWStructuredBuffer<uint> call_generic_claim_ref_payload;
RWStructuredBuffer<uint> call_generic_claim_arg_row;
RWStructuredBuffer<uint> call_arg_row_literal_context_mask;
RWStructuredBuffer<uint> semantic_argument_mode_by_hir;
RWStructuredBuffer<uint> call_const_claim_callee;
RWStructuredBuffer<uint> call_const_claim_slot;
RWStructuredBuffer<uint> call_const_claim_ref_kind;
RWStructuredBuffer<uint> call_const_claim_ref_payload;
RWStructuredBuffer<uint> call_const_claim_identity_mode;
RWStructuredBuffer<uint> call_const_claim_selected;
RWStructuredBuffer<uint> call_const_claim_arg_row;
RWStructuredBuffer<uint> call_result_instance;
RWStructuredBuffer<uint> status;

static const uint INVALID = 0xffffffffu;

static const uint HIR_CALL_EXPR = 19u;
static const uint HIR_INDEX_EXPR = 20u;
static const uint HIR_MEMBER_EXPR = 21u;
static const uint HIR_NAME_EXPR = 22u;
static const uint HIR_STRUCT_LITERAL_EXPR = 28u;
static const uint HIR_MATCH_EXPR = 34u;

static const uint HIR_EXPR_RECORD_STRIDE = 4u;
static const uint HIR_EXPR_RECORD_FORM = 0u;
static const uint HIR_EXPR_RECORD_LEFT = 1u;
static const uint HIR_EXPR_RECORD_RIGHT = 2u;
static const uint HIR_EXPR_RECORD_VALUE_TOKEN = 3u;

static const uint HIR_EXPR_NONE = 0u;
static const uint HIR_EXPR_FORWARD = 1u;
static const uint HIR_EXPR_NAME = 2u;
static const uint HIR_EXPR_INT = 3u;
static const uint HIR_EXPR_TRUE = 4u;
static const uint HIR_EXPR_FALSE = 5u;
static const uint HIR_EXPR_NOT = 6u;
static const uint HIR_EXPR_EQ = 7u;
static const uint HIR_EXPR_NE = 8u;
static const uint HIR_EXPR_LT = 9u;
static const uint HIR_EXPR_GT = 10u;
static const uint HIR_EXPR_LE = 11u;
static const uint HIR_EXPR_GE = 12u;
static const uint HIR_EXPR_NEG = 13u;
static const uint HIR_EXPR_ADD = 14u;
static const uint HIR_EXPR_SUB = 15u;
static const uint HIR_EXPR_MUL = 16u;
static const uint HIR_EXPR_AND = 17u;
static const uint HIR_EXPR_OR = 18u;
static const uint HIR_EXPR_MOD = 19u;
static const uint HIR_EXPR_DIV = 20u;
static const uint HIR_EXPR_BIT_OR = 21u;
static const uint HIR_EXPR_BIT_XOR = 22u;
static const uint HIR_EXPR_BIT_AND = 23u;
static const uint HIR_EXPR_SHL = 24u;
static const uint HIR_EXPR_SHR = 25u;
static const uint HIR_EXPR_FLOAT = 27u;

static const uint TY_UNKNOWN = 0u;
static const uint TY_BOOL = 2u;
static const uint TY_INT = 3u;
static const uint TY_FLOAT = 5u;
static const uint TY_CHAR = 6u;
static const uint TY_STRING = 7u;
static const uint TY_ARRAY_BASE = 128u;
static const uint TY_GENERIC_BASE = 8192u;

static const uint TYPE_REF_INVALID = 0u;
static const uint TYPE_REF_SCALAR = 1u;
static const uint TYPE_REF_GENERIC_PARAM = 2u;
static const uint TYPE_REF_INSTANCE = 3u;
static const uint TYPE_REF_EXTERNAL_CANONICAL = 5u;
static const uint TYPE_REF_EXTERNAL_GENERIC = 6u;
static const uint TYPE_INSTANCE_NAMED = 1u;
static const uint TYPE_INSTANCE_ARRAY = 2u;
static const uint TYPE_INSTANCE_SLICE = 3u;
static const uint INTERFACE_TYPE_GENERIC_PARAMETER = 2u;
static const uint INTERFACE_TYPE_DECLARATION = 3u;
static const uint INTERFACE_TYPE_ARRAY = 4u;
static const uint INTERFACE_TYPE_SLICE = 5u;
static const uint INTERFACE_TYPE_WORDS = 9u;
static const uint TYPE_INSTANCE_ARG_REF_STRIDE = 4u;
static const uint DECL_WORDS = 14u;
static const uint HIR_ITEM_KIND_ENUM = 7u;
static const uint HIR_ITEM_KIND_ENUM_VARIANT = 9u;
static const uint INTERFACE_TYPE_SCALAR = 1u;
static const uint INTERFACE_TYPE_FUNCTION = 7u;

static const uint ERR_ASSIGN_MISMATCH = 3u;
static const uint ERR_CALL_MISMATCH = 10u;
static const uint CALL_MISMATCH_GENERIC_CLAIM_CAPACITY = 0xffffff04u;
static const uint PARAM_CACHE_STRIDE = 4u;
static const uint INTRINSIC_NONE = 0u;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;
static const uint GENERIC_CLAIM_CAPACITY_MULTIPLIER = 32u;

#include "parameter_type_pattern.slang"
#include "argument_value_reference.slang"

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

void record_error(uint token_i, uint code, uint detail)
{
    record_min_token_error(status, token_i, code, detail);
}

bool is_generic_type(uint ty)
{
    return ty >= TY_GENERIC_BASE && ty != INVALID;
}

uint call_arg_error_token(uint arg_node, uint callee_i)
{
    return valid_node(arg_node) ? compact_hir_core[arg_node].token_start : callee_i;
}

void clear_generic_claim(uint claim_i)
{
    call_generic_claim_callee[claim_i] = INVALID;
    call_generic_claim_slot[claim_i] = INVALID;
    call_generic_claim_type[claim_i] = TY_UNKNOWN;
    call_generic_claim_ref_tag[claim_i] = TYPE_REF_INVALID;
    call_generic_claim_ref_payload[claim_i] = INVALID;
    call_generic_claim_arg_row[claim_i] = INVALID;
}

void publish_generic_return_type(
    uint callee_i,
    uint fn_i,
    uint generic_slot,
    uint arg_ty)
{
    if (!valid_token(callee_i) ||
        !valid_token(fn_i) ||
        generic_slot == INVALID ||
        arg_ty == TY_UNKNOWN)
    {
        return;
    }

    uint return_slot = call_return_generic_slot[fn_i];
    if (return_slot == INVALID || return_slot != generic_slot)
        return;

    uint expected = call_return_type[fn_i];
    if (!is_generic_type(expected))
        expected = TY_GENERIC_BASE + return_slot;

    uint prior = atomic_u32_compare_exchange(
        call_return_type,
        callee_i,
        expected,
        arg_ty);
    if (prior == INVALID || prior == TY_UNKNOWN)
        atomic_u32_compare_exchange(call_return_type, callee_i, prior, arg_ty);
}

void emit_argument_claims(uint arg_row)
{
    if (arg_row >= min(call_arg_row_count_out[0u], active_hir_node_count())) return;
    uint call = call_arg_row_call_node[arg_row];
    uint callee = callee_token_for_hir_call(call);
    if (!valid_token(callee) || !parameter_pattern_page_contains(
        call_dependency_library_id[callee], call_dependency_unit_id[callee],
        call_dependency_local_index[callee])) return;
    // The argument producer owns expression provenance. Consumers rank a
    // claim with one row read instead of traversing HIR inside graph lookup.
    call_arg_row_literal_context_mask[arg_row] = numeric_literal_accepts_context(
        call_arg_row_node[arg_row], 3u, active_hir_node_count(), compact_hir_core,
        compact_hir_payload, compact_hir_expr_parent) ? 1u : 0u;
    if (numeric_literal_accepts_context(call_arg_row_node[arg_row], 5u,
        active_hir_node_count(), compact_hir_core, compact_hir_payload, compact_hir_expr_parent))
        call_arg_row_literal_context_mask[arg_row] |= 2u;
    uint pattern_mask = call_generic_claim_pattern_mask[arg_row];
    uint constant_pattern_mask = call_const_claim_pattern_mask[arg_row];
    if ((pattern_mask | constant_pattern_mask) == 0u) return;
    uint start = call_generic_claim_prefix[arg_row];
    uint count = call_generic_claim_scan_input[arg_row];
    uint constant_start = call_const_claim_prefix[arg_row];
    uint constant_count = call_const_claim_scan_input[arg_row];
    uint capacity; uint constant_capacity; uint stride;
    call_generic_claim_callee.GetDimensions(capacity, stride);
    call_const_claim_callee.GetDimensions(constant_capacity, stride);
    uint node = resolve_expr(call_arg_row_node[arg_row]);
    if (start > capacity || count > capacity - start ||
        constant_start > constant_capacity || constant_count > constant_capacity - constant_start)
    {
        record_error(call_arg_error_token(node, callee), ERR_CALL_MISMATCH, CALL_MISMATCH_GENERIC_CLAIM_CAPACITY);
        return;
    }
    // One argument owns both complete spans, so no lane can clear another
    // lane's publication while inference rebuilds the relation.
    for (uint i = 0u; i < count; i++) clear_generic_claim(start + i);
    for (uint i = 0u; i < constant_count; i++)
    {
        uint row = constant_start + i;
        call_const_claim_callee[row] = INVALID;
        call_const_claim_slot[row] = INVALID;
        call_const_claim_ref_kind[row] = 0u;
        call_const_claim_ref_payload[row] = INVALID;
        call_const_claim_identity_mode[row] = 0u;
        call_const_claim_selected[row] = 0u;
        call_const_claim_arg_row[row] = INVALID;
    }
    uint2 inferred[32]; uint inferred_mask = 0u;
    InferredConstant constants[32]; uint constant_mask = 0u;
    for (uint slot = 0u; slot < 32u; slot++)
    { inferred[slot] = uint2(0u, INVALID); constants[slot] = inferred_constant_reference(uint2(0u, INVALID)); }
    uint tag; uint payload;
    if (argument_value_reference(node, tag, payload))
    {
        uint param = call_arg_param_row[arg_row];
        // Explicit bindings are ready at claim publication, after the early
        // parameter-pattern collector. A permitted outer borrow constrains
        // T to its bound slice; the expression itself retains its array type.
        uint root_slot = parameter_root_type_slot(
            call_param_row_ref_tag[param], call_param_row_ref_payload[param]);
        uint2 bound;
        if (root_slot < 32u && checked_explicit_environment_argument(
            0x80000000u | callee, root_slot, bound.x, bound.y))
        {
            uint kind = bound.x == 3u && bound.y < parameter_type_capacity()
                ? type_instance_kind[bound.y] : 0u;
            semantic_argument_mode_by_hir[node] = kind == 4u ? 3u : kind == 3u ? 2u : 1u;
            if (checked_array_borrow_matches<ParameterTypeGraph>(
                bound.x, bound.y, tag, payload, parameter_type_capacity()))
            {
                tag = bound.x;
                payload = bound.y;
            }
        }
        bool matches = parameter_argument_constraints(call_param_row_ref_tag[param],
            call_param_row_ref_payload[param], tag, payload, inferred, inferred_mask,
            constants, constant_mask);
        if (!matches)
        {
            uint error_token = call_arg_error_token(node, callee);
            record_error(error_token, ERR_ASSIGN_MISMATCH, 0u);
            // Slot 32 records rejection outside either parameter domain. A
            // return producer preserves this language error on failed closure.
            if (count != 0u)
            {
                call_generic_claim_callee[start] = callee;
                call_generic_claim_slot[start] = 32u;
                call_generic_claim_ref_tag[start] = 4u;
                call_generic_claim_ref_payload[start] = error_token;
                call_generic_claim_arg_row[start] = arg_row;
            }
            else if (constant_count != 0u)
            {
                call_const_claim_callee[constant_start] = callee;
                call_const_claim_slot[constant_start] = 32u;
                call_const_claim_ref_payload[constant_start] = error_token;
                call_const_claim_arg_row[constant_start] = arg_row;
            }
            return;
        }
    }
    uint ordinal = 0u; uint constant_ordinal = 0u;
    for (uint slot = 0u; slot < 32u; slot++)
    {
        if ((pattern_mask & (1u << slot)) != 0u)
        {
            uint row = start + ordinal++;
            uint2 ref = (inferred_mask & (1u << slot)) != 0u ? inferred[slot] : uint2(0u, INVALID);
            uint legacy = ref.x == 1u ? ref.y : ref.x == 3u ? 1u
                : ref.x == 2u ? leaf_type_code_for_ref(ref.x, ref.y) : 0u;
            call_generic_claim_callee[row] = callee;
            call_generic_claim_slot[row] = slot;
            call_generic_claim_arg_row[row] = arg_row;
            call_generic_claim_type[row] = legacy;
            call_generic_claim_ref_tag[row] = ref.x;
            call_generic_claim_ref_payload[row] = ref.y;
            if (ref.x == 1u) publish_generic_return_type(callee, call_fn_index[callee], slot, ref.y);
        }
        if ((constant_pattern_mask & (1u << slot)) != 0u)
        {
            uint row = constant_start + constant_ordinal++;
            uint2 ref = uint2(0u, INVALID);
            if ((constant_mask & (1u << slot)) != 0u &&
                !publish_inferred_constant<ParameterTypeGraph>(constants[slot], gParams.n_tokens,
                    uint2(call_const_claim_ref_kind[row], call_const_claim_ref_payload[row]), ref))
            {
                record_error(call_arg_error_token(node, callee), 6u, 0x474e0001u);
                call_const_claim_callee[row] = callee;
                call_const_claim_slot[row] = 32u;
                call_const_claim_ref_kind[row] = 0u;
                call_const_claim_ref_payload[row] = INVALID;
                return;
            }
            call_const_claim_callee[row] = callee;
            call_const_claim_slot[row] = slot;
            call_const_claim_arg_row[row] = arg_row;
            call_const_claim_ref_kind[row] = ref.x;
            call_const_claim_ref_payload[row] = ref.y;
            call_const_claim_identity_mode[row] = (constant_mask & (1u << slot)) != 0u
                ? constants[slot].identity_mode : 0u;
        }
    }
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    emit_argument_claims(linear_thread_id(dtid));
}
