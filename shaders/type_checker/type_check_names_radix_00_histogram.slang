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
ByteAddressBuffer source_bytes;
ByteAddressBuffer language_symbol_bytes;
RWStructuredBuffer<uint> radix_block_histogram;

static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;
static const uint RADIX_BUCKETS = 257u;
static const uint NAME_KIND_IDENTIFIER = 1u;
static const uint NAME_KIND_STRING = 2u;
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

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 gid: SV_GroupID, uint3 ltid: SV_GroupThreadID)
{
    uint block_idx = linear_group_id(gid);
    if (block_idx >= gParams.n_blocks)
        return;

    uint lane = ltid.x;
    uint block_base = block_idx * RADIX_BUCKETS;
    for (uint bucket = lane; bucket < RADIX_BUCKETS; bucket += WG_SIZE)
    {
        radix_block_histogram[block_base + bucket] = 0u;
    }
    DeviceMemoryBarrierWithGroupSync();

    uint order_i = block_idx * WG_SIZE + lane;
    if (order_i >= active_name_count())
        return;

    uint name_i = name_order_in[order_i];
    uint key = span_radix_key(name_i, gParams.radix_byte_offset);
    uint old_count;
    InterlockedAdd(radix_block_histogram[block_base + key], 1u, old_count);
}
