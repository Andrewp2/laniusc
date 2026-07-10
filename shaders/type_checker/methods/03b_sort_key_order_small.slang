// One-workgroup bitonic method-key sort for small and medium source packs.
//
// The scalable radix path remains available above SMALL_METHOD_SORT_CAPACITY.
// Below it, 256 lanes cooperatively sort the complete token-indexed key order
// in shared memory, replacing ninety-six separately recorded radix commands.

struct Params
{
    uint method_capacity;
    uint reserved;
    uint n_blocks;
    uint key_step;
};

ConstantBuffer<Params> gParams;

StructuredBuffer<uint> token_count;
StructuredBuffer<uint> method_decl_impl_node;
StructuredBuffer<uint> method_decl_receiver_ref_tag;
StructuredBuffer<uint> method_decl_receiver_ref_payload;
StructuredBuffer<uint> method_decl_module_id;
StructuredBuffer<uint> method_decl_name_id;
StructuredBuffer<uint> module_type_path_type;
StructuredBuffer<uint> type_instance_decl_token;
StructuredBuffer<uint> type_instance_arg_count;
StructuredBuffer<uint> type_instance_arg_hash;
RWStructuredBuffer<uint> method_key_order;

static const uint INVALID = 0xffffffffu;
static const uint TYPE_REF_INVALID = 0u;
static const uint TYPE_REF_GENERIC_PARAM = 2u;
static const uint TYPE_REF_INSTANCE = 3u;
static const uint TY_STRUCT_BASE = 4096u;
static const uint TY_ENUM_BASE = 6144u;
static const uint TY_GENERIC_BASE = 8192u;
static const uint WG_SIZE = 256u;
static const uint SMALL_METHOD_SORT_CAPACITY = 2048u;

groupshared uint shared_order[2048];

uint active_method_capacity()
{
    return min(token_count[0u], gParams.method_capacity);
}

bool valid_method_record(uint fn_i, uint active_count)
{
    return fn_i < active_count && method_decl_impl_node[fn_i] != INVALID &&
           method_decl_module_id[fn_i] != INVALID &&
           method_decl_receiver_ref_tag[fn_i] != TYPE_REF_INVALID &&
           method_decl_receiver_ref_payload[fn_i] != INVALID &&
           method_decl_name_id[fn_i] != INVALID;
}

uint decl_token_from_type_code(uint ty)
{
    if (ty >= TY_STRUCT_BASE && ty < TY_ENUM_BASE)
        return ty - TY_STRUCT_BASE;
    if (ty >= TY_ENUM_BASE && ty < TY_GENERIC_BASE)
        return ty - TY_ENUM_BASE;
    return INVALID;
}

uint resolved_nominal_decl_token(uint token_i, uint active_count)
{
    if (token_i >= active_count)
        return INVALID;
    return decl_token_from_type_code(module_type_path_type[token_i]);
}

uint type_ref_payload_key(uint tag, uint payload, uint active_count)
{
    if (tag == TYPE_REF_GENERIC_PARAM)
        return INVALID;
    if (tag == TYPE_REF_INSTANCE && payload < active_count)
    {
        uint decl_token = type_instance_decl_token[payload];
        if (decl_token != INVALID)
            return decl_token;
        decl_token = resolved_nominal_decl_token(payload, active_count);
        if (decl_token != INVALID)
            return decl_token;
    }
    return payload;
}

uint receiver_arg_count(uint fn_i, uint active_count)
{
    uint tag = method_decl_receiver_ref_tag[fn_i];
    uint payload = method_decl_receiver_ref_payload[fn_i];
    return tag == TYPE_REF_INSTANCE && payload < active_count
        ? type_instance_arg_count[payload]
        : 0u;
}

uint receiver_arg_hash(uint fn_i, uint active_count)
{
    uint tag = method_decl_receiver_ref_tag[fn_i];
    uint payload = method_decl_receiver_ref_payload[fn_i];
    return tag == TYPE_REF_INSTANCE && payload < active_count
        ? type_instance_arg_hash[payload]
        : 0u;
}

uint method_key_lane(uint fn_i, uint lane, uint active_count)
{
    if (!valid_method_record(fn_i, active_count))
        return 0u;
    if (lane == 0u)
        return method_decl_receiver_ref_tag[fn_i] + 1u;
    if (lane == 1u)
        return type_ref_payload_key(
            method_decl_receiver_ref_tag[fn_i],
            method_decl_receiver_ref_payload[fn_i],
            active_count) + 1u;
    if (lane == 2u)
        return receiver_arg_count(fn_i, active_count) + 1u;
    if (lane == 3u)
        return receiver_arg_hash(fn_i, active_count);
    if (lane == 4u)
        return method_decl_name_id[fn_i] + 1u;
    return method_decl_module_id[fn_i] + 1u;
}

bool method_key_less(uint left, uint right, uint active_count)
{
    bool left_padding = left >= active_count;
    bool right_padding = right >= active_count;
    if (left_padding || right_padding)
        return !left_padding && right_padding;

    for (uint lane = 0u; lane < 6u; lane += 1u)
    {
        uint left_value = method_key_lane(left, lane, active_count);
        uint right_value = method_key_lane(right, lane, active_count);
        if (left_value != right_value)
            return left_value < right_value;
    }
    // The old stable radix path preserved the fn-token seed order.
    return left < right;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 ltid: SV_GroupThreadID)
{
    uint lane = ltid.x;
    uint active_count = active_method_capacity();
    if (gParams.method_capacity > SMALL_METHOD_SORT_CAPACITY)
        return;

    for (uint i = lane; i < SMALL_METHOD_SORT_CAPACITY; i += WG_SIZE)
        shared_order[i] = i < active_count ? i : INVALID;
    GroupMemoryBarrierWithGroupSync();

    for (uint sequence = 2u; sequence <= SMALL_METHOD_SORT_CAPACITY; sequence <<= 1u)
    {
        for (uint stride = sequence >> 1u; stride > 0u; stride >>= 1u)
        {
            for (uint i = lane; i < SMALL_METHOD_SORT_CAPACITY; i += WG_SIZE)
            {
                uint peer = i ^ stride;
                if (peer <= i)
                    continue;

                uint left = shared_order[i];
                uint right = shared_order[peer];
                bool ascending = (i & sequence) == 0u;
                bool swap_values = ascending
                    ? method_key_less(right, left, active_count)
                    : method_key_less(left, right, active_count);
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
        method_key_order[i] = shared_order[i];
}
