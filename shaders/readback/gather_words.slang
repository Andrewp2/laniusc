// Gathers scattered words of one source buffer into a dense readback image.
//
// Each pair is (output word, source word). The host binds exactly the pairs of
// one source buffer, so the bound length is the pair count. Host readers that
// need thousands of small rows map one dense image instead of recording one
// buffer copy per row.
StructuredBuffer<uint> gather_source;
StructuredBuffer<uint2> gather_pairs;
RWStructuredBuffer<uint> gather_output;

static const uint MAX_GROUPS_X = 65535u;

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 gid: SV_GroupID, uint3 ltid: SV_GroupThreadID) {
    uint pair_count;
    uint pair_stride;
    gather_pairs.GetDimensions(pair_count, pair_stride);
    uint pair_index = (gid.x + gid.y * MAX_GROUPS_X) * 256u + ltid.x;
    if (pair_index >= pair_count) return;
    uint2 pair = gather_pairs[pair_index];
    gather_output[pair.x] = gather_source[pair.y];
}
