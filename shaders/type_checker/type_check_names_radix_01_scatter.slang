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
StructuredBuffer<uint> name_order_in;
StructuredBuffer<uint> radix_bucket_base;
StructuredBuffer<uint> radix_block_bucket_prefix;
ByteAddressBuffer source_bytes;
ByteAddressBuffer language_symbol_bytes;
RWStructuredBuffer<uint> name_order_out;

static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;
static const uint RADIX_BUCKETS = 257u;
static const uint NAME_KIND_LANGUAGE_SYMBOL = 3u;

uint linear_group_id(uint3 gid)
{
    return gid.x + gid.y * MAX_GROUPS_X;
}

uint load_source_byte(uint byte_index)
{
    if (byte_index >= gParams.source_len)
        return 0u;
    uint word = source_bytes.Load(byte_index & ~3u);
    uint shift = (byte_index & 3u) * 8u;
    return (word >> shift) & 0xffu;
}

uint load_language_symbol_byte(uint byte_index)
{
    uint word = language_symbol_bytes.Load(byte_index & ~3u);
    uint shift = (byte_index & 3u) * 8u;
    return (word >> shift) & 0xffu;
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

uint local_same_key_rank(uint block_begin, uint lane, uint key)
{
    uint rank = 0u;
    [loop]
    for (uint j = 0u; j < lane; j += 1u)
    {
        uint order_j = block_begin + j;
        if (order_j < active_name_count())
        {
            uint prev_name_i = name_order_in[order_j];
            if (span_radix_key(prev_name_i, gParams.radix_byte_offset) == key)
                rank += 1u;
        }
    }
    return rank;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 gid: SV_GroupID, uint3 ltid: SV_GroupThreadID)
{
    uint block_idx = linear_group_id(gid);
    if (block_idx >= gParams.n_blocks)
        return;

    uint lane = ltid.x;
    uint order_i = block_idx * WG_SIZE + lane;
    uint name_count = active_name_count();
    if (order_i >= name_count)
        return;

    uint name_i = name_order_in[order_i];
    uint key = span_radix_key(name_i, gParams.radix_byte_offset);
    uint rank = local_same_key_rank(block_idx * WG_SIZE, lane, key);
    uint block_prefix = radix_block_bucket_prefix[block_idx * RADIX_BUCKETS + key];
    uint dst = radix_bucket_base[key] + block_prefix + rank;

    if (dst < name_count)
        name_order_out[dst] = name_i;
}
