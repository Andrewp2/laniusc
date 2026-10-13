import constant_value;
import type_checker.concrete_type_equality;
import type_checker.constant_atoms;
// Copy a checked constant recipe into immutable source-owned storage after
// applying its declaration environment exactly once. Portable overlay rows
// and substitution environments never escape this publication boundary.
import type_checker.constant_atoms_identity;
import type_checker.constant_publication;

public bool materialize_checked_constant<Graph : IConstantIdentityGraph,
    Environment : IConstantReferenceEnvironment>(uint3 input, uint tokens,
    out uint2 reference, out uint failure)
{
    reference = uint2(0u, 0xffffffffu); failure = 3u;
    ConstantReferenceDescriptor descriptor;
    if (!inspect_constant_reference<Graph, Environment>(input, tokens, descriptor)) return false;
    // A valid caller-owned recipe can be retained only when its complete
    // unbound meaning equals the requested graph under the selected environment.
    ConstantReferenceDescriptor existing;
    if (inspect_constant_reference<CheckedSourceConstantGraph,
        UnboundConstantEnvironment<CheckedSourceConstantGraph>>(
            uint3(descriptor.root.xy, 0xffffffffu), tokens, existing) &&
        constant_reference_descriptors_equal<Graph, Environment,
            CheckedSourceConstantGraph, UnboundConstantEnvironment<CheckedSourceConstantGraph>>(
                descriptor, existing, tokens, false))
    { reference = descriptor.root.xy; failure = 0u; return true; }
    if (descriptor.disposition == CONSTANT_REFERENCE_CONCRETE)
    {
        uint3 existing_value;
        if (descriptor.terminal.x == 1u &&
            checked_constant_atom_value(descriptor.terminal.y, existing_value) &&
            constant_values_equal(existing_value, descriptor.value))
        { reference = descriptor.terminal; failure = 0u; return true; }
        uint row;
        if (!reserve_checked_constant_row(row)) { failure = 1u; return false; }
        if (!publish_checked_constant_atom_at(row, descriptor.value, reference)) return false;
        failure = 0u; return true;
    }
    if (descriptor.disposition != CONSTANT_REFERENCE_SYMBOLIC || descriptor.terminal.x != 2u ||
        checked_constant_parameter_scalar(descriptor.terminal.y) != descriptor.terminal_scalar ||
        !CheckedSourceConstantEnvironment.parameter_is_valid(descriptor.terminal.y)) return false;
    uint targets[64]; uint count = 0u; uint3 current = descriptor.root;
    for (uint work = 0u; work < CONSTANT_REFERENCE_WORK_LIMIT; work++)
    {
        uint3 next; uint scalar; uint3 value;
        uint step = constant_reference_step<Graph, Environment>(current, tokens, next, scalar, value);
        if (step == 2u)
        {
            if (any(current.xy != descriptor.terminal)) return false;
            reference = descriptor.terminal;
            for (uint index = count; index != 0u; index--)
            {
                uint row; uint2 child = reference;
                if (!reserve_checked_constant_row(row)) { failure = 1u; return false; }
                if (!publish_checked_constant_projection_at(row, targets[index - 1u], child, reference)) return false;
            }
            failure = 0u; return true;
        }
        if (step != 3u && step != 4u) return false;
        if (step == 3u)
        {
            if (count == 64u) { failure = 2u; return false; }
            targets[count++] = scalar;
        }
        current = next;
    }
    failure = 2u; return false;
}
