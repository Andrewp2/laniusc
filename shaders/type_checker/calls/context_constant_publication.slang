import type_checker.constant_constraints;
import type_checker.concrete_type_equality;
import type_checker.scoped_type_equality;
import type_checker.constant_publication;
import type_checker.constant_atoms_identity;
import type_checker.calls.constant_claim_identity;
// Producers publish accepted contextual constants. Environment binding readers
// load a per-slot admission bit (the published reference passes the checked
// constant descriptor in its identity mode) instead of re-inspecting it.
import type_checker.calls.contextual_call_environment;

public interface IContextConstantAdmission
{
    // Records the admission bits of the published slots in `mask`.
    static void record(uint call, uint mask, uint2 published[32], uint modes[32]);
}

// For producers whose own dispatch reads call bindings after publishing.
public struct CheckedContextConstantAdmission : IContextConstantAdmission
{
    public static void record(uint call, uint mask, uint2 published[32], uint modes[32])
    {
        uint tokens = checked_source_constant_parameter_capacity();
        uint valid = 0u;
        [loop]
        for (uint slot = 0u; slot < 32u; slot++)
            if ((mask & (1u << slot)) != 0u)
            {
                ConstantReferenceDescriptor descriptor; uint scalar;
                if (checked_constant_claim_descriptor(published[slot], modes[slot], tokens,
                    descriptor, scalar)) valid |= 1u << slot;
            }
        call_context_constant_valid_mask[call] = (call_context_constant_valid_mask[call] & ~mask) | valid;
    }
}

// For producers followed directly by 03a4c_admit_context_constants, which
// rewrites every present bit. No binding reader runs in between.
public struct DeferredContextConstantAdmission : IContextConstantAdmission
{
    public static void record(uint call, uint mask, uint2 published[32], uint modes[32]) {}
}

public bool publish_context_constants<Graph : IParameterScopedTypeGraph,
    Admission : IContextConstantAdmission>(
    uint call, InferredConstant constants[32], uint mask, uint tokens)
{
    uint2 published[32]; uint modes[32];
    for (uint slot = 0u; slot < 32u; slot++)
        if ((mask & (1u << slot)) != 0u)
        {
            uint2 prior = (call_context_constant_mask[call] & (1u << slot)) != 0u
                ? uint2(call_context_constant_kind[call * 32u + slot], call_context_constant_payload[call * 32u + slot])
                : uint2(0u, 0xffffffffu);
            InferredConstant request = constants[slot];
            if (prior.x != 0u)
            {
                uint prior_mode = call_context_constant_identity_mode[call * 32u + slot];
                if (prior_mode > 1u) return false;
                if (prior_mode != request.identity_mode)
                {
                    InferredConstant retained = inferred_constant_reference(prior);
                    retained.identity_mode = prior_mode;
                    if (!merge_inferred_constant_claim<Graph>(retained, request, tokens)) return false;
                    request = retained;
                }
            }
            // Same-mode publications replace a producer's provisional snapshot.
            // Mixed count/exact evidence retains the compatible exact request.
            if (!publish_inferred_constant<Graph>(request, tokens, prior, published[slot])) return false;
            modes[slot] = request.identity_mode;
        }
    for (uint slot = 0u; slot < 32u; slot++)
        if ((mask & (1u << slot)) != 0u)
        {
            call_context_constant_kind[call * 32u + slot] = published[slot].x;
            call_context_constant_payload[call * 32u + slot] = published[slot].y;
            call_context_constant_identity_mode[call * 32u + slot] = modes[slot];
        }
    Admission.record(call, mask, published, modes);
    call_context_constant_mask[call] |= mask;
    return true;
}
