import codegen.lir.schedule.common;
import codegen.lowering_ir;
import gpu_index;
import stable_radix_scatter;

struct Params { uint target_capacity; uint max_blocks; uint key_step; uint reserved; };
ConstantBuffer<Params> gParams;
StructuredBuffer<uint> target_lir_total;
StructuredBuffer<TargetScheduleKey> target_schedule_key;
StructuredBuffer<uint> target_schedule_order_in;
StructuredBuffer<uint> target_schedule_global_prefix;
RWStructuredBuffer<uint> target_schedule_order_out;

static const uint MAX_GROUPS_X = 65535u;
static const uint INACTIVE_KEY = 256u;

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 gid: SV_GroupID, uint3 tid: SV_GroupThreadID)
{
    uint block = linear_group_id_2d(gid, MAX_GROUPS_X);
    uint lane = tid.x;
    uint total = min(gParams.target_capacity, target_lir_total[0u]);
    uint blocks = min((total + 255u) / 256u, gParams.max_blocks);
    if (block >= blocks) return;

    uint order_i = block * 256u + lane;
    bool active = order_i < total;
    uint row = active ? target_schedule_order_in[order_i] : 0u;
    uint key = active
        ? target_schedule_radix_key(target_schedule_key[row], gParams.key_step)
        : INACTIVE_KEY;
    uint sorted_key;
    uint sorted_row;
    uint local_rank;
    stable_radix_sort_byte_rank(
        lane, key, row, sorted_key, sorted_row, local_rank);
    if (sorted_key == INACTIVE_KEY) return;

    uint global_prefix =
        target_schedule_global_prefix[sorted_key * blocks + block];
    uint dst = global_prefix + local_rank;
    if (dst < total)
        target_schedule_order_out[dst] = sorted_row;
}
