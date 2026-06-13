// Build indirect dispatch arguments from a GPU-resident count buffer.
//
// This is for compact record pipelines that already produced their active
// record count on the GPU. It keeps later passes sized to the compact stream
// without adding a host readback.

struct Params
{
    uint capacity;
    uint multiplier;
    uint reserved0;
    uint reserved1;
};

ConstantBuffer<Params> gParams;

StructuredBuffer<uint> count_in;
RWStructuredBuffer<uint> dispatch_args;

static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

uint active_count()
{
    uint count = min(count_in[0], gParams.capacity);
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

    uint groups = max(1u, (active_count() + WG_SIZE - 1u) / WG_SIZE);
    dispatch_args[0u] = min(groups, MAX_GROUPS_X);
    dispatch_args[1u] = max(1u, (groups + MAX_GROUPS_X - 1u) / MAX_GROUPS_X);
    dispatch_args[2u] = 1u;
}
