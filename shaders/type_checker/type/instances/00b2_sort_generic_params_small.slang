// Cooperative sort for both generic-parameter lookup orders.
//
// The same 256 lanes sort owner/name/node and owner/kind/node orderings in one
// dispatch for compact tables up to 2048 rows. Larger tables retain the two
// scalable radix schedules.

struct Params
{
    uint decl_capacity;
    uint reserved;
    uint n_blocks;
    uint key_step;
};

ConstantBuffer<Params> gParams;

StructuredBuffer<uint> generic_param_count_out;
StructuredBuffer<uint> generic_param_owner_node;
StructuredBuffer<uint> generic_param_name_id;
StructuredBuffer<uint> generic_param_node;
StructuredBuffer<uint> generic_param_kind;
RWStructuredBuffer<uint> generic_param_key_order;
RWStructuredBuffer<uint> generic_param_slot_order;

static const uint INVALID = 0xffffffffu;
static const uint WG_SIZE = 256u;
static const uint SMALL_GENERIC_SORT_CAPACITY = 2048u;

groupshared uint shared_key_order[2048];
groupshared uint shared_slot_order[2048];

uint active_generic_param_count()
{
    return min(generic_param_count_out[0u], gParams.decl_capacity);
}

uint encoded_nullable(uint value)
{
    return value == INVALID ? 0u : value + 1u;
}

bool padding_less(uint left, uint right, uint active_count, out bool decided)
{
    bool left_padding = left >= active_count;
    bool right_padding = right >= active_count;
    decided = left_padding || right_padding;
    return !left_padding && right_padding;
}

bool key_less(uint left, uint right, uint active_count)
{
    bool decided;
    bool result = padding_less(left, right, active_count, decided);
    if (decided)
        return result;

    uint left_owner = encoded_nullable(generic_param_owner_node[left]);
    uint right_owner = encoded_nullable(generic_param_owner_node[right]);
    if (left_owner != right_owner)
        return left_owner < right_owner;
    uint left_name = encoded_nullable(generic_param_name_id[left]);
    uint right_name = encoded_nullable(generic_param_name_id[right]);
    if (left_name != right_name)
        return left_name < right_name;
    uint left_node = encoded_nullable(generic_param_node[left]);
    uint right_node = encoded_nullable(generic_param_node[right]);
    return left_node != right_node ? left_node < right_node : left < right;
}

bool slot_less(uint left, uint right, uint active_count)
{
    bool decided;
    bool result = padding_less(left, right, active_count, decided);
    if (decided)
        return result;

    uint left_owner = encoded_nullable(generic_param_owner_node[left]);
    uint right_owner = encoded_nullable(generic_param_owner_node[right]);
    if (left_owner != right_owner)
        return left_owner < right_owner;
    uint left_kind = generic_param_kind[left];
    uint right_kind = generic_param_kind[right];
    if (left_kind != right_kind)
        return left_kind < right_kind;
    uint left_node = encoded_nullable(generic_param_node[left]);
    uint right_node = encoded_nullable(generic_param_node[right]);
    return left_node != right_node ? left_node < right_node : left < right;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 ltid: SV_GroupThreadID)
{
    uint lane = ltid.x;
    uint active_count = active_generic_param_count();
    if (gParams.decl_capacity > SMALL_GENERIC_SORT_CAPACITY)
        return;

    for (uint i = lane; i < SMALL_GENERIC_SORT_CAPACITY; i += WG_SIZE)
    {
        uint row = i < active_count ? i : INVALID;
        shared_key_order[i] = row;
        shared_slot_order[i] = row;
    }
    GroupMemoryBarrierWithGroupSync();

    for (uint sequence = 2u; sequence <= SMALL_GENERIC_SORT_CAPACITY; sequence <<= 1u)
    {
        for (uint stride = sequence >> 1u; stride > 0u; stride >>= 1u)
        {
            for (uint i = lane; i < SMALL_GENERIC_SORT_CAPACITY; i += WG_SIZE)
            {
                uint peer = i ^ stride;
                if (peer <= i)
                    continue;
                bool ascending = (i & sequence) == 0u;

                uint left_key = shared_key_order[i];
                uint right_key = shared_key_order[peer];
                bool swap_key = ascending
                    ? key_less(right_key, left_key, active_count)
                    : key_less(left_key, right_key, active_count);
                if (swap_key)
                {
                    shared_key_order[i] = right_key;
                    shared_key_order[peer] = left_key;
                }

                uint left_slot = shared_slot_order[i];
                uint right_slot = shared_slot_order[peer];
                bool swap_slot = ascending
                    ? slot_less(right_slot, left_slot, active_count)
                    : slot_less(left_slot, right_slot, active_count);
                if (swap_slot)
                {
                    shared_slot_order[i] = right_slot;
                    shared_slot_order[peer] = left_slot;
                }
            }
            GroupMemoryBarrierWithGroupSync();
        }
    }

    for (uint i = lane; i < active_count; i += WG_SIZE)
    {
        generic_param_key_order[i] = shared_key_order[i];
        generic_param_slot_order[i] = shared_slot_order[i];
    }
}
