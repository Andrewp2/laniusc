// Record, once per explicit-binding publication, whether each constant binding
// of an applying owner passes the checked constant descriptor. Environment
// binding readers load this admission instead of inspecting the reference at
// every substitution step; a present but inadmissible binding still rejects.
import type_checker.concrete_type_equality;
import type_checker.calls.constant_claim_identity;
import type_checker.constant_atoms_identity;

struct Params { uint n_tokens; uint source_len; uint n_hir_nodes; };
ConstantBuffer<Params> gParams;
StructuredBuffer<uint> call_explicit_application_status;
StructuredBuffer<uint4> call_explicit_environment;
StructuredBuffer<uint> call_explicit_binding_tag;
StructuredBuffer<uint> call_explicit_binding_payload;
RWStructuredBuffer<uint> call_explicit_constant_valid_mask;

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint token = dtid.x + dtid.y * 16776960u;
    uint capacity; uint stride;
    call_explicit_application_status.GetDimensions(capacity, stride);
    if (token >= gParams.n_tokens || token >= capacity) return;
    uint valid = 0u;
    uint4 descriptor = call_explicit_environment[token];
    if (call_explicit_application_status[token] == 1u && descriptor.x != 0u)
    {
        uint tokens = checked_source_constant_parameter_capacity();
        call_explicit_binding_tag.GetDimensions(capacity, stride);
        uint start = descriptor.x - 1u;
        uint ordinal = countbits(descriptor.z);
        [loop]
        for (uint slot = 0u; slot < 32u; slot++)
            if ((descriptor.w & (1u << slot)) != 0u)
            {
                // Same row and kind decoding as explicit_environment_binding.
                if (ordinal < descriptor.y && start < capacity && ordinal < capacity - start)
                {
                    uint row = start + ordinal;
                    uint2 reference = uint2(call_explicit_binding_tag[row] & 0x7fffffffu,
                        call_explicit_binding_payload[row]);
                    ConstantReferenceDescriptor checked; uint scalar;
                    if (checked_constant_claim_descriptor(reference, 0u, tokens, checked, scalar))
                        valid |= 1u << slot;
                }
                ordinal++;
            }
    }
    call_explicit_constant_valid_mask[token] = valid;
}
