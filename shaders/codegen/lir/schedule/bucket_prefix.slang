// One workgroup per radix bucket scans that bucket's column of per-block
// counts (`histogram.slang` stores bucket b's counts at b * blocks + block).
// Each entry becomes the count of the bucket's rows in earlier blocks, and
// the bucket's total row count goes to target_schedule_bucket_total.
// `scatter.slang` adds the exclusive sum of the smaller buckets' totals, so
// a row's destination is the exclusive scan of the bucket-major histogram,
// as with a scan over the whole histogram.
import codegen.lir.schedule.common;
import shared.buffers.gpu_index;
import shared.collectives.prefix_scan;

// The bucket scan is the same for every digit, so it takes no digit row.
struct Params { uint target_capacity; uint max_blocks; uint key_step; uint reserved; };
ConstantBuffer<Params> gBuckets;
StructuredBuffer<uint> target_lir_total;
StructuredBuffer<uint> target_schedule_histogram;
RWStructuredBuffer<uint> target_schedule_global_prefix;
RWStructuredBuffer<uint> target_schedule_bucket_total;

groupshared uint bucket_scan[256];
static const uint MAX_GROUPS_X = 65535u;

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 gid: SV_GroupID, uint3 tid: SV_GroupThreadID)
{
    uint bucket = linear_group_id_2d(gid, MAX_GROUPS_X);
    if (bucket >= 256u)
        return;
    uint lane = tid.x;
    uint total = min(gBuckets.target_capacity, target_lir_total[0u]);
    uint blocks = min((total + 255u) / 256u, gBuckets.max_blocks);
    uint column = bucket * blocks;
    uint carry = 0u;
    for (uint base = 0u; base < blocks; base += 256u)
    {
        uint block = base + lane;
        uint count = block < blocks ? target_schedule_histogram[column + block] : 0u;
        uint inclusive = prefix_scan_inclusive<uint, PrefixScanU32Add, 256>(
            lane, count, bucket_scan);
        if (block < blocks)
            target_schedule_global_prefix[column + block] = carry + inclusive - count;
        carry += bucket_scan[255u];
        GroupMemoryBarrierWithGroupSync();
    }
    if (lane == 0u)
        target_schedule_bucket_total[bucket] = carry;
}
