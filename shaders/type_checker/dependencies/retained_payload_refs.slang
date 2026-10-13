// Checked payload references shared by record field access and native layout.
// These rows belong to the compilation job, never to a dependency page.
public StructuredBuffer<uint> imported_field_ref_start;
public StructuredBuffer<uint> imported_field_ref_count;
public StructuredBuffer<uint> imported_field_ref_tag;
public StructuredBuffer<uint> imported_field_ref_payload;
// Low bits identify the nominal declaration; the high bit says every payload
// reference is available for native layout. Individual fields may resolve first.
public StructuredBuffer<uint> imported_layout_kind;

public uint retained_nominal_kind(uint instance)
{
    uint capacity; uint stride;
    imported_layout_kind.GetDimensions(capacity, stride);
    return instance < capacity ? imported_layout_kind[instance] & 0x7fffffffu : 0u;
}

public bool retained_payload_reference(uint instance, uint ordinal, out uint tag, out uint payload)
{
    tag = 0u; payload = 0xffffffffu;
    uint capacity; uint stride;
    imported_field_ref_start.GetDimensions(capacity, stride);
    if (instance >= capacity || ordinal >= imported_field_ref_count[instance]) return false;
    uint start = imported_field_ref_start[instance];
    imported_field_ref_tag.GetDimensions(capacity, stride);
    if (start >= capacity || ordinal >= capacity - start) return false;
    tag = imported_field_ref_tag[start + ordinal];
    payload = imported_field_ref_payload[start + ordinal];
    return (tag == 1u || tag == 2u || tag == 3u) && payload != 0xffffffffu;
}
