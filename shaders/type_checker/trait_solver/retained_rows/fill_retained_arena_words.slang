// Retained trait catalog: writes one value over a word range of an arena
// (rc_stage = first word, word count, value), so the host uploads no
// arena-sized initial data.
StructuredBuffer<uint4> rc_stage;
RWStructuredBuffer<uint> rc_catalog;

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint i = dtid.x + dtid.y * 16776960u;
    uint4 range = rc_stage[0];
    if (i < range.y) rc_catalog[range.x + i] = range.z;
}
