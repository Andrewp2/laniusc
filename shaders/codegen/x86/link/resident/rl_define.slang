// One lane per symbol capacity row: writes the link symbol (final identity,
// copied text offset). rl_insert.slang indexes the definitions.

import codegen.x86.link.resident.rl_common;
import codegen.x86.link.resident.rl_symbol_lane;

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
    if (!symbol_lane_row(object, lane, definition, index))
        return;
    uint3 identity;
    uint section = 0u;
    uint offset = 0u;
    uint size = 0u;
    uint flags = 0u;
    if (definition)
    {
        uint row = (slot_word(object, 6u) + index) * 8u;
        identity = uint3(st_def[row], st_def[row + 1u], st_def[row + 2u]);
        section = st_def[row + 3u];
        offset = st_def[row + 4u];
        size = st_def[row + 5u];
        flags = st_def[row + 6u];
        if (section != 1u && section != 2u)
            fail(16u);
        if (section == 1u)
        {
            uint copy_start = object_word(object, OB_COPY_START);
            uint copy_end = object_word(object, OB_COPY_END);
            if (offset < copy_start || offset + size < offset || offset + size > copy_end)
                fail(32u);
            offset -= copy_start;
        }
    }
    else
    {
        uint row = (slot_word(object, 4u) + index) * 4u;
        identity = uint3(st_undef[row], st_undef[row + 1u], st_undef[row + 2u]);
        if (slot_word(object, 19u) != 0u)
        {
            uint word = slot_word(object, 18u) + index * 3u;
            identity = uint3(st_ident[word], st_ident[word + 1u], st_ident[word + 2u]);
        }
        // A deferred generic call names its use until discovery routes it.
        if (identity.x == RESERVED_LIB && identity.y == NS_USE)
        {
            if (identity.z >= gRL.route_capacity)
                fail(64u);
            else
                identity = rl_routes[identity.z].xyz;
        }
    }
    uint base = lane * SYMBOL_WORDS;
    rl_symbols[base] = object;
    rl_symbols[base + 1u] = identity.x;
    rl_symbols[base + 2u] = identity.y;
    rl_symbols[base + 3u] = identity.z;
    rl_symbols[base + 4u] = section;
    rl_symbols[base + 5u] = offset;
    rl_symbols[base + 6u] = size;
    rl_symbols[base + 7u] = flags;
    if (!definition)
        return;
    atomic_u32_max(rl_status, ST_NAME_STRIDE,
        9u + decimal_digits(identity.x) + 1u + decimal_digits(identity.y) + 1u + decimal_digits(identity.z) + 1u);
    if (lookup_binding(identity) != INVALID)
        fail(128u);
}
