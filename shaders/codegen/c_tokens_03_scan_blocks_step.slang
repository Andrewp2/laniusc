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
StructuredBuffer<uint> block_prefix_in;
RWStructuredBuffer<uint> block_prefix_out;

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    uint i = tid.x;
    if (i >= gParams.block_count)
        return;

    uint value = block_prefix_in[i];
    if (i >= gParams.scan_step)
        value += block_prefix_in[i - gParams.scan_step];
    block_prefix_out[i] = value;
}
