import type_checker.constant_parameter_slots;
// Row-dispatched direct call argument validation and generic inference over
// canonical IDs.
//
// Argument-to-parameter matching is built before this pass by the compact
// linked-list matcher. This pass consumes that relation and owns validation,
// generic claim marking, and per-argument diagnostics. A parameter pattern's
// slot masks size its claim spans (ct_pattern_masks); the argument is matched
// against it once (ct_match) for the closed-pattern mismatch and the legacy
// scalar slot cache. Claims themselves are emitted by 03a1.

import dependency_interface;
import type_checker.calls.parameter_pattern_page;
import hir_records;
import atomics;
import hir_expr_semantics;
import type_checker.checked_index_reference;
import type_checker.checked_type_graph;
import type_checker.canonical.canonical_api;
import type_checker.canonical.canonical_candidates;
import type_checker.canonical.canonical_checked_rows;
import type_checker.canonical.canonical_dependency;
import type_checker.substitution.ct_spare;
import type_checker.substitution.ct_checked;
import type_checker.match.ct_match;
import constant_value;
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
StructuredBuffer<uint> call_arg_row_count_out;
StructuredBuffer<uint> call_arg_row_node;
StructuredBuffer<uint> call_arg_row_call_node;
StructuredBuffer<uint> call_arg_param_row;
RWStructuredBuffer<uint> call_generic_claim_scan_input;
RWStructuredBuffer<uint> call_generic_claim_pattern_mask;
StructuredBuffer<uint> call_intrinsic_tag;
StructuredBuffer<uint> call_fn_index;
StructuredBuffer<uint> call_dependency_library_id;
StructuredBuffer<uint> call_dependency_unit_id;
StructuredBuffer<uint> call_dependency_local_index;
StructuredBuffer<uint> call_result_instance;
StructuredBuffer<uint> call_inference_state;
StructuredBuffer<uint> method_call_name_id;
RWStructuredBuffer<uint> call_return_type;
StructuredBuffer<uint> call_return_type_token;
StructuredBuffer<uint> call_return_generic_slot;
StructuredBuffer<uint> fn_return_ref_tag;
StructuredBuffer<uint> fn_return_ref_payload;
StructuredBuffer<uint> visible_decl;
StructuredBuffer<uint> visible_type;
StructuredBuffer<uint> decl_type_ref_tag;
StructuredBuffer<uint> decl_type_ref_payload;
StructuredBuffer<uint> member_result_ref_tag;
StructuredBuffer<uint> member_result_ref_payload;
StructuredBuffer<uint> semantic_expr_ref_tag_by_hir;
StructuredBuffer<uint> semantic_expr_ref_payload_by_hir;
StructuredBuffer<uint> call_param_row_ordinal;
StructuredBuffer<uint> call_param_row_type;
StructuredBuffer<uint> call_param_row_ref_tag;
StructuredBuffer<uint> call_param_row_ref_payload;
RWStructuredBuffer<uint> call_generic_slot_type;
RWStructuredBuffer<uint> call_generic_slot_ordinal;
RWStructuredBuffer<uint> call_generic_return_arg_node;
RWStructuredBuffer<uint> call_const_claim_scan_input;
RWStructuredBuffer<uint> call_const_claim_pattern_mask;
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
static const uint TY_UINT = 4u;
static const uint TY_FLOAT = 5u;
static const uint TY_CHAR = 6u;
static const uint TY_STRING = 7u;
static const uint TY_POINTER = 8u;
static const uint TY_ARRAY_BASE = 128u;
static const uint TY_STRUCT_BASE = 4096u;
static const uint TY_GENERIC_BASE = 8192u;

static const uint TYPE_REF_INVALID = 0u;
static const uint TYPE_REF_SCALAR = 1u;
static const uint TYPE_REF_GENERIC_PARAM = 2u;
static const uint TYPE_REF_INSTANCE = 3u;
static const uint TYPE_REF_ERROR = 4u;
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
static const uint TYPE_LEN_LITERAL = 1u;
static const uint TYPE_LEN_CONST_PARAM = 2u;

static const uint ERR_ASSIGN_MISMATCH = 3u;
static const uint PARAM_CACHE_STRIDE = 4u;
static const uint INTRINSIC_NONE = 0u;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

uint parameter_type_capacity() { return checked_type_capacity(); }
#define ARGUMENT_TYPE_GRAPH ScopedCheckedTypeGraph
#include "argument_value_reference.slang"
#include "argument_pattern_ids.slang"

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

bool scalar_argument_matches(uint expected, uint tag, uint payload, uint source_node)
{
    if (tag != TYPE_REF_SCALAR) return false;
    if (expected == payload) return true;
    // The null-pointer spelling is the sole implicit scalar exception. Check
    // both magnitude limbs; a nonzero high limb must never become null.
    if (expected == TY_POINTER && payload == TY_INT)
    {
        uint node = resolve_expr(source_node);
        return valid_node(node) && compact_hir_core[node].kind == 23u &&
            expr_form(node) == HIR_EXPR_INT && compact_hir_payload[node].b == 0u &&
            compact_hir_payload[node].c == 0u;
    }
    return false;
}

uint call_arg_error_token(uint arg_node, uint callee_i)
{
    return valid_node(arg_node) ? compact_hir_core[arg_node].token_start : callee_i;
}

void claim_generic_slot(
    uint callee_i,
    uint slot,
    uint arg_ty,
    uint arg_token,
    uint param_ordinal)
{
    if (slot >= PARAM_CACHE_STRIDE)
        return;

    uint state_i = callee_i * PARAM_CACHE_STRIDE + slot;
    if (arg_ty == TY_UNKNOWN)
    {
        uint prior_ordinal = atomic_u32_min(
            call_generic_slot_ordinal,
            state_i,
            param_ordinal);
        if (prior_ordinal == INVALID || param_ordinal < prior_ordinal)
            call_generic_slot_type[state_i] = INVALID;
        return;
    }

    uint prior_ordinal = atomic_u32_min(
        call_generic_slot_ordinal,
        state_i,
        param_ordinal);
    if (prior_ordinal == INVALID || param_ordinal < prior_ordinal)
    {
        call_generic_slot_type[state_i] = arg_ty;
        return;
    }

    uint prior = call_generic_slot_type[state_i];
    if (prior == INVALID)
    {
        if (prior_ordinal == param_ordinal)
            call_generic_slot_type[state_i] = arg_ty;
        return;
    }

    // This cache publishes a provisional type for later call-result
    // projection. Stable same-call consistency is checked from compact claims
    // after collection; values observed while nested calls are still refining
    // are not diagnostics.
}

void collect_row_argument(uint row)
{
    if (row >= call_arg_row_count_out[0u]) return;
    uint call = call_arg_row_call_node[row];
    uint node = call_arg_row_node[row];
    uint callee = callee_token_for_hir_call(call);
    uint param = call_arg_param_row[row];
    if (!valid_node(call) || !valid_node(node) || !valid_token(callee) ||
        call_intrinsic_tag[callee] != INTRINSIC_NONE || param == INVALID) return;
    if (!parameter_pattern_page_contains(call_dependency_library_id[callee],
        call_dependency_unit_id[callee], call_dependency_local_index[callee])) return;
    uint error_token = call_arg_error_token(node, callee);
    uint type = call_param_row_type[param];
    uint tag = call_param_row_ref_tag[param];
    uint payload = call_param_row_ref_payload[param];
    bool reference = tag == 3u && payload < parameter_type_capacity() &&
        type_instance_kind[payload] == 4u;
    if (tag == 5u)
    {
        uint count = dependency_type_count();
        uint root = payload < count ? canonical_type_roots[payload] : INVALID;
        reference = root < count && dependency_type_word(root * 9u) == 6u;
    }
    // Transparent aliases have already been resolved by type checking. Their
    // source-level arguments are not nominal call constraints.
    if (type != 0u && type < 128u && !reference)
    {
        // Collection precedes literal-context and expression projection in
        // each inference round. Only the strict pass consumes the converged
        // accepted reference; default literal codes are not argument types.
        if (call_inference_state[0u] != 0u) return;
        uint actual_tag; uint actual_payload;
        if (!argument_result_reference(resolve_expr(node), actual_tag, actual_payload) ||
            !scalar_argument_matches(type, actual_tag, actual_payload, node))
            record_error(error_token, ERR_ASSIGN_MISMATCH,
                actual_tag == TYPE_REF_SCALAR ? type * 256u + actual_payload : 0u);
        return;
    }
    if (tag == 0u || payload == INVALID) return;
    ClaimSlots slots;
    CtSpare spare = ct_spare_none();
    uint actual_tag; uint actual_payload;
    bool known = argument_value_reference(node, actual_tag, actual_payload);
    // Interned at one site: the parameter pattern, then the argument.
    uint pattern = CT_UNKNOWN;
    uint actual = CT_UNKNOWN;
    for (uint step = 0u; step < (known ? 2u : 1u); step++)
    {
        uint id = operand_id<CtCheckedRows>(step == 0u ? uint2(tag, payload)
            : uint2(actual_tag, actual_payload), spare);
        if (step == 0u) pattern = id;
        else actual = id;
    }
    // The slots a pattern uses do not depend on the argument: they size its
    // claim spans before any argument type is known.
    uint mask; uint constant_mask;
    if (!ct_pattern_masks<ClaimSlots>(slots, pattern, mask, constant_mask))
    { record_error(error_token, 6u, 0x474e0000u | (ct_is_resolved(pattern) ? 3u : 4u)); return; }
    call_generic_claim_pattern_mask[row] = mask;
    call_generic_claim_scan_input[row] = countbits(mask);
    call_const_claim_pattern_mask[row] = constant_mask;
    call_const_claim_scan_input[row] = countbits(constant_mask);
    uint fn = call_fn_index[callee];
    uint param_slot = generic_slot_for_type_ref(tag, payload);
    if (valid_token(fn) && param_slot != INVALID &&
        param_slot == generic_slot_for_type_ref(fn_return_ref_tag[fn], fn_return_ref_payload[fn]))
    {
        uint ignored;
        InterlockedMin(call_generic_return_arg_node[call], node, ignored);
    }
    // An argument without an ID yet is matched in a later round.
    if (!ct_is_resolved(actual)) return;
    // Only the legacy cache's four scalar slots need bindings. A parameter
    // root binds the argument itself, so its match interns nothing.
    bool root = ct_is_type_param(pattern);
    bool intern = !root && (mask & 0xfu) != 0u;
    uint count_mask;
    uint environment = ct_match<ClaimSlots>(slots, pattern, actual, CT_NONE, CT_NONE, CT_NONE,
        CT_MATCH_SLICE_ROOT0, intern, spare, count_mask);
    // An interning overflow retries the job with larger tables.
    if (environment == CT_MATCH_OVERFLOW) return;
    bool matches = intern ? ct_is_record(environment) : environment == CT_MATCH_OK;
    if (mask == 0u && constant_mask == 0u && !matches)
        record_error(error_token, ERR_ASSIGN_MISMATCH, 0u);
    if (!matches) return;
    // Legacy scalar consumers get only projections of complete structural
    // bindings. These four cache slots do not validate any parameter.
    for (uint slot = 0u; slot < 4u; slot++)
    {
        if ((mask & (1u << slot)) == 0u) continue;
        uint code = 0u;
        if (root) code = actual_tag == TYPE_REF_SCALAR ? actual_payload : 0u;
        else if (intern)
        {
            uint binding = ct_env_binding(environment, slot, false);
            code = ct_kind(binding) == CT_KIND_SCALAR ? ct_words(binding).x : 0u;
        }
        if (code != 0u)
            claim_generic_slot(callee, slot, code, error_token, call_param_row_ordinal[param]);
    }
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    collect_row_argument(linear_thread_id(dtid));
}
