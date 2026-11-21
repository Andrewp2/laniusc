// One lane per canonical record. Mark the occupied heights so translation
// visits only levels with live records.
import type_checker.canonicalization.canonical_api;
import type_checker.retention.retention_store;
import type_checker.retention.retention_job;

bool published(uint record, uint2 hash)
{
    uint mask = export_slot_capacity() - 1u;
    // Same probe start as canonical_api.slang, using the snapshot's mask.
    uint slot = (hash.x ^ (hash.y * 0x27d4eb2du)) & mask;
    for (uint probe = 0u; probe <= mask; probe++)
    {
        uint occupant = rt_input_ct_slot[slot];
        if (occupant == record) return true;
        if (occupant == 0u) return false;
        slot = (slot + 1u) & mask;
    }
    return false;
}

public void count_retained_type_heights(uint record)
{
    if (record < CT_FIRST_RECORD || record >= min(rt_input_ct_counts[CT_COUNT_NEXT_RECORD], export_record_capacity())) return;
    // Losing canonical candidates can leave complete records below the
    // allocation watermark. Translating them races to intern the same term.
    uint4 meta = rt_input_ct_meta[record];
    if (!published(record, meta.zw))
    {
        rt_x_term_map[record] = RT_UNKNOWN;
        return;
    }
    uint height = meta.y & 0xffffu;
    if (height == 0u || height >= RT_X_HEIGHTS)
    {
        rt_x_term_map[record] = RT_UNKNOWN;
        InterlockedAdd(rt_x_counts[RT_X_UNTRANSLATED], 1u);
        if (height != 0u) rt_invariant(RT_INV_HEIGHT);
        return;
    }
    InterlockedOr(rt_x_counts[RT_X_HEIGHT_MASK + (height >> 5u)], 1u << (height & 31u));
}
