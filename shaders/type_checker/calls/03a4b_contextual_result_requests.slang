import type_checker.constant_constraints;
// Match local call returns against their complete receiving context. Each
// call owns its accepted result constraints. Inference publishes
// all ordered bindings only after the entire graph has matched.
import hir_records;
import hir_expr_semantics;
import gpu_index;
import status;
import type_checker.calls.checked_call_type_graph;
import type_checker.checked_type_graph;
import type_checker.calls.contextual_call_environment;
import type_checker.scoped_type_constraints;
import type_checker.argument_context;

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
StructuredBuffer<uint> type_instance_lookup_head;
StructuredBuffer<uint> type_instance_lookup_next;
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
    if (!result_expression_context<ScopedCheckedTypeGraph>(call, checked_type_capacity(), reference)) return;
    uint tag = reference.x; uint expected = reference.y;
    if (tag == 0u || expected == INVALID || (tag == 3u && expected >= checked_type_capacity())) return;
    if (raw_view)
    {
        // A raw view has no typed input from which to infer its element. The
        // receiving context owns its complete result, as for an empty array.
        if (tag == 3u && type_instance_kind[expected] == 3u) call_result_instance[call] = expected;
        else if (call_inference_state[0u] == 0u)
            record_min_token_error(status, compact_hir_core[call].token_start, 3u, 0u);
        return;
    }
    uint2 inferred[32]; uint mask; InferredConstant constants[32]; uint constant_mask;
    if (!scoped_type_and_constant_constraints<ScopedDeclaredResultTypeGraph>(
        fn_return_ref_tag[function], fn_return_ref_payload[function], 0x80000000u | callee,
        tag, expected, checked_type_capacity(), gParams.n_tokens, inferred, mask,
        constants, constant_mask, true))
    {
        // Parameter contexts can still change while their enclosing call's
        // argument facts settle. A failed provisional comparison publishes
        // nothing; the final invocation diagnoses against the closed facts.
        if (call_inference_state[0u] == 0u)
            record_min_token_error(status, compact_hir_core[call].token_start, 3u, 0u);
        return;
    }
    for (uint slot = 0u; slot < 32u; slot++)
        if ((mask & (1u << slot)) != 0u)
        {
            call_context_ref_tag[call * 32u + slot] = inferred[slot].x;
            call_context_ref_payload[call * 32u + slot] = inferred[slot].y;
        }
    call_context_arg_mask[call] |= mask;
    if (!publish_context_constants<ScopedDeclaredResultTypeGraph>(call, constants, constant_mask, gParams.n_tokens))
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
