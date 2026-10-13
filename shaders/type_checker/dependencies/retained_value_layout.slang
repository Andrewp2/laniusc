// Imported value layouts retain checked child references and group boundaries.
// No field in this relation denotes a row in a reusable dependency page.
import type_checker.dependencies.retained_payload_refs;
public StructuredBuffer<uint> imported_layout_group_start;
public StructuredBuffer<uint> imported_layout_group_count;
public StructuredBuffer<uint2> imported_layout_groups;

public uint retained_layout_kind(uint instance)
{
    uint capacity; uint stride;
    imported_layout_kind.GetDimensions(capacity, stride);
    uint state = instance < capacity ? imported_layout_kind[instance] : 0u;
    return (state & 0x80000000u) != 0u ? state & 0x7fffffffu : 0u;
}

public bool retained_layout_group(uint instance, uint ordinal, out uint2 group)
{
    group = uint2(0u, 0u);
    if (retained_layout_kind(instance) == 0u ||
        ordinal >= imported_layout_group_count[instance]) return false;
    uint start = imported_layout_group_start[instance];
    uint capacity; uint stride;
    imported_layout_groups.GetDimensions(capacity, stride);
    if (start >= capacity || ordinal >= capacity - start) return false;
    group = imported_layout_groups[start + ordinal];
    return group.x <= imported_field_ref_count[instance] &&
        group.y <= imported_field_ref_count[instance] - group.x;
}

public bool retained_layout_child(uint instance, uint group_ordinal, uint ordinal,
    out uint tag, out uint payload)
{
    tag = 0u; payload = 0xffffffffu;
    uint2 group;
    if (!retained_layout_group(instance, group_ordinal, group) || ordinal >= group.y) return false;
    return retained_payload_reference(instance, group.x + ordinal, tag, payload);
}
