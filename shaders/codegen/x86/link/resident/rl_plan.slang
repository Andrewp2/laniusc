// One lane: the per-object link plan (copied text range, shared runtime,
// output section bases, definition prefix) and the link totals.

import codegen.x86.link.resident.rl_common;

void set_object(uint object, uint word, uint value) { rl_objects[object * OBJECT_WORDS + word] = value; }

[shader("compute")]
[numthreads(1, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    uint entry = INVALID;
    uint entries = 0u;
    for (uint k = 0u; k < gRL.object_count; k += 1u)
    {
        uint text_len, rodata_len, is_entry, body_start, body_end;
        object_geometry(k, text_len, rodata_len, is_entry, body_start, body_end);
        if (meta_word(k, 11u) != 0u || meta_word(k, 6u) > 1u ||
            meta_word(k, 1u) > slot_word(k, 1u) || meta_word(k, 16u) > slot_word(k, 3u) ||
            meta_word(k, 2u) > slot_word(k, 5u) || meta_word(k, 3u) > slot_word(k, 7u) ||
            text_len > slot_word(k, 12u) || rodata_len > slot_word(k, 13u) ||
            meta_word(k, 10u) < meta_word(k, 9u))
            fail(1u);
        // The slot holds the object the host published for this unit. An
        // object the host has not read back yet has INVALID lengths; the
        // host compares its plan words after its readback.
        if (slot_word(k, 14u) != INVALID &&
            (text_len != slot_word(k, 14u) || rodata_len != slot_word(k, 15u) ||
            meta_word(k, 1u) + meta_word(k, 16u) != slot_word(k, 16u) ||
            meta_word(k, 2u) + meta_word(k, 3u) != slot_word(k, 17u)))
            fail(1u);
        if (is_entry != 0u)
        {
            entries += 1u;
            entry = k;
        }
        uint rt_end = text_len >= BRIDGE_BYTES ? text_len - BRIDGE_BYTES : 0u;
        bool has_rt = text_len >= BRIDGE_BYTES && body_end < rt_end;
        set_object(k, OB_TEXT_LEN, text_len);
        set_object(k, OB_RODATA_LEN, rodata_len);
        set_object(k, OB_ENTRY, is_entry);
        set_object(k, OB_BODY_START, body_start);
        set_object(k, OB_BODY_END, body_end);
        set_object(k, OB_HAS_BODY, 1u);
        set_object(k, OB_RT_START, body_end);
        set_object(k, OB_RT_END, has_rt ? rt_end : body_end);
        set_object(k, OB_HAS_RT, has_rt ? 1u : 0u);
        set_object(k, OB_UNDEF_COUNT, meta_word(k, 2u));
        set_object(k, OB_DEF_COUNT, meta_word(k, 3u));
        set_object(k, OB_RELOC_COUNT, meta_word(k, 1u));
        set_object(k, OB_RT_COUNT, meta_word(k, 16u));
    }
    if (entries != 1u)
    {
        fail(2u);
        return;
    }
    bool entry_rt = object_word(entry, OB_HAS_RT) != 0u;
    uint entry_rt_start = object_word(entry, OB_RT_START);
    uint entry_rt_len = object_word(entry, OB_RT_END) - entry_rt_start;
    uint text_out = 0u;
    uint rodata_out = 0u;
    uint def_prefix = 0u;
    for (uint k = 0u; k < gRL.object_count; k += 1u)
    {
        uint text_len = object_word(k, OB_TEXT_LEN);
        bool shared = entry_rt && k != entry && object_word(k, OB_ENTRY) == 0u &&
            object_word(k, OB_HAS_RT) != 0u &&
            object_word(k, OB_RT_END) - object_word(k, OB_RT_START) == entry_rt_len &&
            object_word(k, OB_MISMATCH) == 0u;
        uint copy_start = shared ? object_word(k, OB_BODY_START) : 0u;
        uint copy_end = shared ? object_word(k, OB_BODY_END) : text_len;
        set_object(k, OB_COPY_START, copy_start);
        set_object(k, OB_COPY_END, copy_end);
        set_object(k, OB_SHARED, shared ? 1u : 0u);
        set_object(k, OB_TEXT_OUT, text_out);
        set_object(k, OB_RODATA_OUT, rodata_out);
        set_object(k, OB_DEF_PREFIX, def_prefix);
        set_object(k, OB_ENTRY_OBJECT, entry);
        set_object(k, OB_ENTRY_RT_START, entry_rt_start);
        text_out += copy_end - copy_start;
        rodata_out += object_word(k, OB_RODATA_LEN);
        def_prefix += object_word(k, OB_DEF_COUNT);
    }
    rl_status[ST_TEXT_LEN] = text_out;
    rl_status[ST_RODATA_LEN] = rodata_out;
    rl_status[ST_DEF_COUNT] = def_prefix;
    rl_status[ST_ENTRY_OBJECT] = entry;
    // The entry object keeps its whole text, so its CRT bridge trailer keeps
    // its offset.
    rl_status[ST_MAIN_OFFSET] = object_word(entry, OB_TEXT_OUT) +
        object_word(entry, OB_TEXT_LEN) - BRIDGE_BYTES;
    if (object_word(entry, OB_TEXT_LEN) < BRIDGE_BYTES)
        fail(4u);
}
