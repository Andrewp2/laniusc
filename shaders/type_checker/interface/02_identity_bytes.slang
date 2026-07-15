// Copy canonical name bytes into prefix-assigned semantic-interface storage.
// Each lane handles one bounded name (at most 64 bytes), so work remains
// parallel over all exported module segments and declarations.

import gpu_index;
import byte_packing;
import atomics;

struct Params
{
    uint name_capacity;
    uint source_len;
    uint name_ref_count;
    uint module_segment_capacity;
    uint module_index_capacity;
    uint decl_capacity;
    uint member_capacity;
};

struct NameSpan
{
    uint start;
    uint len;
    uint kind;
    uint token_index;
};

ConstantBuffer<Params> gParams;
StructuredBuffer<uint> name_count_out;
StructuredBuffer<NameSpan> name_spans;
StructuredBuffer<uint> module_count_out;
StructuredBuffer<uint> module_key_segment_count;
StructuredBuffer<uint> module_key_segment_base;
StructuredBuffer<uint> module_key_segment_name_id;
StructuredBuffer<uint> module_segment_prefix;
StructuredBuffer<uint> module_segment_total;
StructuredBuffer<uint> public_decl_count;
StructuredBuffer<uint> public_decl_local_id;
StructuredBuffer<uint> decl_name_id;
StructuredBuffer<uint> interface_member_total;
StructuredBuffer<uint> interface_member_name_id;
StructuredBuffer<uint> interface_name_ref_len;
StructuredBuffer<uint> interface_name_ref_prefix;
ByteAddressBuffer source_bytes;
ByteAddressBuffer language_symbol_bytes;
RWStructuredBuffer<uint> interface_name_byte_words;

static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;
static const uint NAME_KIND_LANGUAGE_SYMBOL = 3u;
static const uint MAX_NAME_BYTES = 64u;

uint linear_thread_id(uint3 dtid)
{
    return linear_thread_id_2d(dtid, MAX_GROUPS_X, WG_SIZE);
}

uint name_id_for_ref(uint ref_i)
{
    if (ref_i < gParams.module_segment_capacity)
    {
        uint module_count = min(module_count_out[0u], gParams.module_index_capacity);
        uint segment_count = min(module_segment_total[0u], gParams.module_segment_capacity);
        if (ref_i >= segment_count || module_count == 0u)
            return 0xffffffffu;
        uint lo = 0u;
        uint hi = module_count;
        while (lo < hi)
        {
            uint mid = lo + (hi - lo) / 2u;
            uint end = module_segment_prefix[mid] + module_key_segment_count[mid];
            if (end <= ref_i)
                lo = mid + 1u;
            else
                hi = mid;
        }
        if (lo >= module_count)
            return 0xffffffffu;
        uint ordinal = ref_i - module_segment_prefix[lo];
        return ordinal < module_key_segment_count[lo]
                   ? module_key_segment_name_id[module_key_segment_base[lo] + ordinal]
                   : 0xffffffffu;
    }
    uint row = ref_i - gParams.module_segment_capacity;
    if (row < gParams.decl_capacity)
    {
        if (row >= min(public_decl_count[0u], gParams.decl_capacity))
            return 0xffffffffu;
        uint decl = public_decl_local_id[row];
        return decl < gParams.decl_capacity ? decl_name_id[decl] : 0xffffffffu;
    }
    uint member = row - gParams.decl_capacity;
    return member < min(interface_member_total[0u], gParams.member_capacity)
               ? interface_member_name_id[member]
               : 0xffffffffu;
}

uint load_name_byte(NameSpan span, uint byte_i)
{
    uint offset = span.start + byte_i;
    return span.kind == NAME_KIND_LANGUAGE_SYMBOL
               ? byte_address_load_u8(language_symbol_bytes, offset)
               : byte_address_load_u8_bounded(source_bytes, offset, gParams.source_len);
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint ref_i = linear_thread_id(dtid);
    if (ref_i >= gParams.name_ref_count)
        return;
    uint len = interface_name_ref_len[ref_i];
    if (len == 0u || len > MAX_NAME_BYTES)
        return;
    uint name_id = name_id_for_ref(ref_i);
    if (name_id >= min(name_count_out[0u], gParams.name_capacity))
        return;
    NameSpan span = name_spans[name_id];
    uint dst = interface_name_ref_prefix[ref_i];
    for (uint byte_i = 0u; byte_i < MAX_NAME_BYTES; byte_i += 1u)
    {
        if (byte_i >= len)
            break;
        uint output_byte = dst + byte_i;
        uint word = output_byte >> 2u;
        uint shift = (output_byte & 3u) * 8u;
        atomic_u32_or(
            interface_name_byte_words,
            word,
            (load_name_byte(span, byte_i) & 0xffu) << shift);
    }
}
