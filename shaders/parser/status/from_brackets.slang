// Combines partial-parse packing status with stack-effect validation.

RWStructuredBuffer<uint> partial_parse_status;
StructuredBuffer<int> bracket_depths; // [0]=final depth, [1]=minimum depth
StructuredBuffer<uint> bracket_valid;
RWStructuredBuffer<uint> ll1_status;

static const uint ERR_NONE = 0u;
static const uint ERR_STACK_EFFECT = 4u;

[shader("compute")]
[numthreads(1, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    if (dtid.x != 0u || dtid.y != 0u || dtid.z != 0u)
        return;

    uint pack_ok = partial_parse_status[0u];
    uint error_pos = partial_parse_status[1u];
    uint error_code = partial_parse_status[2u];
    uint detail = partial_parse_status[3u];
    uint steps = partial_parse_status[4u];
    uint emit_len = partial_parse_status[5u];

    bool stack_ok = bracket_valid[0u] != 0u &&
        bracket_depths[0u] == 0 &&
        bracket_depths[1u] >= 0;
    bool accepted = pack_ok != 0u && stack_ok;

    if (pack_ok != 0u && !stack_ok)
    {
        error_pos = 0u;
        error_code = ERR_STACK_EFFECT;
        detail = asuint(bracket_depths[0u]);
    }

    uint accepted_word = accepted ? 1u : 0u;
    uint accepted_emit_len = accepted ? emit_len : 0u;

    ll1_status[0u] = accepted_word;
    ll1_status[1u] = accepted ? 0u : error_pos;
    ll1_status[2u] = accepted ? ERR_NONE : error_code;
    ll1_status[3u] = accepted ? 0u : detail;
    ll1_status[4u] = steps;
    ll1_status[5u] = accepted_emit_len;

    partial_parse_status[0u] = ll1_status[0u];
    partial_parse_status[1u] = ll1_status[1u];
    partial_parse_status[2u] = ll1_status[2u];
    partial_parse_status[3u] = ll1_status[3u];
    partial_parse_status[4u] = ll1_status[4u];
    partial_parse_status[5u] = ll1_status[5u];
}
