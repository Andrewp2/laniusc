struct LinkParams { uint function_count; uint type_len; uint body_len; uint entry_function; uint symbol_count; uint relocation_count; uint hash_capacity; uint output_len; };
ConstantBuffer<LinkParams> gLink;
RWStructuredBuffer<uint> link_hash_table;
RWStructuredBuffer<uint> link_symbol_definition;
RWStructuredBuffer<uint> link_status;
[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    uint i = tid.x;
    if (i < gLink.hash_capacity) link_hash_table[i] = 0xffffffffu;
    if (i < gLink.symbol_count) link_symbol_definition[i] = 0xffffffffu;
    if (i == 0u) { link_status[0u] = 1u; link_status[1u] = 0u; link_status[2u] = 0xffffffffu; link_status[3u] = 0u; }
}
