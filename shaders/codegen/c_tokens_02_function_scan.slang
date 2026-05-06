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
    uint n_hir_nodes;
};

ConstantBuffer<Params> gParams;
StructuredBuffer<int> token_function_delta;
RWStructuredBuffer<int> lengths_out;
RWStructuredBuffer<int> block_prefix_out;

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID, uint3 ltid: SV_GroupThreadID, uint3 gid: SV_GroupID)
{
    uint lane = ltid.x;
    uint i = tid.x;
    int value = i < gParams.n_tokens ? token_function_delta[i] : 0;
    int inclusive = prefix_scan_i32_256(lane, value);

    if (i < gParams.n_tokens)
        lengths_out[i] = inclusive;

    if (lane == 255u)
        block_prefix_out[gid.x] = inclusive;
}
