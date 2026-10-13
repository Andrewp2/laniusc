// Array counts are checked projections of typed scalar constants. Only the
// closed-count reader supplies executable extents; descriptor validity or
// symbolic identity never proves that pending fits have been discharged.
import type_checker.constant_atoms_identity;
import constant_value;
import primitive_types;
import type_checker.concrete_type_equality;

public bool checked_source_array_count(uint kind, uint payload, uint tokens, out uint count)
{
    count = 0u;
    uint3 value;
    return checked_source_constant_value(kind, payload, tokens, value) &&
        constant_value_to_count(value, count);
}

bool checked_source_array_descriptor(uint kind, uint payload, uint tokens,
    out ConstantReferenceDescriptor descriptor)
{
    if (!inspect_constant_reference<CheckedSourceConstantGraph, CheckedSourceConstantEnvironment>(
        uint3(kind, payload, 0u), tokens, descriptor)) return false;
    if (descriptor.disposition == CONSTANT_REFERENCE_CONCRETE)
    {
        uint count;
        return descriptor.pending_fit == 0u && constant_value_to_count(descriptor.value, count);
    }
    // A bare source parameter is a conditional count contract too. Array
    // producers retain it under a U32 count projection; imported/source graphs
    // may keep the obligation in their enclosing array node.
    return descriptor.disposition == CONSTANT_REFERENCE_SYMBOLIC &&
        scalar_is_integer(descriptor.terminal_scalar);
}

public bool checked_source_array_length_valid(uint kind, uint payload, uint tokens)
{
    ConstantReferenceDescriptor descriptor;
    return checked_source_array_descriptor(kind, payload, tokens, descriptor);
}

public bool checked_source_array_lengths_equal(uint2 left, uint2 right, uint tokens)
{
    ConstantReferenceDescriptor a; ConstantReferenceDescriptor b;
    return checked_source_array_descriptor(left.x, left.y, tokens, a) &&
        checked_source_array_descriptor(right.x, right.y, tokens, b) &&
        constant_reference_descriptors_equal<CheckedSourceConstantGraph, CheckedSourceConstantEnvironment,
            CheckedSourceConstantGraph, CheckedSourceConstantEnvironment>(a, b, tokens, true);
}

public bool checked_source_array_length_matches_count(uint kind, uint payload, uint count, uint tokens)
{
    uint actual;
    return checked_source_array_count(kind, payload, tokens, actual) && actual == count;
}
