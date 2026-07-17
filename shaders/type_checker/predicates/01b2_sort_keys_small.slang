// Cooperative sparse predicate-key sort for HIR tables up to 8192 rows.
//
// One 256-lane workgroup performs the complete stable key ordering in shared
// memory. The host loads this optional 32 KiB path only when the adapter exposes
// enough workgroup storage; larger tables and baseline adapters retain the
// scalable byte-radix implementation.

struct Params
{
    uint predicate_capacity;
    uint token_capacity;
    uint n_blocks;
    uint key_step;
    uint mode;
    uint reserved;
};

ConstantBuffer<Params> gParams;

StructuredBuffer<uint> predicate_count_in;
StructuredBuffer<uint> hir_token_pos;
StructuredBuffer<uint> visible_type;
StructuredBuffer<uint> type_expr_ref_tag;
StructuredBuffer<uint> type_expr_ref_payload;
StructuredBuffer<uint> type_generic_param_slot_by_token;
StructuredBuffer<uint> predicate_owner_node;
StructuredBuffer<uint> predicate_subject_token;
StructuredBuffer<uint> predicate_bound_decl_id;
StructuredBuffer<uint> predicate_bound_arg_count;
StructuredBuffer<uint> predicate_bound_first_arg_token;
StructuredBuffer<uint> predicate_bound_second_arg_token;
StructuredBuffer<uint> predicate_status;
StructuredBuffer<uint4> hir_param_record;
StructuredBuffer<uint> predicate_method_contract_owner_hir;
StructuredBuffer<uint> predicate_method_contract_name_id;
RWStructuredBuffer<uint> predicate_key_order;

static const uint INVALID = 0xffffffffu;
static const uint PREDICATE_KEY_MODE_OWNER = 0u;
static const uint PREDICATE_KEY_MODE_IMPL = 1u;
static const uint PREDICATE_KEY_MODE_METHOD_CONTRACT = 2u;
static const uint PREDICATE_KEY_MODE_METHOD_PARAM = 3u;
static const uint PREDICATE_STATUS_OK = 0u;
static const uint PREDICATE_ARG_TYPE_CODE_BIT = 0x80000000u;
static const uint TYPE_REF_SCALAR = 1u;
static const uint TYPE_REF_GENERIC_PARAM = 2u;
static const uint TY_UNKNOWN = 0u;
static const uint TY_GENERIC_BASE = 8192u;
static const uint WG_SIZE = 256u;
static const uint SMALL_KEY_SORT_CAPACITY = 8192u;

groupshared uint shared_order[8192];

uint active_predicate_count()
{
    return min(predicate_count_in[0u], gParams.predicate_capacity);
}

bool valid_token(uint token)
{
    return token < gParams.token_capacity;
}

bool valid_node(uint node)
{
    return node < gParams.predicate_capacity;
}

uint encoded_nullable(uint value, uint invalid)
{
    return value == invalid ? 0u : value + 1u;
}

uint type_code_for_ref(uint tag, uint payload)
{
    if (tag == TYPE_REF_SCALAR)
        return payload;
    if (tag == TYPE_REF_GENERIC_PARAM)
    {
        uint slot = valid_token(payload) ? type_generic_param_slot_by_token[payload] : INVALID;
        return slot == INVALID ? TY_UNKNOWN : TY_GENERIC_BASE + slot;
    }
    return TY_UNKNOWN;
}

uint type_code_for_type_token(uint token)
{
    if (!valid_token(token))
        return TY_UNKNOWN;
    uint ty = type_code_for_ref(type_expr_ref_tag[token], type_expr_ref_payload[token]);
    return ty != TY_UNKNOWN ? ty : visible_type[token];
}

uint predicate_arg_type_code(uint arg)
{
    if (arg != INVALID && (arg & PREDICATE_ARG_TYPE_CODE_BIT) != 0u)
        return arg & ~PREDICATE_ARG_TYPE_CODE_BIT;
    return type_code_for_type_token(arg);
}

bool valid_owner_predicate(uint pred)
{
    if (!valid_node(pred) || predicate_status[pred] != PREDICATE_STATUS_OK)
        return false;
    uint owner = predicate_owner_node[pred];
    return valid_node(owner) && owner != pred && valid_token(hir_token_pos[owner]);
}

bool valid_impl_predicate(uint pred)
{
    if (!valid_node(pred) || predicate_status[pred] != PREDICATE_STATUS_OK)
        return false;
    return predicate_owner_node[pred] == pred &&
           predicate_bound_decl_id[pred] != INVALID &&
           predicate_arg_type_code(predicate_subject_token[pred]) != TY_UNKNOWN;
}

bool valid_method_contract(uint node)
{
    return valid_node(node) &&
           valid_node(predicate_method_contract_owner_hir[node]) &&
           predicate_method_contract_name_id[node] != INVALID;
}

bool valid_method_param(uint node)
{
    if (!valid_node(node))
        return false;
    uint4 record = hir_param_record[node];
    return record.w == node &&
           valid_method_contract(record.x) &&
           record.y != INVALID;
}

uint owner_key_lane(uint pred, uint lane)
{
    if (!valid_owner_predicate(pred))
        return 0u;
    return lane == 0u
        ? encoded_nullable(hir_token_pos[predicate_owner_node[pred]], INVALID)
        : encoded_nullable(pred, INVALID);
}

uint impl_key_lane(uint pred, uint lane)
{
    if (!valid_impl_predicate(pred))
        return 0u;
    if (lane == 0u)
        return encoded_nullable(predicate_bound_decl_id[pred], INVALID);
    if (lane == 1u)
        return encoded_nullable(predicate_arg_type_code(predicate_subject_token[pred]), TY_UNKNOWN);
    if (lane == 2u)
        return predicate_bound_arg_count[pred] + 1u;
    if (lane == 3u)
        return encoded_nullable(
            predicate_arg_type_code(predicate_bound_first_arg_token[pred]),
            TY_UNKNOWN);
    return encoded_nullable(
        predicate_arg_type_code(predicate_bound_second_arg_token[pred]),
        TY_UNKNOWN);
}

uint method_contract_key_lane(uint node, uint lane)
{
    if (!valid_method_contract(node))
        return 0u;
    if (lane == 0u)
        return encoded_nullable(predicate_method_contract_owner_hir[node], INVALID);
    if (lane == 1u)
        return encoded_nullable(predicate_method_contract_name_id[node], INVALID);
    return encoded_nullable(node, INVALID);
}

uint method_param_key_lane(uint node, uint lane)
{
    if (!valid_method_param(node))
        return 0u;
    uint4 record = hir_param_record[node];
    if (lane == 0u)
        return encoded_nullable(record.x, INVALID);
    if (lane == 1u)
        return encoded_nullable(record.y, INVALID);
    return encoded_nullable(node, INVALID);
}

uint key_lane_count()
{
    if (gParams.mode == PREDICATE_KEY_MODE_OWNER)
        return 2u;
    if (gParams.mode == PREDICATE_KEY_MODE_IMPL)
        return 5u;
    return 3u;
}

uint key_lane(uint row, uint lane)
{
    if (gParams.mode == PREDICATE_KEY_MODE_OWNER)
        return owner_key_lane(row, lane);
    if (gParams.mode == PREDICATE_KEY_MODE_IMPL)
        return impl_key_lane(row, lane);
    if (gParams.mode == PREDICATE_KEY_MODE_METHOD_CONTRACT)
        return method_contract_key_lane(row, lane);
    return method_param_key_lane(row, lane);
}

bool key_less(uint left, uint right, uint active_count)
{
    bool left_padding = left >= active_count;
    bool right_padding = right >= active_count;
    if (left_padding || right_padding)
        return !left_padding && right_padding;

    uint lanes = key_lane_count();
    for (uint lane = 0u; lane < lanes; lane += 1u)
    {
        uint left_value = key_lane(left, lane);
        uint right_value = key_lane(right, lane);
        if (left_value != right_value)
            return left_value < right_value;
    }
    return left < right;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 gid: SV_GroupID, uint3 ltid: SV_GroupThreadID)
{
    // The existing active-HIR grid can contain multiple workgroups. Exactly
    // one group owns this cooperative table-wide operation.
    if (gid.x != 0u || gid.y != 0u || gid.z != 0u)
        return;

    uint lane = ltid.x;
    uint active_count = active_predicate_count();
    if (active_count > SMALL_KEY_SORT_CAPACITY ||
        gParams.predicate_capacity > SMALL_KEY_SORT_CAPACITY)
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
                    ? key_less(right, left, active_count)
                    : key_less(left, right, active_count);
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
        predicate_key_order[i] = shared_order[i];
}
