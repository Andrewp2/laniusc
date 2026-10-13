import type_checker.dependencies.constant_view;
// Expected argument types are checked caller-side references. Each argument
// owns one row; imported patterns are consumed only on their declaration page.
// This relation provides context to expressions without replacing their
// accepted actual types or inferring a type from native storage width.
#include "../type/instances/materialize_application_inputs.slang"
import type_checker.calls.mutable_checked_call_types;
import type_checker.calls.checked_call_environment;
import type_checker.calls.checked_constant_environment;
import type_checker.argument_context;
import primitive_types;
#include "../type/instances/materialize_application.slang"
#include "array_shape_context.slang"

StructuredBuffer<uint> call_arg_row_node;
StructuredBuffer<uint> call_arg_row_call_node;
StructuredBuffer<uint> call_arg_row_ordinal;
StructuredBuffer<uint> call_arg_param_row;
StructuredBuffer<uint> call_param_row_count_out;
StructuredBuffer<uint> call_param_row_ref_tag;
StructuredBuffer<uint> call_param_row_ref_payload;
StructuredBuffer<uint> call_dependency_library_id;
StructuredBuffer<uint> call_dependency_unit_id;
StructuredBuffer<uint> call_dependency_local_index;
StructuredBuffer<uint> call_generic_claim_arg_row;
StructuredBuffer<uint> call_arg_row_literal_context_mask;
RWStructuredBuffer<uint> argument_expected_ref_tag;
RWStructuredBuffer<uint> argument_expected_ref_payload;
RWStructuredBuffer<uint> call_inference_state;

// Numeric literals can receive context within their category. Named values,
// Boolean literals, and structural values keep their known types. The owning expression pass
// supplies provenance without adding HIR bindings to every environment consumer.
public struct ArgumentContextClaimPriority : ICheckedCallClaimPriority
{
    public static uint rank(uint row)
    {
        uint scalar = call_generic_claim_ref_payload[row];
        if (call_generic_claim_ref_tag[row] != 1u || (!scalar_is_integer(scalar) && !scalar_is_float(scalar))) return 0u;
        uint argument = call_generic_claim_arg_row[row];
        if (argument >= min(call_arg_row_count_out[0u], gParams.n_hir_nodes)) return 0u;
        return (call_arg_row_literal_context_mask[argument] & (scalar_is_float(scalar) ? 2u : 1u)) != 0u ? 1u : 0u;
    }
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint row = dtid.x + dtid.y * 16776960u;
    if (row >= min(call_arg_row_count_out[0u], gParams.n_hir_nodes)) return;
    uint call = call_arg_row_call_node[row];
    uint node = argument_context_root(call_arg_row_node[row], hir_count(),
        compact_hir_core, compact_hir_payload);
    if (call >= hir_count() || node >= hir_count()) return;
    uint callee = compact_hir_payload[call].a;
    if (callee >= hir_count()) return;
    bool dotted = compact_hir_core[callee].kind == 21u;
    uint token = dotted ? compact_hir_payload[callee].c : compact_hir_payload[callee].d;
    if (token >= gParams.n_tokens) token = compact_hir_core[callee].token_start;
    if (token >= gParams.n_tokens) return;
    uint tag = 0u; uint payload = INVALID;
    if (call_dependency_library_id[token] != INVALID)
    {
        uint declaration = dependency_find_declaration(call_dependency_library_id[token],
            call_dependency_unit_id[token], call_dependency_local_index[token]);
        uint ordinal = call_arg_row_ordinal[row];
        if (declaration < dependency_declaration_count())
        {
            uint signature = canonical_field_root(dependency_declaration_word(declaration * 14u + 7u));
            if (signature == INVALID || dependency_type_word(signature * 9u) != 7u) return;
            uint start = dependency_type_word(signature * 9u + 3u);
            uint count = dependency_type_word(signature * 9u + 4u);
            uint edges = dependency_count(5u);
            if (count == 0u || ordinal >= count - 1u || start > edges || count > edges - start) return;
            payload = dependency_type_edge_word(start + ordinal);
        }
        else
        {
            uint method = dependency_find_method(call_dependency_library_id[token],
                call_dependency_unit_id[token], call_dependency_local_index[token]);
            if (method >= dependency_member_count()) return;
            payload = dependency_method_parameter_type(method, ordinal + (dotted ? 1u : 0u));
        }
        if (payload >= dependency_type_count()) return;
        tag = 5u;
    }
    else
    {
        uint parameter = call_arg_param_row[row];
        if (parameter >= min(call_param_row_count_out[0u], gParams.n_hir_nodes)) return;
        tag = call_param_row_ref_tag[parameter];
        payload = call_param_row_ref_payload[parameter];
    }
    uint environment = 0x80000000u | token;
    uint prior_tag = argument_expected_ref_tag[node];
    uint prior = argument_expected_ref_payload[node];
    if (prior_tag != 0u && ((tag == 5u && prior_tag == 3u &&
        canonical_field_ref_matches<MutableCheckedExpectedCallTypeGraph<ArgumentContextClaimPriority>>(environment, payload, prior,
            mutable_type_capacity(), gParams.n_tokens)) ||
        (tag != 5u && scoped_type_refs_equal<MutableCheckedExpectedCallTypeGraph<ArgumentContextClaimPriority>>(tag, payload, environment,
            prior_tag, prior, INVALID, mutable_type_capacity(), gParams.n_tokens)))) return;
    uint created[DEPTH_LIMIT]; uint count = 0u; uint failure; uint2 expected;
    uint lengths[DEPTH_LIMIT]; uint previous[DEPTH_LIMIT]; uint depth = 0u;
    uint3 reference = uint3(tag, payload, environment);
    uint3 leaf; uint shape_failure;
    bool shaped = compact_hir_core[node].kind == 24u &&
        prepare_array_shape_context(reference, node, prior_tag == 3u ? prior : INVALID,
            leaf, lengths, previous, depth, shape_failure);
    if (compact_hir_core[node].kind == 24u && !shaped && (shape_failure == 1u || shape_failure == 2u))
    {
        record_min_token_error(status, token, 6u, 0x474e0000u | shape_failure);
        return;
    }
    if (shaped) reference = leaf;
    if (!materialize<MutableCheckedExpectedCallTypeGraph<ArgumentContextClaimPriority>>(reference,
        created, count, expected, failure))
    {
        // Context is optional until bindings become known. Capacity failures
        // have an explicit diagnostic; ordinary call validation owns missing
        // required bindings and actual argument mismatches.
        if (failure == 1u || failure == 2u)
            record_min_token_error(status, token, 6u, 0x474e0000u | failure);
        return;
    }
    if (shaped && !wrap_array_shape_context<MutableCheckedExpectedCallTypeGraph<ArgumentContextClaimPriority>>(
        depth, lengths, previous, expected, failure))
    {
        if (failure == 1u || failure == 2u)
            record_min_token_error(status, token, 6u, 0x474e0000u | failure);
        return;
    }
    argument_expected_ref_tag[node] = expected.x;
    argument_expected_ref_payload[node] = expected.y;
    // Both rows are caller-side materialized references. Change detection
    // compares their concrete structure without reading the call environment.
    if (!concrete_type_refs_equal<MutableCheckedTypeGraph>(prior_tag, prior,
        expected.x, expected.y, mutable_type_capacity()))
    { uint ignored; InterlockedAdd(call_inference_state[1u], 1u, ignored); }
}
