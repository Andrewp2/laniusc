// A compound is concrete when every type argument and element reference is
// concrete. Being another instance is not itself a reason to reject a field.
// Unsubstituted parameters, unavailable rows, cycles, and excessive depth fail
// closed before machine layout is considered.
import type_checker.concrete_type_equality;

public bool concrete_instance_is_closed(uint instance, uint capacity,
    StructuredBuffer<uint> kinds, StructuredBuffer<uint> counts,
    StructuredBuffer<uint> starts, StructuredBuffer<uint> tags,
    StructuredBuffer<uint> payloads, StructuredBuffer<uint> row_starts,
    StructuredBuffer<uint> row_count, StructuredBuffer<uint> row_tags,
    StructuredBuffer<uint> row_payloads, StructuredBuffer<uint> element_tags,
    StructuredBuffer<uint> element_payloads, StructuredBuffer<uint> length_kinds,
    uint source_capacity = 0xffffffffu)
{
    static const uint INVALID = 0xffffffffu;
    static const uint DEPTH_LIMIT = 64u;
    uint2 refs[DEPTH_LIMIT];
    uint next[DEPTH_LIMIT];
    uint children[DEPTH_LIMIT];
    uint depth = 0u;
    refs[0u] = uint2(3u, instance);
    next[0u] = INVALID;
    for (;;)
    {
        uint2 current = refs[depth];
        if (next[depth] == INVALID)
        {
            if (current.y == INVALID) return false;
            children[depth] = 0u;
            next[depth] = 0u;
            if (current.x == 1u)
            {
                if (current.y == 0u) return false;
            }
            else if (current.x == (APPLICATION_CONSTANT_ARGUMENT | 1u)) {}
            else if (current.x == 3u && current.y < capacity)
            {
                uint kind = kinds[current.y];
                if (kind == 1u)
                {
                    children[depth] = counts[current.y];
                    if (children[depth] > capacity) return false;
                }
                else if (kind == 2u || kind == 3u || kind == 4u)
                {
                    if (kind == 2u && length_kinds[current.y] != 1u) return false;
                    children[depth] = 1u;
                }
                else return false;
            }
            else return false;
        }
        if (next[depth] == children[depth])
        {
            if (depth == 0u) return true;
            depth--;
            continue;
        }
        uint ordinal = next[depth]++;
        uint tag; uint payload;
        if (kinds[current.y] != 1u)
        {
            tag = element_tags[current.y]; payload = element_payloads[current.y];
        }
        else
        {
            uint start = row_starts[current.y];
            uint total = row_count[0u];
            tag = 0u; payload = INVALID;
            if (start < total && ordinal < total - start)
            {
                tag = row_tags[start + ordinal]; payload = row_payloads[start + ordinal];
            }
            if (tag == 0u)
            {
                start = starts[current.y];
                uint argument_capacity; uint stride;
                tags.GetDimensions(argument_capacity, stride);
                if ((ordinal >= 4u && (source_capacity == INVALID ||
                    current.y < source_capacity)) || ordinal >= 32u || start >= argument_capacity ||
                    ordinal >= argument_capacity - start) return false;
                tag = tags[start + ordinal]; payload = payloads[start + ordinal];
            }
        }
        if (depth + 1u == DEPTH_LIMIT) return false;
        for (uint ancestor = 0u; ancestor <= depth; ancestor++)
            if (refs[ancestor].x == tag && refs[ancestor].y == payload) return false;
        depth++;
        refs[depth] = uint2(tag, payload);
        next[depth] = INVALID;
    }
}
