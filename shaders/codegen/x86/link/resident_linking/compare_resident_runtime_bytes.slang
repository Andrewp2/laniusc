// The link may keep only an object's body when its runtime matches the
// entry object's byte for byte. Compare the live runtime ranges, excluding
// the trailing bridge bytes in both objects.
import codegen.x86.link.resident_linking.resident_link_layout;

static const uint GROUP_LANES = 256u;
static const uint GROUPS_PER_OBJECT = 8u;

uint entry_object()
{
    for (uint k = 0u; k < gRL.object_count; k += 1u)
        if (meta_word(k, 6u) == 1u)
            return k;
    return INVALID;
}

bool runtime_range(uint object, out uint start, out uint length)
{
    uint text_len, rodata_len, entry, body_start, body_end;
    object_geometry(object, text_len, rodata_len, entry, body_start, body_end);
    uint end = text_len >= BRIDGE_BYTES ? text_len - BRIDGE_BYTES : 0u;
    start = slot_word(object, 8u) + body_end;
    length = end > body_end ? end - body_end : 0u;
    // The plan will reject invalid object geometry.
    return length != 0u && text_len <= slot_word(object, 12u);
}

uint runtime_word(uint start, uint bytes)
{
    uint word = start >> 2u;
    uint shift = (start & 3u) * 8u;
    uint value = st_text[word] >> shift;
    if (bytes * 8u > 32u - shift)
        value |= st_text[word + 1u] << (32u - shift);
    return value & (0xffffffffu >> ((4u - bytes) * 8u));
}

[shader("compute")]
[numthreads(GROUP_LANES, 1, 1)]
void main(uint3 group: SV_GroupID, uint lane: SV_GroupIndex)
{
    uint block = group.x + group.y * 65535u;
    uint object = block / GROUPS_PER_OBJECT;
    if (object >= gRL.object_count || meta_word(object, 6u) == 1u)
        return;
    uint entry = entry_object();
    if (entry == INVALID)
        return;
    uint start, length, entry_start, entry_length;
    if (!runtime_range(object, start, length) ||
        !runtime_range(entry, entry_start, entry_length) || length != entry_length)
        return;
    uint offset = 4u * ((block % GROUPS_PER_OBJECT) * GROUP_LANES + lane);
    bool mismatch = false;
    for (; offset < length; offset += 4u * GROUPS_PER_OBJECT * GROUP_LANES)
    {
        uint bytes = min(4u, length - offset);
        if (runtime_word(start + offset, bytes) != runtime_word(entry_start + offset, bytes))
        {
            mismatch = true;
            break;
        }
    }
    if (WaveActiveAnyTrue(mismatch) && WaveIsFirstLane())
        atomic_u32_or(rl_objects, object * OBJECT_WORDS + OB_MISMATCH, 1u);
}
