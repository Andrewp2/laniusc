// Decode compact string literals with a workgroup-parallel two-state DFA scan.
import atomics;
import byte_packing;

struct Params { uint n; uint source_len; uint pool_capacity; uint uses_status_count; };
ConstantBuffer<Params> gHirString;
ByteAddressBuffer source_bytes;
StructuredBuffer<uint> hir_string_node;
StructuredBuffer<uint> hir_string_count;
StructuredBuffer<uint> hir_expr_string_start;
StructuredBuffer<uint> hir_expr_string_len;
StructuredBuffer<uint> hir_string_data_offset;
RWStructuredBuffer<uint> hir_string_decoded_len;
RWStructuredBuffer<uint> hir_string_data_words;

static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;
groupshared uint scan_count0[WG_SIZE];
groupshared uint scan_count1[WG_SIZE];
groupshared uint scan_end0[WG_SIZE];
groupshared uint scan_end1[WG_SIZE];

uint string_row(uint3 gid) { return gid.x + gid.y * MAX_GROUPS_X; }
uint source_byte(uint pos) { return pos < gHirString.source_len ? byte_address_load_u8(source_bytes, pos) : 0u; }
uint decoded_escape_byte(uint escaped)
{
    if (escaped == 110u) return 10u;
    if (escaped == 114u) return 13u;
    if (escaped == 116u) return 9u;
    if (escaped == 48u) return 0u;
    if (escaped == 34u) return 34u;
    if (escaped == 92u) return 92u;
    return escaped;
}
uint2 summarize(uint start, uint begin, uint end, uint input_state)
{
    uint state = input_state;
    uint count = 0u;
    for (uint i = begin; i < end; i += 1u)
    {
        uint b = source_byte(start + i);
        if (state != 0u) { count += 1u; state = 0u; }
        else if (b == 92u) { state = 1u; }
        else { count += 1u; }
    }
    return uint2(count, state);
}
void scatter_byte(uint pos, uint value)
{
    if (pos >= gHirString.pool_capacity)
        return;
    atomic_u32_or(hir_string_data_words, pos >> 2u, (value & 0xffu) << ((pos & 3u) * 8u));
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 gid: SV_GroupID, uint3 ltid: SV_GroupThreadID)
{
    uint row = string_row(gid);
    if (row >= hir_string_count[0])
        return;
    uint node = hir_string_node[row];
    uint start = hir_expr_string_start[node];
    uint raw_len = hir_expr_string_len[node];
    uint chunk = (raw_len + WG_SIZE - 1u) / WG_SIZE;
    uint begin = min(raw_len, ltid.x * chunk);
    uint end = min(raw_len, begin + chunk);

    uint2 f0 = summarize(start, begin, end, 0u);
    uint2 f1 = summarize(start, begin, end, 1u);
    scan_count0[ltid.x] = f0.x; scan_end0[ltid.x] = f0.y;
    scan_count1[ltid.x] = f1.x; scan_end1[ltid.x] = f1.y;
    GroupMemoryBarrierWithGroupSync();

    for (uint stride = 1u; stride < WG_SIZE; stride <<= 1u)
    {
        uint own_c0 = scan_count0[ltid.x], own_e0 = scan_end0[ltid.x];
        uint own_c1 = scan_count1[ltid.x], own_e1 = scan_end1[ltid.x];
        uint prev_c0 = 0u, prev_e0 = 0u, prev_c1 = 0u, prev_e1 = 1u;
        if (ltid.x >= stride)
        {
            uint p = ltid.x - stride;
            prev_c0 = scan_count0[p]; prev_e0 = scan_end0[p];
            prev_c1 = scan_count1[p]; prev_e1 = scan_end1[p];
        }
        GroupMemoryBarrierWithGroupSync();
        if (ltid.x >= stride)
        {
            scan_count0[ltid.x] = prev_c0 + (prev_e0 == 0u ? own_c0 : own_c1);
            scan_end0[ltid.x] = prev_e0 == 0u ? own_e0 : own_e1;
            scan_count1[ltid.x] = prev_c1 + (prev_e1 == 0u ? own_c0 : own_c1);
            scan_end1[ltid.x] = prev_e1 == 0u ? own_e0 : own_e1;
        }
        GroupMemoryBarrierWithGroupSync();
    }

    uint incoming_count = ltid.x == 0u ? 0u : scan_count0[ltid.x - 1u];
    uint state = ltid.x == 0u ? 0u : scan_end0[ltid.x - 1u];
    uint out_i = incoming_count;
    uint pool_base = hir_string_data_offset[node];
    for (uint i = begin; i < end; i += 1u)
    {
        uint b = source_byte(start + i);
        if (state != 0u)
        {
            scatter_byte(pool_base + out_i, decoded_escape_byte(b));
            out_i += 1u; state = 0u;
        }
        else if (b == 92u) state = 1u;
        else { scatter_byte(pool_base + out_i, b); out_i += 1u; }
    }
    if (ltid.x == WG_SIZE - 1u)
        hir_string_decoded_len[node] = scan_count0[WG_SIZE - 1u];
}
