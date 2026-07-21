import codegen.lir.schedule.common;
import codegen.lowering_ir;
import gpu_index;

struct Params { uint target_capacity; uint max_blocks; uint key_step; uint reserved; };
ConstantBuffer<Params> gParams;
StructuredBuffer<uint> target_lir_total;
StructuredBuffer<TargetScheduleKey> target_schedule_key;
StructuredBuffer<uint> target_schedule_order_in;
RWStructuredBuffer<uint> target_schedule_histogram;

groupshared Atomic<uint> bucket_count[256];
static const uint MAX_GROUPS_X = 65535u;

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 gid: SV_GroupID, uint3 tid: SV_GroupThreadID)
{
    uint block = linear_group_id_2d(gid, MAX_GROUPS_X);
    uint lane = tid.x;
    uint total = min(gParams.target_capacity, target_lir_total[0u]);
    uint blocks = min((total + 255u) / 256u, gParams.max_blocks);
    if (block >= blocks) return;

    bucket_count[lane].store(0u, MemoryOrder::Relaxed);
    GroupMemoryBarrierWithGroupSync();
    uint order_i = block * 256u + lane;
    if (order_i < total)
    {
        uint row = target_schedule_order_in[order_i];
        uint key = target_schedule_radix_key(target_schedule_key[row], gParams.key_step);
        bucket_count[key].add(1u, MemoryOrder::Relaxed);
    }
    GroupMemoryBarrierWithGroupSync();
    target_schedule_histogram[lane * blocks + block] =
        bucket_count[lane].load(MemoryOrder::Relaxed);
}
