// Record, for every present contextual constant of a call or record row,
// whether its published reference passes the checked constant descriptor in
// its identity mode. Runs directly after producers that publish with deferred
// admission; environment binding readers load these bits and never inspect
// contextual references again. Presence and admission stay distinct: a
// present but inadmissible binding still rejects.
import type_checker.concrete_type_equality;
import type_checker.calls.constant_claim_identity;
import type_checker.constant_atoms_identity;

struct Params { uint n_tokens; uint source_len; uint n_hir_nodes; };
ConstantBuffer<Params> gParams;
StructuredBuffer<uint> call_context_constant_mask;
StructuredBuffer<uint> call_context_constant_kind;
StructuredBuffer<uint> call_context_constant_payload;
StructuredBuffer<uint> call_context_constant_identity_mode;
RWStructuredBuffer<uint> call_context_constant_valid_mask;

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint call = dtid.x + dtid.y * 16776960u;
    uint capacity; uint stride;
    call_context_constant_mask.GetDimensions(capacity, stride);
    if (call >= gParams.n_hir_nodes || call >= capacity) return;
    uint mask = call_context_constant_mask[call];
    if (mask == 0u) return;
    uint tokens = checked_source_constant_parameter_capacity();
    uint valid = 0u;
    [loop]
    for (uint slot = 0u; slot < 32u; slot++)
        if ((mask & (1u << slot)) != 0u)
        {
            uint row = call * 32u + slot;
            ConstantReferenceDescriptor descriptor; uint scalar;
            if (checked_constant_claim_descriptor(
                uint2(call_context_constant_kind[row], call_context_constant_payload[row]),
                call_context_constant_identity_mode[row], tokens, descriptor, scalar))
                valid |= 1u << slot;
        }
    call_context_constant_valid_mask[call] = valid;
}
