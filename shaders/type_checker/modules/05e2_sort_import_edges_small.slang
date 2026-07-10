// Cooperative import-edge sort for compact source packs up to 2048 imports.

struct Params
{
    uint module_capacity;
    uint reserved;
    uint n_blocks;
    uint key_step;
};

ConstantBuffer<Params> gParams;

StructuredBuffer<uint> import_count_out;
StructuredBuffer<uint> import_module_id;
StructuredBuffer<uint> import_target_module_id;
StructuredBuffer<uint> import_status;
RWStructuredBuffer<uint> import_edge_key_order;

static const uint INVALID = 0xffffffffu;
static const uint IMPORT_STATUS_OK = 0u;
static const uint WG_SIZE = 256u;
static const uint SMALL_EDGE_SORT_CAPACITY = 2048u;

groupshared uint shared_order[2048];

uint active_import_count()
{
    return min(import_count_out[0u], gParams.module_capacity);
}

bool valid_import_edge(uint import_i, uint active_count)
{
    return import_i < active_count && import_status[import_i] == IMPORT_STATUS_OK &&
           import_module_id[import_i] != INVALID && import_target_module_id[import_i] != INVALID;
}

uint edge_lane(uint import_i, uint lane, uint active_count)
{
    if (!valid_import_edge(import_i, active_count))
        return 0u;
    uint value = lane == 0u ? import_module_id[import_i] : import_target_module_id[import_i];
    return value + 1u;
}

bool edge_less(uint left, uint right, uint active_count)
{
    bool left_padding = left >= active_count;
    bool right_padding = right >= active_count;
    if (left_padding || right_padding)
        return !left_padding && right_padding;
    for (uint lane = 0u; lane < 2u; lane += 1u)
    {
        uint left_value = edge_lane(left, lane, active_count);
        uint right_value = edge_lane(right, lane, active_count);
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
    uint active_count = active_import_count();
    if (gParams.module_capacity > SMALL_EDGE_SORT_CAPACITY)
        return;
    for (uint i = lane; i < SMALL_EDGE_SORT_CAPACITY; i += WG_SIZE)
        shared_order[i] = i < active_count ? i : INVALID;
    GroupMemoryBarrierWithGroupSync();

    for (uint sequence = 2u; sequence <= SMALL_EDGE_SORT_CAPACITY; sequence <<= 1u)
    {
        for (uint stride = sequence >> 1u; stride > 0u; stride >>= 1u)
        {
            for (uint i = lane; i < SMALL_EDGE_SORT_CAPACITY; i += WG_SIZE)
            {
                uint peer = i ^ stride;
                if (peer <= i)
                    continue;
                uint left = shared_order[i];
                uint right = shared_order[peer];
                bool ascending = (i & sequence) == 0u;
                bool swap_values = ascending
                    ? edge_less(right, left, active_count)
                    : edge_less(left, right, active_count);
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
        import_edge_key_order[i] = shared_order[i];
}
