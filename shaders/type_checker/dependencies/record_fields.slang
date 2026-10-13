// Field names and checked types belong to the imported application. Neither
// lookup nor native field layout may depend on the currently resident page.
import type_checker.dependencies.retained_payload_refs;
public StructuredBuffer<uint2> imported_field_name_hash;

public bool imported_record_fields_available(uint instance)
{
    return retained_nominal_kind(instance) == 6u;
}

public bool imported_record_field_type(uint instance, uint ordinal, out uint tag, out uint payload)
{
    tag = 0u; payload = 0xffffffffu;
    return imported_record_fields_available(instance) &&
        retained_payload_reference(instance, ordinal, tag, payload);
}

public uint imported_record_field_ordinal(uint instance, uint name_lo, uint name_hi)
{
    static const uint INVALID = 0xffffffffu;
    if (!imported_record_fields_available(instance)) return INVALID;
    uint start = imported_field_ref_start[instance];
    uint count = imported_field_ref_count[instance];
    uint capacity; uint stride;
    imported_field_name_hash.GetDimensions(capacity, stride);
    if (start > capacity || count > capacity - start) return INVALID;
    for (uint ordinal = 0u; ordinal < count; ordinal++)
    {
        uint2 name = imported_field_name_hash[start + ordinal];
        if (name.x == name_lo && name.y == name_hi) return ordinal;
    }
    return INVALID;
}
