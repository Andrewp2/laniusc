// Cooperative declaration-key sort for token-indexed tables up to 2048 rows.
// The scalable radix path remains the fallback above this capacity.

struct Params
{
    uint decl_capacity;
    uint reserved;
    uint n_blocks;
    uint key_step;
};

ConstantBuffer<Params> gParams;

StructuredBuffer<uint> decl_count_out;
StructuredBuffer<uint> decl_module_id;
StructuredBuffer<uint> decl_namespace;
StructuredBuffer<uint> decl_name_id;
RWStructuredBuffer<uint> decl_key_order;

static const uint INVALID = 0xffffffffu;
static const uint WG_SIZE = 256u;
static const uint SMALL_KEY_SORT_CAPACITY = 2048u;

groupshared uint shared_order[2048];

uint active_decl_count()
{
    return min(decl_count_out[0u], gParams.decl_capacity);
}

uint encoded_nullable(uint value)
{
    return value == INVALID ? 0u : value + 1u;
}

uint decl_key_lane(uint decl_i, uint lane)
{
    if (lane == 0u)
        return encoded_nullable(decl_module_id[decl_i]);
    if (lane == 1u)
        return decl_namespace[decl_i];
    return encoded_nullable(decl_name_id[decl_i]);
}

bool decl_key_less(uint left, uint right, uint active_count)
{
    bool left_padding = left >= active_count;
    bool right_padding = right >= active_count;
    if (left_padding || right_padding)
        return !left_padding && right_padding;
    for (uint lane = 0u; lane < 3u; lane += 1u)
    {
        uint left_value = decl_key_lane(left, lane);
        uint right_value = decl_key_lane(right, lane);
        if (left_value != right_value)
            return left_value < right_value;
    }
    return left < right;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 ltid: SV_GroupThreadID)
{
    uint lane = ltid.x;
    uint active_count = active_decl_count();
    if (gParams.decl_capacity > SMALL_KEY_SORT_CAPACITY)
        return;
    for (uint i = lane; i < SMALL_KEY_SORT_CAPACITY; i += WG_SIZE)
        shared_order[i] = i < active_count ? i : INVALID;
    GroupMemoryBarrierWithGroupSync();

    for (uint sequence = 2u; sequence <= SMALL_KEY_SORT_CAPACITY; sequence <<= 1u)
    {
        for (uint stride = sequence >> 1u; stride > 0u; stride >>= 1u)
        {
            for (uint i = lane; i < SMALL_KEY_SORT_CAPACITY; i += WG_SIZE)
            {
                uint peer = i ^ stride;
                if (peer <= i)
                    continue;
                uint left = shared_order[i];
                uint right = shared_order[peer];
                bool ascending = (i & sequence) == 0u;
                bool swap_values = ascending
                    ? decl_key_less(right, left, active_count)
                    : decl_key_less(left, right, active_count);
                if (swap_values)
                {
                    shared_order[i] = right;
                    shared_order[peer] = left;
                }
            }
            GroupMemoryBarrierWithGroupSync();
        }
    }
    for (uint i = lane; i < active_count; i += WG_SIZE)
        decl_key_order[i] = shared_order[i];
}
