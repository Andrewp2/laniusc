// The including pass supplies the checked kind/element columns (read or RW).
// Follow only reference edges. The terminal root still owns its complete
// nominal environment; the caller retains the original value representation.
bool checked_referent_reference(inout uint tag, inout uint payload,
                                 out uint reference_depth)
{
    static const uint INVALID_REFERENCE = 0xffffffffu;
    reference_depth = 0u;
    uint capacity; uint stride;
    type_instance_kind.GetDimensions(capacity, stride);
    for (uint depth = 0u; depth <= 64u; depth++)
    {
        if (tag != 3u)
            return (tag == 1u || tag == 2u) && payload != INVALID_REFERENCE &&
                (tag != 1u || payload != 0u);
        if (payload >= capacity || type_instance_kind[payload] == 0u)
            return false;
        if (type_instance_kind[payload] != 4u) return true;
        if (depth == 64u) return false;
        uint reference = payload;
        tag = type_instance_elem_ref_tag[reference];
        payload = type_instance_elem_ref_payload[reference];
        reference_depth += 1u;
    }
    return false;
}
