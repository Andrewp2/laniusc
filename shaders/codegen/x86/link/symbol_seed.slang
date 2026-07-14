// Seed stable symbol order before the 13-pass linker radix sort.

import gpu_index;

struct Params
{
    uint symbol_count;
    uint reserved;
    uint n_blocks;
    uint key_step;
};

ConstantBuffer<Params> gParams;
RWStructuredBuffer<uint> link_symbol_order;

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    uint symbol_i = linear_dispatch_thread_id_2d(tid, 16776960u);
    if (symbol_i < gParams.symbol_count)
        link_symbol_order[symbol_i] = symbol_i;
}
