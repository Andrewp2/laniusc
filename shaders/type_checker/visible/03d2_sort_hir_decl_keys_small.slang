// Cooperative HIR-visible declaration sort for tables up to 2048 rows.
// Larger declaration tables retain the scalable byte-radix schedule.

struct Params
{
    uint decl_capacity;
    uint reserved;
    uint n_blocks;
    uint key_step;
};

ConstantBuffer<Params> gParams;

StructuredBuffer<uint> hir_visible_decl_count_out;
StructuredBuffer<uint> hir_visible_decl_owner_fn;
StructuredBuffer<uint> hir_visible_decl_name_id;
StructuredBuffer<uint> hir_visible_decl_token;
RWStructuredBuffer<uint> hir_visible_decl_key_order;

static const uint INVALID = 0xffffffffu;
static const uint WG_SIZE = 256u;
static const uint SMALL_VISIBLE_DECL_SORT_CAPACITY = 2048u;

groupshared uint shared_order[2048];

uint active_decl_count()
{
    return min(hir_visible_decl_count_out[0u], gParams.decl_capacity);
}

uint encoded_nullable(uint value)
{
    return value == INVALID ? 0u : value + 1u;
}

bool decl_key_less(uint left, uint right, uint active_count)
{
    bool left_padding = left >= active_count;
    bool right_padding = right >= active_count;
    if (left_padding || right_padding)
        return !left_padding && right_padding;

    uint left_owner = hir_visible_decl_owner_fn[left];
    uint right_owner = hir_visible_decl_owner_fn[right];
    if (left_owner != right_owner)
        return left_owner < right_owner;
    uint left_name = encoded_nullable(hir_visible_decl_name_id[left]);
    uint right_name = encoded_nullable(hir_visible_decl_name_id[right]);
    if (left_name != right_name)
        return left_name < right_name;
    uint left_token = encoded_nullable(hir_visible_decl_token[left]);
    uint right_token = encoded_nullable(hir_visible_decl_token[right]);
    return left_token != right_token ? left_token < right_token : left < right;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 ltid: SV_GroupThreadID)
{
    uint lane = ltid.x;
    uint active_count = active_decl_count();
    if (gParams.decl_capacity > SMALL_VISIBLE_DECL_SORT_CAPACITY)
        return;

    for (uint i = lane; i < SMALL_VISIBLE_DECL_SORT_CAPACITY; i += WG_SIZE)
        shared_order[i] = i < active_count ? i : INVALID;
    GroupMemoryBarrierWithGroupSync();

    for (uint sequence = 2u; sequence <= SMALL_VISIBLE_DECL_SORT_CAPACITY; sequence <<= 1u)
    {
        for (uint stride = sequence >> 1u; stride > 0u; stride >>= 1u)
        {
            for (uint i = lane; i < SMALL_VISIBLE_DECL_SORT_CAPACITY; i += WG_SIZE)
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
        hir_visible_decl_key_order[i] = shared_order[i];
}
