// Constant-only readers do not need type-instance or layout capabilities.
import type_checker.constant_atoms;
import type_checker.constant_parameter_slots;
import type_checker.concrete_type_equality;

public struct CheckedSourceConstantGraph : IConstantIdentityGraph
{
    [ForceInline]
    public static bool constant_value(uint row, out uint3 value)
    { return checked_constant_atom_value(row, value); }
    [ForceInline]
    public static uint constant_parameter_scalar(uint reference)
    { return checked_constant_parameter_scalar(reference); }
    [ForceInline]
    public static bool constant_projection(uint row, out uint scalar, out uint2 child)
    { return checked_constant_projection(row, scalar, child); }
}

// Body replay publishes an atom row at the exact declaration token. This is
// shared read-only storage; source/replay producing passes own its writes.
public StructuredBuffer<uint> type_const_param_value_by_token;

public struct CheckedSourceConstantEnvironment : IConstantReferenceEnvironment
{
    public static bool parameter_is_valid(uint reference)
    {
        uint count; uint stride;
        type_const_param_slot_by_token.GetDimensions(count, stride);
        return reference < count && type_const_param_slot_by_token[reference] < 32u &&
            checked_constant_parameter_scalar(reference) != 0u;
    }
    public static bool substitute(uint environment, uint reference, out uint kind, out uint payload)
    {
        kind = 2u; payload = reference;
        uint count; uint stride;
        type_const_param_value_by_token.GetDimensions(count, stride);
        if (reference >= count || !parameter_is_valid(reference)) return false;
        uint atom = type_const_param_value_by_token[reference];
        if (atom != 0xffffffffu) { kind = 1u; payload = atom; }
        // An unbound original becomes an exact caller-scoped symbolic leaf.
        // The central walker validates a bound atom and scalar compatibility.
        return true;
    }
}

// Executable bits require closure and discharged fit obligations. This reader
// never converts an unresolved parameter to its slot or truncates a high limb.
public bool checked_source_constant_value(uint kind, uint payload, uint tokens, out uint3 value)
{
    value = uint3(0u, 0u, 0u);
    ConstantReferenceDescriptor descriptor;
    if (!inspect_constant_reference<CheckedSourceConstantGraph,
        CheckedSourceConstantEnvironment>(
            uint3(kind, payload, 0u), tokens, descriptor) ||
        descriptor.disposition != CONSTANT_REFERENCE_CONCRETE || descriptor.pending_fit != 0u)
        return false;
    value = descriptor.value;
    return true;
}

// Physical parameter capacity is a namespace bound, never an instance count.
// The job initializer clears all scalar rows, including recycled workspace slack.
public uint checked_source_constant_parameter_capacity()
{
    uint count; uint stride;
    type_const_param_scalar_by_token.GetDimensions(count, stride);
    return count;
}
