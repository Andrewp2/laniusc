// Read a checked source or private generated application's ordered arguments.
// Source fallback rows have four slots; replay and generated rows have 32.
// The arena boundary follows the workspace source capacity, not a job's size.
public bool checked_instance_argument(uint instance, uint slot, uint source_capacity,
    StructuredBuffer<uint> counts, StructuredBuffer<uint> starts,
    StructuredBuffer<uint> tags, StructuredBuffer<uint> payloads,
    StructuredBuffer<uint> row_starts, StructuredBuffer<uint> row_count,
    StructuredBuffer<uint> row_tags, StructuredBuffer<uint> row_payloads,
    out uint tag, out uint payload)
{
    static const uint INVALID = 0xffffffffu;
    tag = 0u; payload = INVALID;
    uint capacity; uint stride;
    counts.GetDimensions(capacity, stride);
    if (instance >= capacity || slot >= counts[instance]) return false;
    uint start = row_starts[instance];
    row_tags.GetDimensions(capacity, stride);
    uint total = min(row_count[0u], capacity);
    if (start < total && slot < total - start)
    {
        tag = row_tags[start + slot]; payload = row_payloads[start + slot];
        if (tag != 0u) return payload != INVALID;
    }
    start = starts[instance];
    tags.GetDimensions(capacity, stride);
    if (slot >= 32u || (instance < source_capacity && slot >= 4u) ||
        start >= capacity || slot >= capacity - start) return false;
    tag = tags[start + slot]; payload = payloads[start + slot];
    return tag != 0u && payload != INVALID;
}
