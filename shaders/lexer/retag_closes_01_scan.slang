import retag_closes_common;
import prefix_scan;

StructuredBuffer<uint> token_count;
StructuredBuffer<TokenOut> tokens_out;
RWStructuredBuffer<int> exscan_inblock;
RWStructuredBuffer<int> block_sum;

groupshared int s_val[256];

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID,
          uint3 ltid: SV_GroupThreadID,
          uint3 gid: SV_GroupID)
{
    const uint GSIZE = 256u;
    uint total = token_count[0];
    uint i = tid.x;

    int v = 0;
    if (i < total)
        v = delimiter_delta(tokens_out[i].kind);

    int inc = prefix_scan_i32_256(ltid.x, v);
    s_val[ltid.x] = inc;
    GroupMemoryBarrierWithGroupSync();

    if (i < total)
        exscan_inblock[i] = inc - v;

    if (ltid.x == 0u)
        block_sum[gid.x] = s_val[GSIZE - 1u];
}
