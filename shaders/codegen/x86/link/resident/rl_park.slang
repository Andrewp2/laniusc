// Parks one lowered object in the resident link store
// (codegen/x86/link/resident.rs, `park`): copies the rows and bytes the
// object uses from each region of its projection into the store. The counts
// are the object's metadata words, which the host copied into the store's
// metadata region earlier in the same encoder; the job's bound in each
// region, which is what the host knows, is only the upper limit. Every link
// kernel reads a region only below these counts.

struct ParkParams
{
    // Word of the slot's metadata in pk_meta, and the grid's lane count.
    uint meta_base;
    uint lanes;
    uint reserved0;
    uint reserved1;
    // Source word offsets: relocations, runtime relocations, undefined
    // rows, definitions, then text, rodata.
    uint4 src_rows;
    uint4 src_bytes;
    // Store word bases, in the same order.
    uint4 dst_rows;
    uint4 dst_bytes;
    // Words reserved for each region in the store (the job's bound).
    uint4 cap_rows;
    uint4 cap_bytes;
};

ConstantBuffer<ParkParams> gPK;
StructuredBuffer<uint> pk_meta;
StructuredBuffer<uint> pk_src_reloc;
StructuredBuffer<uint> pk_src_runtime;
StructuredBuffer<uint> pk_src_undef;
StructuredBuffer<uint> pk_src_def;
StructuredBuffer<uint> pk_src_text;
StructuredBuffer<uint> pk_src_rodata;
RWStructuredBuffer<uint> pk_reloc;
RWStructuredBuffer<uint> pk_undef;
RWStructuredBuffer<uint> pk_def;
RWStructuredBuffer<uint> pk_text;
RWStructuredBuffer<uint> pk_rodata;

uint meta(uint word) { return pk_meta[gPK.meta_base + word]; }

// Words holding `count` items of `words_per_item`, at most `cap`.
uint row_words(uint count, uint words_per_item, uint cap)
{
    return count >= cap / words_per_item ? cap : count * words_per_item;
}

// Words holding `bytes` bytes, at most `cap`.
uint byte_words(uint bytes, uint cap)
{
    return bytes / 4u >= cap ? cap : (bytes + 3u) / 4u;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    uint lane = tid.x;
    uint stride = gPK.lanes;
    // Metadata words (x86_object_artifact.rs `park_meta`, rl_common.slang
    // `object_geometry`): 1 relocations, 2 undefined symbols, 3 definitions,
    // 4 body bytes, 9..10 the wrapper's range, 13 runtime bytes, 15 rodata
    // bytes, 16 runtime relocations. A wrapper range that runs backwards is
    // an error the plan reports; the whole bound is copied for it.
    uint reloc = row_words(meta(1u), 8u, gPK.cap_rows.x);
    uint runtime = row_words(meta(16u), 8u, gPK.cap_rows.y);
    uint undef = row_words(meta(2u), 4u, gPK.cap_rows.z);
    uint def = row_words(meta(3u), 8u, gPK.cap_rows.w);
    uint text = gPK.cap_bytes.x;
    if (meta(10u) >= meta(9u))
    {
        uint wrapper = meta(10u) - meta(9u);
        uint body = meta(4u);
        uint runtime_bytes = meta(13u);
        uint limit = gPK.cap_bytes.x * 4u;
        if (wrapper <= limit && body <= limit - wrapper && runtime_bytes <= limit - wrapper - body)
            text = byte_words(wrapper + body + runtime_bytes, gPK.cap_bytes.x);
    }
    uint rodata = byte_words(meta(15u), gPK.cap_bytes.y);

    for (uint i = lane; i < reloc; i += stride)
        pk_reloc[gPK.dst_rows.x + i] = pk_src_reloc[gPK.src_rows.x + i];
    for (uint i = lane; i < runtime; i += stride)
        pk_reloc[gPK.dst_rows.y + i] = pk_src_runtime[gPK.src_rows.y + i];
    for (uint i = lane; i < undef; i += stride)
        pk_undef[gPK.dst_rows.z + i] = pk_src_undef[gPK.src_rows.z + i];
    for (uint i = lane; i < def; i += stride)
        pk_def[gPK.dst_rows.w + i] = pk_src_def[gPK.src_rows.w + i];
    for (uint i = lane; i < text; i += stride)
        pk_text[gPK.dst_bytes.x + i] = pk_src_text[gPK.src_bytes.x + i];
    for (uint i = lane; i < rodata; i += stride)
        pk_rodata[gPK.dst_bytes.y + i] = pk_src_rodata[gPK.src_bytes.y + i];
}
