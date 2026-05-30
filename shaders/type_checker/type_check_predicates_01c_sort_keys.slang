// GPU predicate-key radix histogram.
//
// Scheduling contract:
// - Dispatch after predicate key order seeding or the previous stable scatter.
// - mode 0 sorts callable bounds by owning function token.
// - mode 1 sorts trait impl rows by (trait decl, subject type, arg count,
//   arg0 type, arg1 type).
// - mode 2 sorts trait/impl method contract rows by (owner node, method name,
//   method node), so validators can range-query by owner/name.
// - This pass only counts radix buckets; it does not solve obligations,
//   inspect source bytes, or impose fixed per-owner/per-trait limits.

import gpu_index;
import radix;

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
StructuredBuffer<uint> predicate_method_contract_owner_node;
StructuredBuffer<uint> predicate_method_contract_name_id;
StructuredBuffer<uint> predicate_key_order_in;

RWStructuredBuffer<uint> radix_block_histogram;

static const uint INVALID = 0xffffffffu;
static const uint PREDICATE_KEY_MODE_OWNER = 0u;
static const uint PREDICATE_KEY_MODE_IMPL = 1u;
static const uint PREDICATE_KEY_MODE_METHOD_CONTRACT = 2u;
static const uint PREDICATE_STATUS_OK = 0u;
static const uint PREDICATE_ARG_TYPE_CODE_BIT = 0x80000000u;
static const uint TYPE_REF_SCALAR = 1u;
static const uint TYPE_REF_GENERIC_PARAM = 2u;
static const uint TY_UNKNOWN = 0u;
static const uint TY_GENERIC_BASE = 8192u;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;
static const uint RADIX_BUCKETS = RADIX_U8_SENTINEL_BUCKETS;

uint linear_group_id(uint3 gid)
{
    return linear_group_id_2d(gid, MAX_GROUPS_X);
}

uint active_predicate_capacity()
{
    return min(predicate_count_in[0], gParams.predicate_capacity);
}

bool valid_token(uint token)
{
    return token < gParams.token_capacity;
}

bool valid_node(uint node)
{
    return node < gParams.predicate_capacity;
}

uint encode_key_value(uint value, uint invalid)
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

uint visible_type_for_token(uint token)
{
    return valid_token(token) ? visible_type[token] : TY_UNKNOWN;
}

uint type_code_for_type_token(uint token)
{
    if (!valid_token(token))
        return TY_UNKNOWN;
    uint ty = type_code_for_ref(type_expr_ref_tag[token], type_expr_ref_payload[token]);
    if (ty != TY_UNKNOWN)
        return ty;
    return visible_type_for_token(token);
}

bool predicate_arg_is_encoded_type(uint arg)
{
    return arg != INVALID && (arg & PREDICATE_ARG_TYPE_CODE_BIT) != 0u;
}

uint predicate_arg_type_code(uint arg)
{
    if (predicate_arg_is_encoded_type(arg))
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
           type_code_for_type_token(predicate_subject_token[pred]) != TY_UNKNOWN;
}

bool valid_method_contract(uint node)
{
    if (!valid_node(node))
        return false;
    return valid_node(predicate_method_contract_owner_node[node]) &&
           predicate_method_contract_name_id[node] != INVALID;
}

uint owner_key_field(uint pred, uint field_i)
{
    if (!valid_owner_predicate(pred))
        return 0u;
    if (field_i == 0u)
        return encode_key_value(pred, INVALID);
    return encode_key_value(hir_token_pos[predicate_owner_node[pred]], INVALID);
}

uint impl_key_lane(uint pred, uint lane)
{
    if (!valid_impl_predicate(pred))
        return 0u;

    if (lane == 0u)
        return encode_key_value(predicate_bound_decl_id[pred], INVALID);
    if (lane == 1u)
        return encode_key_value(
            type_code_for_type_token(predicate_subject_token[pred]),
            TY_UNKNOWN);
    if (lane == 2u)
        return predicate_bound_arg_count[pred] + 1u;
    if (lane == 3u)
        return encode_key_value(
            predicate_arg_type_code(predicate_bound_first_arg_token[pred]),
            TY_UNKNOWN);
    return encode_key_value(
        predicate_arg_type_code(predicate_bound_second_arg_token[pred]),
        TY_UNKNOWN);
}

uint impl_key_field(uint pred, uint field_i)
{
    if (field_i == 0u)
        return impl_key_lane(pred, 4u);
    if (field_i == 1u)
        return impl_key_lane(pred, 3u);
    if (field_i == 2u)
        return impl_key_lane(pred, 2u);
    if (field_i == 3u)
        return impl_key_lane(pred, 1u);
    return impl_key_lane(pred, 0u);
}

uint method_contract_key_lane(uint node, uint lane)
{
    if (!valid_method_contract(node))
        return 0u;

    if (lane == 0u)
        return encode_key_value(predicate_method_contract_owner_node[node], INVALID);
    if (lane == 1u)
        return encode_key_value(predicate_method_contract_name_id[node], INVALID);
    return encode_key_value(node, INVALID);
}

uint method_contract_key_field(uint node, uint field_i)
{
    if (field_i == 0u)
        return method_contract_key_lane(node, 2u);
    if (field_i == 1u)
        return method_contract_key_lane(node, 1u);
    return method_contract_key_lane(node, 0u);
}

uint predicate_key_field(uint pred, uint field_i)
{
    if (gParams.mode == PREDICATE_KEY_MODE_METHOD_CONTRACT)
        return method_contract_key_field(pred, field_i);
    return gParams.mode == PREDICATE_KEY_MODE_IMPL
        ? impl_key_field(pred, field_i)
        : owner_key_field(pred, field_i);
}

uint predicate_key_radix_key(uint pred, uint key_step)
{
    uint field_count = gParams.mode == PREDICATE_KEY_MODE_METHOD_CONTRACT
        ? 3u
        : (gParams.mode == PREDICATE_KEY_MODE_IMPL ? 5u : 2u);
    uint field_i = radix_field_index(key_step, field_count);
    return radix_byte_key(predicate_key_field(pred, field_i), key_step);
}

public struct PredicateKeyRadixSource : IRadixU8KeySource
{
    public static uint active_count()
    {
        return active_predicate_capacity();
    }

    public static uint ordered_row(uint order_i)
    {
        return predicate_key_order_in[order_i];
    }

    public static uint radix_key(uint row, uint key_step)
    {
        return predicate_key_radix_key(row, key_step);
    }
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 gid: SV_GroupID, uint3 ltid: SV_GroupThreadID)
{
    uint block_idx = linear_group_id(gid);
    uint lane = ltid.x;
    radix_u8_histogram_block<PredicateKeyRadixSource>(
        block_idx,
        lane,
        gParams.n_blocks,
        gParams.key_step,
        WG_SIZE,
        RADIX_BUCKETS,
        radix_block_histogram);
}
