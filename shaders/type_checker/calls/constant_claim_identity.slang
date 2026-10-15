import primitive_types;
import type_checker.concrete_type_equality;
// Published claim provenance authorizes an evidence merge, never a change to
// ordinary typed constant identity. Source refs keep their original fit graph.
import type_checker.constant_atoms_identity;

public bool checked_constant_claim_descriptor(uint2 reference, uint identity_mode,
    uint tokens, out ConstantReferenceDescriptor descriptor, out uint scalar)
{
    descriptor = (ConstantReferenceDescriptor)0; scalar = 0u;
    return identity_mode <= 1u &&
        inspect_constant_reference<CheckedSourceConstantGraph, CheckedSourceConstantEnvironment>(
            uint3(reference, 0u), tokens, descriptor) &&
        constant_descriptor_result_scalar<CheckedSourceConstantGraph>(descriptor, scalar) &&
        (identity_mode == 0u || scalar_is_integer(scalar));
}

// The claim is a valid constant reference with a result scalar, which is an
// integer for a count claim.
public bool checked_constant_claim_admitted(uint2 reference, uint identity_mode, uint tokens)
{
    ConstantReferenceDescriptor descriptor; uint scalar;
    return checked_constant_claim_descriptor(reference, identity_mode, tokens, descriptor, scalar);
}

public bool checked_constant_claims_compatible(uint2 left, uint left_mode,
    uint2 right, uint right_mode, uint tokens)
{
    ConstantReferenceDescriptor a; ConstantReferenceDescriptor b;
    uint left_scalar; uint right_scalar;
    return checked_constant_claim_descriptor(left, left_mode, tokens, a, left_scalar) &&
        checked_constant_claim_descriptor(right, right_mode, tokens, b, right_scalar) &&
        left_scalar == right_scalar &&
        constant_reference_descriptors_equal<CheckedSourceConstantGraph, CheckedSourceConstantEnvironment,
            CheckedSourceConstantGraph, CheckedSourceConstantEnvironment>(a, b, tokens,
                left_mode == 1u || right_mode == 1u);
}
