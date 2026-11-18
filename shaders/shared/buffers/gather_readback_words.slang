// Gathers small regions of up to GATHER_SOURCES source buffers into a dense
// readback image.
//
// Each region record is three words: output word, source word, word count.
// One dispatch reads its records from gather_params.first_region on, and one
// thread copies one region. The records of source slot s end at
// slot_end[s] (counted from first_region), so a thread finds its source by
// comparing its record index with the slot ends; slots past the last source
// end at region_count. The params sit behind a dynamic offset and every
// buffer is bound whole, so the bind group of a set of sources does not
// change between readbacks. Host readers that need thousands of small rows
// from a record's columns map one dense image instead of recording one buffer
// copy per row, or one dispatch per column.
struct GatherParams {
    uint first_region;
    uint region_count;
    uint2 reserved;
    uint4 slot_end_low;
    uint4 slot_end_high;
};

ConstantBuffer<GatherParams> gather_params;
StructuredBuffer<uint> gather_source_0;
StructuredBuffer<uint> gather_source_1;
StructuredBuffer<uint> gather_source_2;
StructuredBuffer<uint> gather_source_3;
StructuredBuffer<uint> gather_source_4;
StructuredBuffer<uint> gather_source_5;
StructuredBuffer<uint> gather_source_6;
StructuredBuffer<uint> gather_source_7;
StructuredBuffer<uint> gather_regions;
RWStructuredBuffer<uint> gather_output;

static const uint MAX_GROUPS_X = 65535u;
static const uint REGION_WORDS = 3u;

uint source_word(uint slot, uint word)
{
    switch (slot)
    {
    case 0u: return gather_source_0[word];
    case 1u: return gather_source_1[word];
    case 2u: return gather_source_2[word];
    case 3u: return gather_source_3[word];
    case 4u: return gather_source_4[word];
    case 5u: return gather_source_5[word];
    case 6u: return gather_source_6[word];
    default: return gather_source_7[word];
    }
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 gid: SV_GroupID, uint3 ltid: SV_GroupThreadID) {
    uint region_index = (gid.x + gid.y * MAX_GROUPS_X) * 256u + ltid.x;
    if (region_index >= gather_params.region_count) return;
    uint4 low = gather_params.slot_end_low;
    uint4 high = gather_params.slot_end_high;
    uint slot = uint(region_index >= low.x) + uint(region_index >= low.y)
        + uint(region_index >= low.z) + uint(region_index >= low.w)
        + uint(region_index >= high.x) + uint(region_index >= high.y)
        + uint(region_index >= high.z);
    uint record = (gather_params.first_region + region_index) * REGION_WORDS;
    uint output_word = gather_regions[record];
    uint first_source_word = gather_regions[record + 1u];
    uint word_count = gather_regions[record + 2u];
    for (uint word = 0u; word < word_count; word++) {
        gather_output[output_word + word] = source_word(slot, first_source_word + word);
    }
}
