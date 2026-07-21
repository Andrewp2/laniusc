import gpu_index;

struct Params { uint target_capacity; uint max_blocks; uint reserved0; uint reserved1; };
ConstantBuffer<Params> gParams;
StructuredBuffer<uint> target_lir_total;
RWStructuredBuffer<uint> target_schedule_slot_count;

[shader("compute")]
[numthreads(1, 1, 1)]
void main()
{
    uint total = min(gParams.target_capacity, target_lir_total[0u]);
    uint blocks = min((total + 255u) / 256u, gParams.max_blocks);
    target_schedule_slot_count[0u] = blocks * 256u;
}
