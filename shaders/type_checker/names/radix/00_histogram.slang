// Paper-aligned name radix foundation.
//
// GPU-only scheduling contract:
// - Earlier GPU extraction writes NameSpan rows for identifier/string names.
// - name_count_in is the GPU-written compact name count from lexeme scatter.
// - For byte offsets max_name_len - 1 down to 0, dispatch histogram, run GPU
//   prefix scans over bucket counts, then dispatch stable scatter.
// - The host may bind buffers and dispatch passes, but does not read or classify
//   name bytes.
//
// This pass builds per-block histograms for a GPU-friendly parallel radix sort.

import gpu_index;
import byte_packing;
import radix;

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
ByteAddressBuffer source_bytes;
ByteAddressBuffer language_symbol_bytes;
RWStructuredBuffer<uint> radix_block_histogram;

static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;
static const uint RADIX_BUCKETS = RADIX_U8_SENTINEL_BUCKETS;
static const uint NAME_KIND_IDENTIFIER = 1u;
static const uint NAME_KIND_STRING = 2u;
static const uint NAME_KIND_LANGUAGE_SYMBOL = 3u;

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

public struct NameRadixKeySource : IRadixU8KeySource
{
    public static uint active_count()
    {
        return active_name_count();
    }

    public static uint ordered_row(uint order_i)
    {
        return name_order_in[order_i];
    }

    public static uint radix_key(uint row, uint key_step)
    {
        return span_radix_key(row, key_step);
    }
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 gid: SV_GroupID, uint3 ltid: SV_GroupThreadID)
{
    uint block_idx = linear_group_id(gid);
    uint lane = ltid.x;
    if (gParams.radix_byte_offset >= name_max_len_in[0u])
        return;
    radix_u8_histogram_block<NameRadixKeySource>(
        block_idx,
        lane,
        gParams.n_blocks,
        gParams.radix_byte_offset,
        WG_SIZE,
        RADIX_BUCKETS,
        radix_block_histogram);
}
