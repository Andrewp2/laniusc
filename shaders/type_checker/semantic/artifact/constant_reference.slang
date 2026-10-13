import type_checker.concrete_type_equality;
// Project a checked scalar constant reference after body substitution. Source
// references remain immutable; the selected body supplies parameter atoms.
import type_checker.constant_atoms_identity;

// (scalar, low bits, high bits, presence). The symbolic marker records a value
// dependency for native body closure; its declaration token is never executable
// bits. Unresolved projections publish no expression value here: their complete
// root/target/fit identity remains in the retained checked constant graph. Native
// replay must normalize that graph before requesting an executable body.
public uint4 project_checked_constant_value(uint kind, uint payload, uint token_capacity)
{
    ConstantReferenceDescriptor descriptor;
    if (!inspect_constant_reference<CheckedSourceConstantGraph,
        CheckedSourceConstantEnvironment>(uint3(kind, payload, 0u), token_capacity, descriptor))
        return uint4(0u, 0u, 0u, 0u);
    if (descriptor.disposition == CONSTANT_REFERENCE_CONCRETE && descriptor.pending_fit == 0u)
        return uint4(descriptor.value, 0x80000000u);
    if (kind == 2u && descriptor.disposition == CONSTANT_REFERENCE_SYMBOLIC && descriptor.terminal.x == 2u)
    {
        uint scalar = constant_reference_scalar<CheckedSourceConstantGraph>(descriptor.root.xy);
        return uint4(scalar, descriptor.terminal.y, 0u, 0x20000000u);
    }
    return uint4(0u, 0u, 0u, 0u);
}
