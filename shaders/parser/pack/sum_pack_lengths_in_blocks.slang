import reduce;

struct ActionHeader
{
    uint push_len;
    uint emit_len;
    uint pop_tag;
    uint pop_count;
};

struct Params
{
    uint n_pairs;
};

ConstantBuffer<Params> gParams;
StructuredBuffer<uint> token_count;
StructuredBuffer<ActionHeader> out_headers;

RWStructuredBuffer<uint> sc_block_sum;
RWStructuredBuffer<uint> emit_block_sum;

static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

groupshared uint sc_scratch[256];
groupshared uint emit_scratch[256];

uint linear_group_id(uint3 gid)
{
    return gid.x + gid.y * MAX_GROUPS_X;
}

uint active_pair_count()
{
    uint active_tokens = token_count[0u] + 2u;
    uint active_pairs = active_tokens > 0u ? active_tokens - 1u : 0u;
    return min(gParams.n_pairs, active_pairs);
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 gid: SV_GroupID, uint3 ltid: SV_GroupThreadID)
{
    uint group_i = linear_group_id(gid);
    uint lane = ltid.x;
    uint pair_i = group_i * WG_SIZE + lane;
    uint n_active = active_pair_count();

    uint sc_seed = 0u;
    uint emit_seed = 0u;
    if (pair_i < n_active)
    {
        ActionHeader header = out_headers[pair_i];
        sc_seed = header.push_len + header.pop_count;
        emit_seed = header.emit_len;
    }

    uint sc_sum = group_reduce_power_of_two<uint, ReduceU32Add, 256>(
        lane,
        sc_seed,
        sc_scratch);
    uint emit_sum = group_reduce_power_of_two<uint, ReduceU32Add, 256>(
        lane,
        emit_seed,
        emit_scratch);

    if (lane == 0u)
    {
        sc_block_sum[group_i] = sc_sum;
        emit_block_sum[group_i] = emit_sum;
    }
}
