// Gathers scattered words of one source buffer into a dense readback image.
//
// Each pair is (output word, source word). One dispatch per source buffer
// reads its pairs from gather_params.first_pair on. The params sit behind a
// dynamic offset and every buffer is bound whole, so the bind group of a
// source does not change between readbacks. Host readers that need thousands
// of small rows map one dense image instead of recording one buffer copy per
// row.
struct GatherParams {
    uint first_pair;
    uint pair_count;
};

ConstantBuffer<GatherParams> gather_params;
StructuredBuffer<uint> gather_source;
StructuredBuffer<uint2> gather_pairs;
RWStructuredBuffer<uint> gather_output;

static const uint MAX_GROUPS_X = 65535u;

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 gid: SV_GroupID, uint3 ltid: SV_GroupThreadID) {
    uint pair_index = (gid.x + gid.y * MAX_GROUPS_X) * 256u + ltid.x;
    if (pair_index >= gather_params.pair_count) return;
    uint2 pair = gather_pairs[gather_params.first_pair + pair_index];
    gather_output[pair.x] = gather_source[pair.y];
}
