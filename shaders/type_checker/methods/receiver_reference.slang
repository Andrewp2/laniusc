// Preserve the original checked receiver. Candidate collection owns each
// explicit dereference step and records the selected adjustment separately.
bool method_lookup_receiver(uint tag, uint payload)
{
    if (payload == 0xffffffffu) return false;
    if (tag == 1u) return payload != 0u && payload < 4096u;
    if (tag == 2u) return true;
    uint capacity; uint stride;
    type_instance_kind.GetDimensions(capacity, stride);
    return tag == 3u && payload < capacity &&
        type_instance_kind[payload] >= 1u && type_instance_kind[payload] <= 4u;
}
