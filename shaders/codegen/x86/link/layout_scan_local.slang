// Per-object exclusive section-size scan for the x86 linker.

import gpu_index;
import prefix_scan;

struct Params
{
    uint object_count;
    uint object_block_count;
    uint entry_object_index;
    uint out_capacity;
};

ConstantBuffer<Params> gLink;

// (text input start, text length, rodata input start, rodata length)
StructuredBuffer<uint4> link_object_sections;

RWStructuredBuffer<uint2> link_section_local_prefix;
RWStructuredBuffer<uint2> link_section_block_sum;

static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;
groupshared uint2 scan_values[256];

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 gid: SV_GroupID, uint3 ltid: SV_GroupThreadID)
{
    uint block = linear_group_id_2d(gid, MAX_GROUPS_X);
    if (block >= gLink.object_block_count)
        return;

    uint object_i = block * WG_SIZE + ltid.x;
    uint4 section = object_i < gLink.object_count
        ? link_object_sections[object_i]
        : uint4(0u, 0u, 0u, 0u);
    uint2 size = uint2(section.y, section.w);
    uint2 inclusive = prefix_scan_inclusive<uint2, PrefixScanU32x2Add, 256>(
        ltid.x,
        size,
        scan_values);

    if (object_i < gLink.object_count)
        link_section_local_prefix[object_i] = inclusive - size;
    if (ltid.x == WG_SIZE - 1u)
        link_section_block_sum[block] = inclusive;
}
