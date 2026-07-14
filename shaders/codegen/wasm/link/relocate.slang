import codegen.wasm.link.common;
StructuredBuffer<uint4> link_relocation;
RWStructuredBuffer<uint> out_words;
void write_byte(uint pos, uint value)
{
    uint word_i = pos >> 2u; uint shift = (pos & 3u) * 8u; uint mask = 0xffu << shift;
    uint old_value = out_words[word_i];
    for (;;) { uint next = (old_value & ~mask) | ((value & 0xffu) << shift); uint prior; InterlockedCompareExchange(out_words[word_i], old_value, next, prior); if (prior == old_value) return; old_value = prior; }
}
[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    uint i = tid.x; if (i >= gLink.relocation_count) return;
    uint4 row = link_relocation[i];
    uint target = INVALID;
    if (row.y == 1u)
    {
        target = row.z;
    }
    else if (row.y == 2u)
    {
        uint representative = lookup_identity(row.z);
        if (representative == INVALID) { fail(4u, i); return; }
        target = link_symbol_definition[representative];
    }
    else { fail(7u, i); return; }
    if (target == INVALID) { fail(5u, i); return; }
    int adjusted = int(target) + asint(row.w); if (adjusted < 0) { fail(6u, i); return; }
    uint body_start = 8u + (11u + gLink.type_len) + (11u + 5u * gLink.function_count) + 22u + 11u;
    uint value = uint(adjusted); for (uint b = 0u; b < 5u; b += 1u) write_byte(body_start + row.x + b, ((value >> (7u * b)) & 0x7fu) | (b < 4u ? 0x80u : 0u));
}
