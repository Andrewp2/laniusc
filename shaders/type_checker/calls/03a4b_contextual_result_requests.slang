// Match local call returns against their complete receiving context over
// canonical IDs: the callee's declared result pattern against the receiving
// type (ct_match), and the bindings become the call's context
// (ct_publish_context; constants merge with the context table and are
// admitted later). Each call owns its accepted result constraints.
// Inference publishes all ordered bindings only after the entire graph has
// matched.
import hir_records;
import hir_expr_semantics;
import gpu_index;
import status;
import type_checker.mutable_checked_type_graph;
import type_checker.calls.contextual_call_environment;
import type_checker.argument_context;
import type_checker.canonical.canonical_api;
import type_checker.canonical.canonical_candidates;
import type_checker.canonical.canonical_mutable_rows;
import type_checker.substitution.ct_spare;
import type_checker.substitution.ct_checked;
import type_checker.substitution.ct_rows;
import type_checker.substitution.source_slots;
import type_checker.match.ct_match;
import type_checker.match.ct_context_publish;
import type_checker.match.field_expected;

struct Params { uint n_tokens; uint source_len; uint n_hir_nodes; };
ConstantBuffer<Params> gParams;
StructuredBuffer<uint> compact_hir_count;
StructuredBuffer<HirCore> compact_hir_core;
StructuredBuffer<HirPayload> compact_hir_payload;
StructuredBuffer<uint> compact_hir_nearest_fn;
StructuredBuffer<uint> compact_field_count;
StructuredBuffer<HirField> compact_fields;
StructuredBuffer<uint> compact_match_arm_count;
StructuredBuffer<HirMatchArm> compact_match_arms;
StructuredBuffer<uint> struct_init_field_expected_ref_tag;
StructuredBuffer<uint> struct_init_field_expected_ref_payload;
StructuredBuffer<uint> struct_init_field_expected_context_instance;
StructuredBuffer<uint> compact_array_element_start;
StructuredBuffer<uint> compact_array_element_count;
StructuredBuffer<uint> compact_array_element_row_count;
StructuredBuffer<HirArrayElement> compact_array_elements;
StructuredBuffer<uint> argument_expected_ref_tag;
StructuredBuffer<uint> argument_expected_ref_payload;
StructuredBuffer<uint> decl_type_ref_tag;
StructuredBuffer<uint> decl_type_ref_payload;
StructuredBuffer<uint> visible_decl;
StructuredBuffer<uint> member_result_ref_tag;
StructuredBuffer<uint> member_result_ref_payload;
StructuredBuffer<uint> call_fn_index;
StructuredBuffer<uint> call_intrinsic_tag;
StructuredBuffer<uint> fn_return_ref_tag;
StructuredBuffer<uint> fn_return_ref_payload;
StructuredBuffer<uint> type_expr_ref_tag;
StructuredBuffer<uint> type_expr_ref_payload;
StructuredBuffer<uint> call_inference_state;
StructuredBuffer<uint> call_inference_result_tag;
StructuredBuffer<uint> call_inference_result_payload;
RWStructuredBuffer<uint> call_result_instance;
RWStructuredBuffer<uint> aggregate_compare_scan_input;
RWStructuredBuffer<uint> status;
// The status words before this final invocation.
StructuredBuffer<uint> status_prior;

static const uint INVALID = 0xffffffffu;
[ForceInline]
uint active_hir_count() { return min(gParams.n_hir_nodes, compact_hir_count[0u]); }
[ForceInline]
bool valid_hir(uint node) { return node < active_hir_count(); }
[ForceInline]
bool valid_token(uint token) { return token < gParams.n_tokens; }
static const uint HIR_STMT = 7u;
static const uint HIR_LET_STMT = 8u;
static const uint HIR_RETURN_STMT = 9u;
uint checked_type_capacity() { return mutable_type_capacity(); }
#define CANONICAL_FIELD_EXPECTATION
#include "../result_expression_context.slang"

uint callee_token(uint call)
{
    uint callee = compact_hir_payload[call].a;
    // A member's leaf owns this call; its span can begin in a receiver call.
    if (valid_hir(callee) && compact_hir_core[callee].kind == 21u)
    {
        uint member_token = compact_hir_payload[callee].c;
        return valid_token(member_token) ? member_token : INVALID;
    }
    uint token = compact_hir_core[call].token_start;
    if (valid_token(token) && valid_token(call_fn_index[token])) return token;
    if (!valid_hir(callee)) return INVALID;
    token = compact_hir_payload[callee].d;
    if (!valid_token(token)) token = compact_hir_core[callee].token_start;
    return valid_token(token) ? token : INVALID;
}

// The final invocation's result mismatch, unless an error already recorded
// inside the call explains it (an argument that does not match its
// parameter, such as a length that does not fit): that error is the
// diagnostic.
void record_result_mismatch(uint call)
{
    HirCore core = compact_hir_core[call];
    if (call_inference_state[0u] == 0u && !error_recorded_within(status_prior, core.token_start, core.token_end))
        record_min_token_error(status, core.token_start, 3u, 0u);
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint node = linear_dispatch_thread_id_2d(dtid, 16776960u);
    if (!valid_hir(node)) return;
    uint kind = compact_hir_core[node].kind;
    if (kind == HIR_STMT || kind == HIR_LET_STMT || kind == HIR_RETURN_STMT)
    {
        // The complete matcher replaces legacy comparisons for direct local
        // aggregate results. A statement lane only owns its comparison row;
        // all result environments are published by the call lane below.
        HirPayload statement = compact_hir_payload[node];
        uint root = statement.a == 2u ? statement.b : statement.c;
        root = argument_context_root(root, active_hir_count(), compact_hir_core, compact_hir_payload);
        uint2 reference;
        if (valid_hir(root) && compact_hir_core[root].kind == 19u &&
            statement_expression_context(root, node, reference))
        {
            uint token = callee_token(root);
            uint function = valid_token(token) ? call_fn_index[token] : INVALID;
            if (valid_token(function) && fn_return_ref_tag[function] != 0u && fn_return_ref_tag[function] != 1u)
                aggregate_compare_scan_input[node] = 0u;
        }
        return;
    }
    if (kind != 19u) return;
    uint call = node;
    uint callee = callee_token(call);
    bool raw_view = valid_token(callee) && call_intrinsic_tag[callee] == 7u;
    uint function = valid_token(callee) ? call_fn_index[callee] : INVALID;
    if (!raw_view && (!valid_token(function) || fn_return_ref_tag[function] == 0u || fn_return_ref_tag[function] == 1u)) return;
    uint2 reference;
    // Receiving fields resolve under their nominal owner's environment. The
    // resulting reference is already in caller scope; only the return-pattern
    // matcher below suppresses provisional bindings of the called function.
    if (!result_expression_context<MutableCheckedTypeGraph>(call, checked_type_capacity(), reference)) return;
    uint tag = reference.x; uint expected = reference.y;
    if (tag == 0u || expected == INVALID || (tag == 3u && expected >= checked_type_capacity())) return;
    if (raw_view)
    {
        // A raw view has no typed input from which to infer its element. The
        // receiving context owns its complete result, as for an empty array.
        if (tag == 3u && type_instance_kind[expected] == 3u) call_result_instance[call] = expected;
        else record_result_mismatch(call);
        return;
    }
    SourceSlots slots;
    CtSpare spare = ct_spare_none();
    uint pattern = CT_UNKNOWN;
    uint actual = CT_UNKNOWN;
    uint environment = CT_MATCH_FAILED;
    uint count_mask = 0u;
    uint3 interned = uint3(0u, INVALID, CT_NONE);
    // One interning site serves the result pattern, the receiving type and
    // each prior operand the publisher asks for.
    uint2 operand = uint2(fn_return_ref_tag[function], fn_return_ref_payload[function]);
    uint outcome = CT_PUBLISH_REJECTED;
    [loop]
    for (uint work = 0u; work < 2u + CT_PUBLISH_REQUEST_LIMIT; work++)
    {
        uint id = ct_intern_checked<CtMutableRows>(operand.x, operand.y, spare.record);
        if (work == 0u)
        {
            pattern = id;
            operand = uint2(tag, expected);
            continue;
        }
        if (work == 1u)
        {
            actual = id;
            environment = ct_is_resolved(pattern) && ct_is_resolved(actual)
                ? ct_match<SourceSlots>(slots, pattern, actual, CT_NONE, CT_NONE, CT_NONE, 0u, true,
                    spare, count_mask)
                : CT_MATCH_FAILED;
            // An interning overflow retries the job with larger tables.
            if (environment == CT_MATCH_OVERFLOW) return;
            if (!ct_is_record(environment)) break;
        }
        // A prior that has no ID agrees with no binding.
        else if (!ct_is_resolved(id)) { outcome = CT_PUBLISH_REJECTED; break; }
        else interned = uint3(operand, id);
        uint3 words = ct_words(environment);
        outcome = ct_publish_context<CtNoClaims>(call, callee, environment, words.y, words.z,
            count_mask, 0u, interned, operand);
        if (outcome != CT_PUBLISH_INTERN) break;
    }
    if (!ct_is_record(environment))
    {
        // Parameter contexts can still change while their enclosing call's
        // argument facts settle. A failed provisional comparison publishes
        // nothing; the final invocation diagnoses against the closed facts.
        record_result_mismatch(call);
        return;
    }
    // A row another lane is writing settles in a later round.
    if (outcome == CT_PUBLISH_BUSY) return;
    if (outcome != CT_PUBLISHED)
    { record_min_token_error(status, compact_hir_core[call].token_start, 6u, 0x474e0001u); return; }
    call_context_owner_by_token[callee] = call;
    uint callee_node = compact_hir_payload[call].a;
    // A dotted call's leading tokens belong to its receiver expression.
    // Only nonmember calls publish their existing qualified-owner aliases.
    if (valid_hir(callee_node) && compact_hir_core[callee_node].kind != 21u)
    {
        uint head = compact_hir_core[callee_node].token_start;
        uint call_token = compact_hir_core[call].token_start;
        if (valid_token(head)) call_context_owner_by_token[head] = call;
        if (valid_token(call_token)) call_context_owner_by_token[call_token] = call;
    }
    if (tag == 3u) call_result_instance[call] = expected;
}
