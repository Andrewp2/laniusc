// A nominal application's ordered operands include types and constants.
// The high bit marks the constant domain; the low bits use the existing
// literal/parameter constant reference kinds. These are private argument
// references, never value types or verified IR type tags.
public static const uint APPLICATION_CONSTANT_ARGUMENT = 0x80000000u;
public bool application_argument_is_constant(uint tag)
{
    return tag == (APPLICATION_CONSTANT_ARGUMENT | 1u) ||
           tag == (APPLICATION_CONSTANT_ARGUMENT | 2u);
}
public bool application_constant_argument(uint tag, uint payload, out uint kind, out uint value)
{
    kind = 0u; value = 0xffffffffu;
    if (!application_argument_is_constant(tag) || payload == 0xffffffffu) return false;
    kind = tag & ~APPLICATION_CONSTANT_ARGUMENT; value = payload; return true;
}

// Arguments retain declaration/source order in source, replay, and interface
// trees. Named metadata field 5 stores the type count; its high bit marks an
// interleaved domain order. Field 6 stores the constant-position bit mask.
// Common type-first headers keep direct slot reads.
public static const uint APPLICATION_INTERLEAVED_DOMAINS = 0x80000000u;
// Select the zero-based nth set bit. Admission guarantees slot < 32 and
// enough set bits. Clearing lower candidates takes at most 31 iterations;
// common type-first headers use direct reads and never enter this loop.
public uint application_argument_ordinal(uint mask, uint slot)
{
    [loop]
    for (uint ordinal = 0u; ordinal < slot; ordinal++) mask &= mask - 1u;
    return firstbitlow(mask);
}

public bool application_environment_argument<Graph : IConcreteTypeGraph>(
    uint instance, uint slot, bool constant, out uint tag, out uint payload)
{
    tag = 0u; payload = 0xffffffffu;
    if (instance == 0xffffffffu || slot >= 32u || Graph.metadata(instance, 0u) != 1u) return false;
    uint count = Graph.metadata(instance, 2u);
    uint domains = Graph.metadata(instance, 5u);
    uint types = domains & ~APPLICATION_INTERLEAVED_DOMAINS;
    if (count > 32u || types > count || slot >= (constant ? count - types : types)) return false;
    if ((domains & APPLICATION_INTERLEAVED_DOMAINS) == 0u)
        return Graph.argument(instance, (constant ? types : 0u) + slot, tag, payload) &&
            application_argument_is_constant(tag) == constant;
    uint valid = count == 32u ? 0xffffffffu : (1u << count) - 1u;
    uint constants = Graph.metadata(instance, 6u);
    if ((constants & ~valid) != 0u || countbits(constants) != count - types) return false;
    uint mask = constant ? constants : valid & ~constants;
    return Graph.argument(instance, application_argument_ordinal(mask, slot), tag, payload) &&
        application_argument_is_constant(tag) == constant;
}
public bool application_environment_type_argument<Graph : IConcreteTypeGraph>(
    uint instance, uint slot, out uint tag, out uint payload)
{
    return application_environment_argument<Graph>(instance, slot, false, tag, payload) &&
        (tag == 1u || tag == 2u || tag == 3u || tag == 5u);
}
public bool application_environment_constant<Graph : IConcreteTypeGraph>(
    uint instance, uint slot, out uint kind, out uint payload)
{
    uint tag; uint value;
    kind = 0u; payload = 0xffffffffu;
    return application_environment_argument<Graph>(instance, slot, true, tag, value) &&
        application_constant_argument(tag, value, kind, payload);
}
