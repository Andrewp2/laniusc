// Cooperative imported-visibility key sort for tables up to 2048 rows.

struct Params
{
    uint capacity;
    uint reserved;
    uint n_blocks;
    uint key_step;
};

ConstantBuffer<Params> gParams;

StructuredBuffer<uint> import_visible_count_out;
StructuredBuffer<uint> import_visible_module_id;
StructuredBuffer<uint> import_visible_name_id;
RWStructuredBuffer<uint> import_visible_key_order;

static const uint INVALID = 0xffffffffu;
static const uint WG_SIZE = 256u;
static const uint SMALL_KEY_SORT_CAPACITY = 2048u;

groupshared uint shared_order[2048];

uint active_visible_count()
{
    return min(import_visible_count_out[0u], gParams.capacity);
}

uint encoded_nullable(uint value)
{
    return value == INVALID ? 0u : value + 1u;
}

bool visible_key_less(uint left, uint right, uint active_count)
{
    bool left_padding = left >= active_count;
    bool right_padding = right >= active_count;
    if (left_padding || right_padding)
        return !left_padding && right_padding;

    uint left_module = encoded_nullable(import_visible_module_id[left]);
    uint right_module = encoded_nullable(import_visible_module_id[right]);
    if (left_module != right_module)
        return left_module < right_module;
    uint left_name = encoded_nullable(import_visible_name_id[left]);
    uint right_name = encoded_nullable(import_visible_name_id[right]);
    if (left_name != right_name)
        return left_name < right_name;
    return left < right;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 ltid: SV_GroupThreadID)
{
    uint lane = ltid.x;
    uint active_count = active_visible_count();
    if (gParams.capacity > SMALL_KEY_SORT_CAPACITY)
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
                    ? visible_key_less(right, left, active_count)
                    : visible_key_less(left, right, active_count);
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
        import_visible_key_order[i] = shared_order[i];
}
