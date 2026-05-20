// Build indirect dispatch arguments from the max of two GPU-resident counts.
//
// This is for paired compact streams that are validated or consumed by a
// single shader invocation. It keeps scheduling on GPU counts without adding a
// host readback or picking one stream as a proxy for the other.

struct Params
{
    uint left_capacity;
    uint right_capacity;
    uint multiplier;
    uint reserved;
};

ConstantBuffer<Params> gParams;

StructuredBuffer<uint> left_count_in;
StructuredBuffer<uint> right_count_in;
RWStructuredBuffer<uint> dispatch_args;

static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

uint scaled_active_count()
{
    uint left_count = min(left_count_in[0], gParams.left_capacity);
    uint right_count = min(right_count_in[0], gParams.right_capacity);
    uint count = max(left_count, right_count);
    uint multiplier = max(gParams.multiplier, 1u);
    if (count > 0xffffffffu / multiplier)
        return 0xffffffffu;
    return count * multiplier;
}

[shader("compute")]
[numthreads(1, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    if (dtid.x != 0u || dtid.y != 0u || dtid.z != 0u)
        return;

    uint groups = max(1u, (scaled_active_count() + WG_SIZE - 1u) / WG_SIZE);
    dispatch_args[0u] = min(groups, MAX_GROUPS_X);
    dispatch_args[1u] = max(1u, (groups + MAX_GROUPS_X - 1u) / MAX_GROUPS_X);
    dispatch_args[2u] = 1u;
}
