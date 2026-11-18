// Store growth (one lane per record of the largest table): after the host
// copied the committed prefixes of the arenas into larger buffers and
// zeroed the new slot tables, every live record (not a tombstone) is
// published again in its table. Records are distinct keys already, so the
// insert is a blind CAS into the first empty probe slot.
import type_checker.retention.retention_store;

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint id = dtid.x + dtid.y * 16776960u;
    uint slots; uint stride;
    if (id >= 1u && id < rt_counts[RT_A_DECLS] && rt_decl_key[id].z != 0u)
    {
        rt_decl_slot.GetDimensions(slots, stride);
        uint slot = rt_probe_start(rt_decl_hash(rt_decl_key[id]).x, slots);
        for (uint probe = 0u; probe < slots; probe++)
        {
            uint value;
            InterlockedCompareExchange(rt_decl_slot[slot], 0u, id, value);
            if (value == 0u) break;
            slot = (slot + 1u) & (slots - 1u);
        }
    }
    if (id >= 1u && id < rt_counts[RT_A_PARAMS] && rt_param_key[id].y != 0u)
    {
        rt_param_slot.GetDimensions(slots, stride);
        uint slot = rt_probe_start(rt_param_hash(rt_param_key[id].xyz).x, slots);
        for (uint probe = 0u; probe < slots; probe++)
        {
            uint value;
            InterlockedCompareExchange(rt_param_slot[slot], 0u, id, value);
            if (value == 0u) break;
            slot = (slot + 1u) & (slots - 1u);
        }
    }
    if (id >= RT_FIRST_TERM && id < rt_counts[RT_A_TERMS] && rt_term_head[id].x != 0u)
    {
        rt_term_slot.GetDimensions(slots, stride);
        uint slot = rt_probe_start(rt_term_meta[id].z, slots);
        for (uint probe = 0u; probe < slots; probe++)
        {
            uint value;
            InterlockedCompareExchange(rt_term_slot[slot], 0u, id, value);
            if (value == 0u) break;
            slot = (slot + 1u) & (slots - 1u);
        }
    }
}
