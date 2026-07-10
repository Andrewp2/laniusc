// Cooperative module-key sort for source packs with at most 256 files.
//
// One lane owns each possible module row and the workgroup performs a shared
// bitonic sort over the complete eight-segment path key. Larger source packs
// keep using the scalable multi-workgroup radix path.

struct Params
{
    uint module_capacity;
    uint reserved;
    uint n_blocks;
    uint key_step;
};

ConstantBuffer<Params> gParams;

StructuredBuffer<uint> module_table_count_out;
StructuredBuffer<uint> module_key_segment_count;
StructuredBuffer<uint> module_key_segment_base;
StructuredBuffer<uint> module_key_segment_name_id;
RWStructuredBuffer<uint> module_key_order;

static const uint INVALID = 0xffffffffu;
static const uint SMALL_MODULE_SORT_CAPACITY = 256u;
static const uint MODULE_KEY_SEGMENT_ROW_WIDTH = 8u;

groupshared uint shared_order[256];

uint active_module_count()
{
    return min(module_table_count_out[0u], gParams.module_capacity);
}

uint module_key_lane(uint module_i, uint lane)
{
    uint count = min(module_key_segment_count[module_i], MODULE_KEY_SEGMENT_ROW_WIDTH);
    if (lane >= count)
        return 0u;
    uint base = module_key_segment_base[module_i];
    uint name_id = module_key_segment_name_id[base + lane];
    return name_id == INVALID ? 0u : name_id + 1u;
}

bool module_key_less(uint left, uint right, uint active_count)
{
    bool left_padding = left >= active_count;
    bool right_padding = right >= active_count;
    if (left_padding || right_padding)
        return !left_padding && right_padding;

    for (uint lane = 0u; lane < MODULE_KEY_SEGMENT_ROW_WIDTH; lane += 1u)
    {
        uint left_value = module_key_lane(left, lane);
        uint right_value = module_key_lane(right, lane);
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
    uint active_count = active_module_count();
    if (gParams.module_capacity > SMALL_MODULE_SORT_CAPACITY)
        return;

    shared_order[lane] = lane < active_count ? lane : INVALID;
    GroupMemoryBarrierWithGroupSync();

    for (uint sequence = 2u; sequence <= SMALL_MODULE_SORT_CAPACITY; sequence <<= 1u)
    {
        for (uint stride = sequence >> 1u; stride > 0u; stride >>= 1u)
        {
            uint peer = lane ^ stride;
            if (peer > lane)
            {
                uint left = shared_order[lane];
                uint right = shared_order[peer];
                bool ascending = (lane & sequence) == 0u;
                bool swap_values = ascending
                    ? module_key_less(right, left, active_count)
                    : module_key_less(left, right, active_count);
                if (swap_values)
                {
                    shared_order[lane] = right;
                    shared_order[peer] = left;
                }
            }
            GroupMemoryBarrierWithGroupSync();
        }
    }

    if (lane < active_count)
        module_key_order[lane] = shared_order[lane];
}
