// One lane per symbol capacity row: inserts each definition into the
// definition table and each small text definition into the splice table.
// A second definition of an identity is an error.

import codegen.x86.link.resident_linking.resident_link_layout;
import codegen.x86.link.resident_linking.resident_symbol_rows;

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    uint lane = rl_lane(tid);
    uint object = symbol_lane_object(lane);
    if (object == INVALID)
        return;
    bool definition;
    uint index;
    if (!symbol_lane_row(object, lane, definition, index) || !definition)
        return;
    uint3 identity = symbol_identity(lane);
    uint slot = identity_hash(identity) & gRL.hash_mask;
    bool inserted = false;
    for (uint probe = 0u; probe <= gRL.hash_mask; probe += 1u)
    {
        uint prior;
        InterlockedCompareExchange(rl_sym_hash[slot], 0u, lane + 1u, prior);
        if (prior == 0u)
        {
            inserted = true;
            break;
        }
        if (all(symbol_identity(prior - 1u) == identity))
        {
            fail(512u);
            return;
        }
        slot = (slot + 1u) & gRL.hash_mask;
    }
    if (!inserted)
    {
        fail(512u);
        return;
    }
    uint section = rl_symbols[lane * SYMBOL_WORDS + 4u];
    uint offset = rl_symbols[lane * SYMBOL_WORDS + 5u];
    uint size = rl_symbols[lane * SYMBOL_WORDS + 6u];
    if (section == 1u && size >= 2u && size <= 10u)
    {
        if (object >= 255u || offset >= 0x1000000u)
        {
            fail(256u);
            return;
        }
        uint key = small_key(object, offset);
        uint slot = small_key_hash(object, offset);
        for (uint probe = 0u; probe <= gRL.small_mask; probe += 1u)
        {
            uint prior;
            InterlockedCompareExchange(rl_small_hash[slot * 2u], 0u, key, prior);
            if (prior == 0u || prior == key)
            {
                // The host map keeps the last symbol in object order.
                atomic_u32_max(rl_small_hash, slot * 2u + 1u, index + 1u);
                return;
            }
            slot = (slot + 1u) & gRL.small_mask;
        }
        fail(256u);
    }
}
