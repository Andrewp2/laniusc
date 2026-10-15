import type_checker.constant_constraints;
// Bind a method receiver to its declaration-owned type and constant domains.
// This producer publishes accepted call facts before the independent return
// materializer reads them. Keeping matching out of materialization also keeps
// GPU driver compilation bounded for both traversals.
#include "../type/instances/materialize_application_inputs.slang"
import semantic_interface_layout;
import type_checker.methods.candidate;
import type_checker.calls.explicit_call_environment;
import type_checker.calls.mutable_checked_call_types;
import type_checker.calls.checked_call_environment;
import type_checker.calls.checked_constant_environment;
import type_checker.calls.contextual_call_environment;
import type_checker.calls.context_constant_publication;
import type_checker.scoped_type_constraints;

StructuredBuffer<uint> call_fn_index;
StructuredBuffer<uint> call_dependency_library_id;
StructuredBuffer<uint> call_dependency_unit_id;
StructuredBuffer<uint> call_dependency_local_index;
StructuredBuffer<uint> method_decl_receiver_ref_tag;
StructuredBuffer<uint> method_decl_receiver_ref_payload;
StructuredBuffer<uint> method_decl_receiver_mode;
StructuredBuffer<uint> method_decl_param_offset;
StructuredBuffer<uint> method_call_receiver_ref_tag;
StructuredBuffer<uint> method_call_receiver_ref_payload;
StructuredBuffer<MethodCandidate> method_candidate;
StructuredBuffer<uint> method_call_parameter_ref_tag;
StructuredBuffer<uint> method_call_parameter_ref_payload;
StructuredBuffer<uint> call_param_row_start;
StructuredBuffer<uint> call_param_row_count_out;
StructuredBuffer<uint> call_param_row_ref_tag;
StructuredBuffer<uint> call_param_row_ref_payload;
StructuredBuffer<uint> call_inference_state;

// The receiver's complete pattern establishes lexical impl bindings for
// both local and imported methods. Store them in the same call environment
// used by ordinary argument/result inference, never in positional type slots.
bool publish_receiver_bindings(uint call, uint token, uint2 inferred[32], uint mask,
    InferredConstant constants[32], uint constant_mask)
{
    for (uint slot = 0u; slot < 32u; slot++)
        if ((mask & (1u << slot)) != 0u)
        {
            // The checked receiver owns its impl parameters. Ordinary
            // argument claims can still contain default numeric literal types;
            // they receive this context before strict claim validation. An
            // independently typed conflicting argument remains an error there.
            // Explicit and checked contextual facts already have authority and
            // must each agree, even when both are present for the same slot.
            // Source 0 is explicit, source 1 contextual: one comparison site.
            [loop]
            for (uint source = 0u; source < 2u; source++)
            {
                uint2 prior; bool present;
                if (source == 0u)
                    present = checked_explicit_environment_argument(0x80000000u | token, slot, prior.x, prior.y);
                else
                    present = checked_context_environment_argument(0x80000000u | token, slot, prior.x, prior.y);
                if (present && !scoped_type_refs_equal<MutableCheckedTypeGraph>(prior.x, prior.y, INVALID,
                    inferred[slot].x, inferred[slot].y, INVALID,
                    mutable_type_capacity(), gParams.n_tokens)) return false;
            }
        }
    for (uint slot = 0u; slot < 32u; slot++)
        if ((constant_mask & (1u << slot)) != 0u)
        {
            uint2 prior; uint prior_mode; uint prior_claim;
            if (checked_call_environment_constant_binding(0x80000000u | token, slot,
                prior.x, prior.y, prior_mode, prior_claim))
            {
                InferredConstant retained = inferred_constant_reference(prior);
                retained.identity_mode = prior_mode;
                if (!merge_inferred_constant_claim<MutableCheckedTypeGraph>(retained,
                    constants[slot], gParams.n_tokens)) return false;
                constants[slot] = retained;
            }
        }
    for (uint slot = 0u; slot < 32u; slot++)
        if ((mask & (1u << slot)) != 0u)
        {
            call_context_ref_tag[call * 32u + slot] = inferred[slot].x;
            call_context_ref_payload[call * 32u + slot] = inferred[slot].y;
        }
    call_context_arg_mask[call] |= mask;
    if (!publish_context_constants<MutableCheckedTypeGraph, CheckedContextConstantAdmission>(call, constants, constant_mask, gParams.n_tokens))
    { record_min_token_error(status, token, 6u, 0x474e0001u); return false; }
    call_context_owner_by_token[token] = call;
    return true;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint call = dtid.x + dtid.y * 16776960u;
    if (call >= hir_count() || compact_hir_core[call].kind != 19u) return;
    uint callee = compact_hir_payload[call].a;
    if (callee >= hir_count()) return;
    uint kind = compact_hir_core[callee].kind;
    if (kind != 21u && kind != 22u && kind != 33u) return;
    uint token = kind == 21u ? compact_hir_payload[callee].c : compact_hir_payload[callee].d;
    if (token >= gParams.n_tokens) token = compact_hir_core[callee].token_start;
    if (token >= gParams.n_tokens) return;
    uint owner = checked_call_application_owner(token);
    uint2 inferred[32]; uint mask;
    InferredConstant constants[32]; uint constant_mask;
    uint environment = 0x80000000u | token;
    bool library = call_dependency_library_id[token] != INVALID;
    uint method = INVALID;
    if (library)
    {
        method = dependency_find_method(call_dependency_library_id[token],
            call_dependency_unit_id[token], call_dependency_local_index[token]);
        if (method >= dependency_member_count()) return;
    }
    // Phase 0 binds the receiver to the impl root without an environment.
    // Phase 1 matches the self parameter under the bindings phase 0 published.
    // One call site per matcher and publisher keeps one inlined copy of each.
    [loop]
    for (uint phase = 0u; phase < 2u; phase++)
    {
        bool run = false;
        uint canonical_environment = INVALID; uint first = INVALID;
        uint2 pattern = uint2(0u, INVALID); uint pattern_environment = INVALID;
        uint2 actual = uint2(0u, INVALID);
        if (phase == 0u)
        {
            if (library)
            {
                uint receiver_tag = method_call_receiver_ref_tag[owner];
                uint receiver = method_call_receiver_ref_payload[owner];
                if (receiver_tag == 0u || receiver == INVALID ||
                    (receiver_tag == 3u && receiver >= mutable_type_capacity())) return;
                first = dependency_member_word(method * SEMANTIC_INTERFACE_MEMBER_WORDS + 10u);
                actual = uint2(receiver_tag, receiver);
            }
            else
            {
                uint declaration = call_fn_index[token];
                if (declaration >= gParams.n_tokens || method_decl_receiver_ref_tag[declaration] == 0u ||
                    method_call_receiver_ref_tag[owner] == 0u) return;
                pattern = uint2(method_decl_receiver_ref_tag[declaration],
                    method_decl_receiver_ref_payload[declaration]);
                actual = uint2(method_call_receiver_ref_tag[owner], method_call_receiver_ref_payload[owner]);
            }
            run = true;
        }
        else
        {
            MethodCandidate candidate = method_candidate[owner];
            if (candidate.state != METHOD_CANDIDATE_UNIQUE || candidate.receiver_mode == 0u) return;
            uint2 parameter = uint2(method_call_parameter_ref_tag[owner], method_call_parameter_ref_payload[owner]);
            actual = parameter;
            if (library)
            {
                uint base = method * SEMANTIC_INTERFACE_MEMBER_WORDS;
                uint mode = (dependency_member_word(base + 8u) >> 28u) & 3u;
                if (mode == 1u || mode == 2u)
                {
                    // Portable parameter rows omit syntactic self. Its declared
                    // type is the full impl root, with one wrapper for &self.
                    // Remove exactly that wrapper from the accepted parameter,
                    // retaining any references that are part of the impl root.
                    if (mode == 2u)
                    {
                        if (actual.x == 3u && actual.y < mutable_type_capacity() &&
                            type_instance_kind[actual.y] == 4u)
                            actual = uint2(type_instance_elem_ref_tag[actual.y],
                                type_instance_elem_ref_payload[actual.y]);
                        else actual = uint2(0u, INVALID);
                    }
                    first = dependency_member_word(base + 10u);
                }
                else if (mode == 3u) first = dependency_method_parameter_type(method, 0u);
                canonical_environment = environment;
                run = first < dependency_type_count() && actual.x != 0u && actual.y != INVALID;
            }
            else
            {
                uint declaration = call_fn_index[token];
                if (declaration < gParams.n_tokens)
                {
                    uint mode = method_decl_receiver_mode[declaration];
                    if (mode == 1u)
                        pattern = uint2(method_decl_receiver_ref_tag[declaration],
                            method_decl_receiver_ref_payload[declaration]);
                    else if (mode == 2u)
                    {
                        // The method metadata producer owns this complete &ImplRoot
                        // graph. The unannotated self parameter row has no written
                        // type and is not an independent signature authority.
                        uint self_decl = method_decl_param_offset[declaration];
                        if (self_decl < gParams.n_tokens) pattern = uint2(3u, self_decl);
                    }
                    else if (mode == 3u)
                    {
                        uint first_param = call_param_row_start[declaration];
                        if (first_param < call_param_row_count_out[0u])
                            pattern = uint2(call_param_row_ref_tag[first_param],
                                call_param_row_ref_payload[first_param]);
                    }
                }
                pattern_environment = environment;
                run = pattern.x != 0u && pattern.y != INVALID;
            }
        }
        bool matches = false;
        if (run)
        {
            if (library)
                matches = canonical_type_and_constant_constraints<MutableCheckedCallTypeGraph>(
                    canonical_environment, first, actual.x, actual.y, mutable_type_capacity(),
                    gParams.n_tokens, true, inferred, mask, constants, constant_mask, true);
            else
                matches = scoped_type_and_constant_constraints<MutableCheckedCallTypeGraph>(
                    pattern.x, pattern.y, pattern_environment, actual.x, actual.y,
                    mutable_type_capacity(), gParams.n_tokens,
                    inferred, mask, constants, constant_mask, true);
        }
        if (matches) matches = publish_receiver_bindings(call, token, inferred, mask, constants, constant_mask);
        if (phase == 0u)
        {
            if (!matches) { record_min_token_error(status, token, 3u, 0u); return; }
        }
        else if (!matches && call_inference_state[0u] == 0u)
            record_min_token_error(status, token, 3u, 0u);
    }
}
