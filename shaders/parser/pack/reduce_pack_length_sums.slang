import reduce;

struct Params
{
    uint item_count;
};

ConstantBuffer<Params> gParams;
StructuredBuffer<uint> sc_in;
StructuredBuffer<uint> emit_in;

RWStructuredBuffer<uint> sc_out;
RWStructuredBuffer<uint> emit_out;

static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

groupshared uint sc_scratch[256];
groupshared uint emit_scratch[256];

uint linear_group_id(uint3 gid)
{
    return gid.x + gid.y * MAX_GROUPS_X;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 gid: SV_GroupID, uint3 ltid: SV_GroupThreadID)
{
    uint group_i = linear_group_id(gid);
    uint lane = ltid.x;
    uint item_i = group_i * WG_SIZE + lane;
    uint sc_value = item_i < gParams.item_count ? sc_in[item_i] : 0u;
    uint emit_value = item_i < gParams.item_count ? emit_in[item_i] : 0u;

    uint sc_sum = group_reduce_power_of_two<uint, ReduceU32Add, 256>(
        lane,
        sc_value,
        sc_scratch);
    uint emit_sum = group_reduce_power_of_two<uint, ReduceU32Add, 256>(
        lane,
        emit_value,
        emit_scratch);

    if (lane == 0u)
    {
        sc_out[group_i] = sc_sum;
        emit_out[group_i] = emit_sum;
    }
}
