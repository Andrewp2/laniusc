// One lane per symbol capacity row: an undefined symbol needs a definition
// or a foreign C binding; a binding marks its name as an import.

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
    if (!symbol_lane_row(object, lane, definition, index) || definition)
        return;
    uint3 identity = symbol_identity(lane);
    uint name = lookup_binding(identity);
    if (name != INVALID)
    {
        rl_name_ref[name] = 1u;
        return;
    }
    if (lookup_definition(identity) == INVALID)
        fail(1024u);
}
