// Gathers small regions of one source buffer into a dense readback image.
//
// Each region record is three words: output word, source word, word count.
// One dispatch per source buffer reads its records from
// gather_params.first_region on, and one thread copies one region. The params
// sit behind a dynamic offset and every buffer is bound whole, so the bind
// group of a source does not change between readbacks. Host readers that need
// thousands of small rows map one dense image instead of recording one buffer
// copy per row, and upload one record per row rather than one per word.
struct GatherParams {
    uint first_region;
    uint region_count;
};

ConstantBuffer<GatherParams> gather_params;
StructuredBuffer<uint> gather_source;
StructuredBuffer<uint> gather_regions;
RWStructuredBuffer<uint> gather_output;

static const uint MAX_GROUPS_X = 65535u;
static const uint REGION_WORDS = 3u;

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 gid: SV_GroupID, uint3 ltid: SV_GroupThreadID) {
    uint region_index = (gid.x + gid.y * MAX_GROUPS_X) * 256u + ltid.x;
    if (region_index >= gather_params.region_count) return;
    uint record = (gather_params.first_region + region_index) * REGION_WORDS;
    uint output_word = gather_regions[record];
    uint source_word = gather_regions[record + 1u];
    uint word_count = gather_regions[record + 2u];
    for (uint word = 0u; word < word_count; word++) {
        gather_output[output_word + word] = gather_source[source_word + word];
    }
}
