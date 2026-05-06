import prefix_scan;

struct Params
{
    uint n_tokens;
    uint source_len;
    uint out_capacity;
    uint segment_count;
    uint segment_len;
    uint block_count;
    uint scan_step;
};

ConstantBuffer<Params> gParams;
StructuredBuffer<uint> lengths;
RWStructuredBuffer<uint> offsets_out;
RWStructuredBuffer<uint> block_prefix_out;

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID, uint3 ltid: SV_GroupThreadID, uint3 gid: SV_GroupID)
{
    uint lane = ltid.x;
    uint block_idx = gid.x;
    uint i = tid.x;
    uint value = i < gParams.n_tokens ? lengths[i] : 0u;
    uint inclusive = prefix_scan_u32x2_256(lane, uint2(value, 0u)).x;

    if (i < gParams.n_tokens)
        offsets_out[i] = inclusive - value;

    if (lane == 255u)
    {
        block_prefix_out[block_idx] = inclusive;
    }
}
