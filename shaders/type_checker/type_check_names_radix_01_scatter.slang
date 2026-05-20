// Paper-aligned name radix foundation.
//
// GPU-only scheduling contract:
// - This pass consumes GPU prefix-scan outputs over the per-block histograms
//   produced by type_check_names_radix_00_histogram.slang.
// - name_count_in is the GPU-written compact name count from lexeme scatter.
// - radix_bucket_base is the exclusive base for each radix bucket.
// - radix_block_bucket_prefix is the exclusive per-block prefix for each bucket.
// - Dispatch once per byte offset, from max_name_len - 1 down to 0, to preserve
//   stable lexicographic ordering for identifier/string names.
//
// This pass performs the stable scatter step of a GPU-friendly parallel radix sort.

import gpu_index;
import byte_packing;
import radix;
import scatter;

struct Params
{
    uint name_count;
    uint source_len;
    uint n_blocks;
    uint radix_byte_offset;
};

ConstantBuffer<Params> gParams;

struct NameSpan
{
    uint start;
    uint len;
    uint kind;
    uint token_index;
};

StructuredBuffer<NameSpan> name_spans;
StructuredBuffer<uint> name_count_in;
StructuredBuffer<uint> name_max_len_in;
StructuredBuffer<uint> name_order_in;
StructuredBuffer<uint> radix_bucket_base;
StructuredBuffer<uint> radix_block_bucket_prefix;
ByteAddressBuffer source_bytes;
ByteAddressBuffer language_symbol_bytes;
RWStructuredBuffer<uint> name_order_out;

static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;
static const uint RADIX_BUCKETS = RADIX_U8_SENTINEL_BUCKETS;
static const uint NAME_KIND_LANGUAGE_SYMBOL = 3u;

groupshared uint local_radix_keys[256];

uint linear_group_id(uint3 gid)
{
    return linear_group_id_2d(gid, MAX_GROUPS_X);
}

uint load_source_byte(uint byte_index)
{
    return byte_address_load_u8_bounded(source_bytes, byte_index, gParams.source_len);
}

uint load_language_symbol_byte(uint byte_index)
{
    return byte_address_load_u8(language_symbol_bytes, byte_index);
}

uint active_name_count()
{
    return min(name_count_in[0], gParams.name_count);
}

uint span_radix_key(uint name_i, uint byte_offset)
{
    if (name_i >= active_name_count())
        return 0u;

    NameSpan span = name_spans[name_i];
    if (byte_offset >= span.len)
        return 0u;

    uint b = span.kind == NAME_KIND_LANGUAGE_SYMBOL
                 ? load_language_symbol_byte(span.start + byte_offset)
                 : load_source_byte(span.start + byte_offset);
    return b + 1u;
}

public struct NameRadixScatterSource : IStableRadixScatterSource<uint>
{
    public static uint active_count()
    {
        return active_name_count();
    }

    public static uint inactive_value()
    {
        return 0u;
    }

    public static uint ordered_value(uint order_i)
    {
        return name_order_in[order_i];
    }

    public static uint radix_key(uint value, uint key_step)
    {
        return span_radix_key(value, key_step);
    }
}

public struct NameOrderOutSink : IScatterSink<uint>
{
    public static void store(uint dst, uint value)
    {
        name_order_out[dst] = value;
    }
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 gid: SV_GroupID, uint3 ltid: SV_GroupThreadID)
{
    uint block_idx = linear_group_id(gid);
    uint lane = ltid.x;
    if (gParams.radix_byte_offset >= name_max_len_in[0u])
    {
        uint order_i = block_idx * 256u + lane;
        if (order_i < active_name_count())
            name_order_out[order_i] = name_order_in[order_i];
        return;
    }
    stable_radix_scatter_block<uint, NameRadixScatterSource, NameOrderOutSink, 256>(
        block_idx,
        lane,
        gParams.n_blocks,
        gParams.radix_byte_offset,
        RADIX_BUCKETS,
        radix_bucket_base,
        radix_block_bucket_prefix,
        local_radix_keys);
}
