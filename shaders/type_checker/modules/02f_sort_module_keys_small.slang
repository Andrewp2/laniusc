// Cooperative module-key sort for source packs with at most 256 files.
//
// One lane owns each possible module row and the workgroup performs a shared
// bitonic sort over exact canonical path-prefix ids. Larger source packs
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
StructuredBuffer<uint> module_key_canonical_id;
RWStructuredBuffer<uint> module_key_order;

static const uint INVALID = 0xffffffffu;
static const uint SMALL_MODULE_SORT_CAPACITY = 256u;

groupshared uint shared_order[256];

uint active_module_count()
{
    return min(module_table_count_out[0u], gParams.module_capacity);
}

bool module_key_less(uint left, uint right, uint active_count)
{
    bool left_padding = left >= active_count;
    bool right_padding = right >= active_count;
    if (left_padding || right_padding)
        return !left_padding && right_padding;

    uint left_value = module_key_canonical_id[left];
    uint right_value = module_key_canonical_id[right];
    if (left_value != right_value)
        return left_value < right_value;
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
