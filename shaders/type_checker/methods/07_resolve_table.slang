// GPU sorted method-table resolver.
//
// Scheduling contract:
// - Dispatch after method-call keys are marked and method declaration keys are
//   sorted/validated.
// - This pass binary-searches sorted_method_key_order using
//   (receiver type-ref tag/payload, receiver type-argument row count/hash,
//   method name id, module id) and writes the resolved function token plus
//   return type metadata. Cross-module visibility uses an equal range over the
//   receiver/name prefix and verifies compact receiver argument rows inside the
//   candidate range.
// - It does not inspect source bytes, hash token text, compare names by
//   spelling, perform CPU lookup, or use a direct method hash table.

import fixed.key;
import gpu_index;
import range_query;

struct Params
{
    uint n_tokens;
    uint source_len;
    uint n_hir_nodes;
};

ConstantBuffer<Params> gParams;

StructuredBuffer<uint> token_count;
StructuredBuffer<uint> method_call_receiver_ref_tag;
StructuredBuffer<uint> method_call_receiver_ref_payload;
StructuredBuffer<uint> method_call_name_id;
StructuredBuffer<uint> method_call_site_module_id;
StructuredBuffer<uint> name_id_by_token;
StructuredBuffer<uint> module_count_out;
StructuredBuffer<uint> sorted_method_key_order;
StructuredBuffer<uint> method_key_status;
StructuredBuffer<uint> method_decl_receiver_ref_tag;
StructuredBuffer<uint> method_decl_receiver_ref_payload;
StructuredBuffer<uint> method_decl_module_id;
StructuredBuffer<uint> method_decl_name_id;
StructuredBuffer<uint> module_type_path_type;
StructuredBuffer<uint> fn_return_ref_tag;
StructuredBuffer<uint> fn_return_ref_payload;
StructuredBuffer<uint> type_instance_decl_token;
StructuredBuffer<uint> type_instance_arg_start;
StructuredBuffer<uint> type_instance_arg_count;
StructuredBuffer<uint> type_instance_arg_ref_tag;
StructuredBuffer<uint> type_instance_arg_ref_payload;
StructuredBuffer<uint> type_instance_arg_hash;
StructuredBuffer<uint> type_instance_arg_row_start;
StructuredBuffer<uint> type_instance_arg_row_count_out;
StructuredBuffer<uint> type_instance_arg_row_ref_tag;
StructuredBuffer<uint> type_instance_arg_row_ref_payload;
StructuredBuffer<uint> type_generic_param_slot_by_token;

RWStructuredBuffer<uint> call_fn_index;
RWStructuredBuffer<uint> call_return_type;
RWStructuredBuffer<uint> call_return_type_token;
static const uint INVALID = 0xffffffffu;
static const uint TYPE_REF_INVALID = 0u;
static const uint TYPE_REF_SCALAR = 1u;
static const uint TYPE_REF_GENERIC_PARAM = 2u;
static const uint TYPE_REF_INSTANCE = 3u;
static const uint TY_STRUCT_BASE = 4096u;
static const uint TY_ENUM_BASE = 6144u;
static const uint TY_GENERIC_BASE = 8192u;
static const uint TYPE_INSTANCE_ARG_REF_STRIDE = 4u;
static const uint METHOD_KEY_STATUS_PRIVATE_OK = 0u;
static const uint METHOD_KEY_STATUS_PUBLIC_OK = 5u;
static const uint TY_UNKNOWN = 0u;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

uint linear_thread_id(uint3 dtid)
{
    return linear_thread_id_2d(dtid, MAX_GROUPS_X, WG_SIZE);
}

uint active_token_count()
{
    return min(token_count[0], gParams.n_tokens);
}

uint active_module_count()
{
    return max(1u, min(module_count_out[0], gParams.n_hir_nodes));
}

uint decl_token_from_type_code(uint ty)
{
    if (ty >= TY_STRUCT_BASE && ty < TY_ENUM_BASE)
        return ty - TY_STRUCT_BASE;
    if (ty >= TY_ENUM_BASE && ty < TY_GENERIC_BASE)
        return ty - TY_ENUM_BASE;
    return INVALID;
}

uint resolved_nominal_decl_token(uint token_i)
{
    if (token_i >= active_token_count())
        return INVALID;
    return decl_token_from_type_code(module_type_path_type[token_i]);
}

uint type_ref_payload_key(uint receiver_tag, uint receiver_payload)
{
    if (receiver_tag == TYPE_REF_GENERIC_PARAM)
        return INVALID;

    if (receiver_tag == TYPE_REF_INSTANCE && receiver_payload < active_token_count())
    {
        uint decl_token = type_instance_decl_token[receiver_payload];
        if (decl_token != INVALID)
            return decl_token;
        decl_token = resolved_nominal_decl_token(receiver_payload);
        if (decl_token != INVALID)
            return decl_token;
    }
    return receiver_payload;
}

uint receiver_payload_key(uint receiver_tag, uint receiver_payload)
{
    return type_ref_payload_key(receiver_tag, receiver_payload);
}

uint receiver_arg_count(uint receiver_tag, uint receiver_payload)
{
    if (receiver_tag != TYPE_REF_INSTANCE || receiver_payload >= active_token_count())
        return 0u;
    return type_instance_arg_count[receiver_payload];
}

bool receiver_instance_resolved(uint receiver_tag, uint receiver_payload)
{
    if (receiver_tag != TYPE_REF_INSTANCE)
        return receiver_tag == TYPE_REF_SCALAR && receiver_payload != INVALID;
    if (receiver_payload >= active_token_count())
        return false;
    return type_instance_decl_token[receiver_payload] != INVALID;
}

uint receiver_arg_ref_index(uint receiver_tag, uint receiver_payload, uint slot)
{
    if (receiver_tag != TYPE_REF_INSTANCE || receiver_payload >= active_token_count())
        return INVALID;
    if (slot >= receiver_arg_count(receiver_tag, receiver_payload))
        return INVALID;
    uint start = type_instance_arg_start[receiver_payload];
    return start == INVALID ? INVALID : start + slot;
}

uint receiver_arg_row_ref_index(uint receiver_payload, uint ordinal)
{
    uint start = type_instance_arg_row_start[receiver_payload];
    uint ref_i = start == INVALID ? INVALID : start + ordinal;
    return ref_i != INVALID && ref_i < type_instance_arg_row_count_out[0u]
        ? ref_i
        : INVALID;
}

bool receiver_arg_ref(uint receiver_tag, uint receiver_payload, uint ordinal, out uint tag, out uint payload)
{
    tag = TYPE_REF_INVALID;
    payload = INVALID;
    if (receiver_tag != TYPE_REF_INSTANCE || receiver_payload >= active_token_count() ||
        ordinal >= type_instance_arg_count[receiver_payload])
        return false;

    uint row_ref_i = receiver_arg_row_ref_index(receiver_payload, ordinal);
    if (row_ref_i != INVALID)
    {
        tag = type_instance_arg_row_ref_tag[row_ref_i];
        payload = type_instance_arg_row_ref_payload[row_ref_i];
        if (tag != TYPE_REF_INVALID)
            return true;
    }

    if (ordinal >= TYPE_INSTANCE_ARG_REF_STRIDE)
        return false;

    uint arg_i = receiver_arg_ref_index(receiver_tag, receiver_payload, ordinal);
    if (arg_i == INVALID)
        return false;

    tag = type_instance_arg_ref_tag[arg_i];
    payload = type_instance_arg_ref_payload[arg_i];
    return tag != TYPE_REF_INVALID;
}

uint type_code_for_ref(uint tag, uint payload)
{
    if (tag == TYPE_REF_SCALAR)
        return payload;
    if (tag == TYPE_REF_INSTANCE && payload < active_token_count())
    {
        uint decl_token = type_instance_decl_token[payload];
        if (decl_token != INVALID && decl_token < active_token_count())
        {
            uint ty = module_type_path_type[payload];
            if (ty != TY_UNKNOWN)
                return ty;
            ty = module_type_path_type[decl_token];
            if (ty != TY_UNKNOWN)
                return ty;
            return TY_STRUCT_BASE + decl_token;
        }
    }
    return TY_UNKNOWN;
}

uint generic_param_slot_for_payload(uint payload)
{
    return payload < active_token_count() ? type_generic_param_slot_by_token[payload] : payload;
}

uint generic_param_name_for_payload(uint payload)
{
    return payload < active_token_count() ? name_id_by_token[payload] : INVALID;
}

bool same_generic_param_payload(uint left_payload, uint right_payload)
{
    uint left_slot = generic_param_slot_for_payload(left_payload);
    uint right_slot = generic_param_slot_for_payload(right_payload);
    if (left_slot != INVALID && right_slot != INVALID)
        return left_slot == right_slot;

    uint left_name = generic_param_name_for_payload(left_payload);
    uint right_name = generic_param_name_for_payload(right_payload);
    return left_name != INVALID && left_name == right_name;
}

bool same_receiver_projection_arg(
    uint ret_arg_tag,
    uint ret_arg_payload,
    uint decl_arg_tag,
    uint decl_arg_payload)
{
    if (ret_arg_tag != decl_arg_tag)
        return false;
    if (ret_arg_tag == TYPE_REF_GENERIC_PARAM)
        return same_generic_param_payload(ret_arg_payload, decl_arg_payload);
    if (ret_arg_tag == TYPE_REF_SCALAR)
        return ret_arg_payload == decl_arg_payload;
    return false;
}

bool return_instance_is_receiver_projection(
    uint receiver_tag,
    uint receiver_payload,
    uint fn_i,
    uint ret_payload)
{
    if (receiver_tag != TYPE_REF_INSTANCE ||
        receiver_payload >= active_token_count() ||
        fn_i >= active_token_count() ||
        ret_payload >= active_token_count())
    {
        return false;
    }

    uint decl_receiver_tag = method_decl_receiver_ref_tag[fn_i];
    uint decl_receiver_payload = method_decl_receiver_ref_payload[fn_i];
    if (decl_receiver_tag != TYPE_REF_INSTANCE || decl_receiver_payload >= active_token_count())
        return false;

    if (receiver_payload_key(decl_receiver_tag, decl_receiver_payload) !=
        receiver_payload_key(TYPE_REF_INSTANCE, ret_payload))
    {
        return false;
    }

    uint decl_arg_count = receiver_arg_count(decl_receiver_tag, decl_receiver_payload);
    if (receiver_arg_count(TYPE_REF_INSTANCE, ret_payload) != decl_arg_count ||
        receiver_arg_count(receiver_tag, receiver_payload) != decl_arg_count)
    {
        return false;
    }

    for (uint slot_i = 0u; slot_i < decl_arg_count; slot_i += 1u)
    {
        uint ret_arg_tag;
        uint ret_arg_payload;
        uint decl_arg_tag;
        uint decl_arg_payload;
        if (!receiver_arg_ref(
                TYPE_REF_INSTANCE,
                ret_payload,
                slot_i,
                ret_arg_tag,
                ret_arg_payload) ||
            !receiver_arg_ref(
                decl_receiver_tag,
                decl_receiver_payload,
                slot_i,
                decl_arg_tag,
                decl_arg_payload) ||
            !same_receiver_projection_arg(
                ret_arg_tag,
                ret_arg_payload,
                decl_arg_tag,
                decl_arg_payload))
        {
            return false;
        }
    }

    return true;
}

bool return_instance_is_call_receiver_slot_projection(
    uint receiver_tag,
    uint receiver_payload,
    uint ret_payload)
{
    if (receiver_tag != TYPE_REF_INSTANCE ||
        receiver_payload >= active_token_count() ||
        ret_payload >= active_token_count())
    {
        return false;
    }

    if (receiver_payload_key(receiver_tag, receiver_payload) !=
        receiver_payload_key(TYPE_REF_INSTANCE, ret_payload))
    {
        return false;
    }

    uint arg_count = receiver_arg_count(receiver_tag, receiver_payload);
    if (arg_count == 0u || receiver_arg_count(TYPE_REF_INSTANCE, ret_payload) != arg_count)
        return false;

    for (uint slot_i = 0u; slot_i < arg_count; slot_i += 1u)
    {
        uint ret_arg_tag;
        uint ret_arg_payload;
        if (!receiver_arg_ref(
                TYPE_REF_INSTANCE,
                ret_payload,
                slot_i,
                ret_arg_tag,
                ret_arg_payload) ||
            ret_arg_tag != TYPE_REF_GENERIC_PARAM ||
            generic_param_slot_for_payload(ret_arg_payload) != slot_i)
        {
            return false;
        }
    }

    return true;
}

bool return_instance_projects_to_call_receiver(
    uint receiver_tag,
    uint receiver_payload,
    uint fn_i,
    uint ret_payload)
{
    return return_instance_is_receiver_projection(receiver_tag, receiver_payload, fn_i, ret_payload) ||
           return_instance_is_call_receiver_slot_projection(receiver_tag, receiver_payload, ret_payload);
}

bool substituted_receiver_return_type_slot(
    uint receiver_tag,
    uint receiver_payload,
    uint decl_receiver_tag,
    uint decl_receiver_payload,
    uint decl_arg_count,
    uint ret_payload,
    uint fallback_ty,
    uint slot,
    out uint ty)
{
    ty = TY_UNKNOWN;
    if (slot >= decl_arg_count)
        return false;

    uint decl_arg_tag;
    uint decl_arg_payload;
    if (!receiver_arg_ref(
            decl_receiver_tag,
            decl_receiver_payload,
            slot,
            decl_arg_tag,
            decl_arg_payload))
        return false;
    if (decl_arg_tag != TYPE_REF_GENERIC_PARAM)
        return false;

    if (!same_generic_param_payload(decl_arg_payload, ret_payload))
        return false;

    uint call_arg_tag;
    uint call_arg_payload;
    if (!receiver_arg_ref(receiver_tag, receiver_payload, slot, call_arg_tag, call_arg_payload))
    {
        ty = fallback_ty;
        return true;
    }

    uint resolved_ty = type_code_for_ref(call_arg_tag, call_arg_payload);
    ty = resolved_ty == TY_UNKNOWN ? fallback_ty : resolved_ty;
    return true;
}

uint substituted_receiver_return_type(
    uint receiver_tag,
    uint receiver_payload,
    uint fn_i,
    uint fallback_ty)
{
    if (fn_i < active_token_count())
    {
        uint ret_tag = fn_return_ref_tag[fn_i];
        uint ret_payload = fn_return_ref_payload[fn_i];
        if (ret_tag == TYPE_REF_INSTANCE &&
            return_instance_projects_to_call_receiver(
                receiver_tag,
                receiver_payload,
                fn_i,
                ret_payload))
        {
            uint ty = type_code_for_ref(receiver_tag, receiver_payload);
            if (ty != TY_UNKNOWN)
                return ty;
        }

        if (ret_tag == TYPE_REF_GENERIC_PARAM && ret_payload != INVALID)
        {
            uint decl_receiver_tag = method_decl_receiver_ref_tag[fn_i];
            uint decl_receiver_payload = method_decl_receiver_ref_payload[fn_i];
            uint decl_arg_count = receiver_arg_count(decl_receiver_tag, decl_receiver_payload);
            uint ty = TY_UNKNOWN;
            for (uint slot_i = 0u; slot_i < decl_arg_count; slot_i += 1u)
            {
                if (substituted_receiver_return_type_slot(
                        receiver_tag, receiver_payload, decl_receiver_tag, decl_receiver_payload,
                        decl_arg_count, ret_payload, fallback_ty, slot_i, ty))
                    return ty;
            }
        }
    }

    if (fallback_ty < TY_GENERIC_BASE)
        return fallback_ty;

    uint slot = fallback_ty - TY_GENERIC_BASE;
    uint arg_tag;
    uint arg_payload;
    if (!receiver_arg_ref(receiver_tag, receiver_payload, slot, arg_tag, arg_payload))
        return fallback_ty;

    uint ty = type_code_for_ref(arg_tag, arg_payload);
    return ty == TY_UNKNOWN ? fallback_ty : ty;
}

uint substituted_receiver_return_token(
    uint receiver_tag,
    uint receiver_payload,
    uint fn_i,
    uint fallback_token)
{
    if (fn_i >= active_token_count())
        return fallback_token;

    uint ret_tag = fn_return_ref_tag[fn_i];
    uint ret_payload = fn_return_ref_payload[fn_i];
    if (ret_tag == TYPE_REF_INSTANCE &&
        return_instance_projects_to_call_receiver(receiver_tag, receiver_payload, fn_i, ret_payload))
    {
        return receiver_payload;
    }

    return fallback_token;
}

uint receiver_arg_ref_tag_key(uint receiver_tag, uint receiver_payload, uint slot)
{
    uint tag;
    uint payload;
    return receiver_arg_ref(receiver_tag, receiver_payload, slot, tag, payload)
        ? tag
        : TYPE_REF_INVALID;
}

uint receiver_arg_ref_payload_key(uint receiver_tag, uint receiver_payload, uint slot)
{
    uint tag;
    uint payload;
    if (!receiver_arg_ref(receiver_tag, receiver_payload, slot, tag, payload))
        return INVALID;
    return type_ref_payload_key(tag, payload);
}

public struct MethodLookupKey
{
    uint module_id;
    uint receiver_tag;
    uint receiver_payload;
    uint receiver_arg_hash;
    uint name_id;
    uint generic_receiver_args;
}

uint mix_hash(uint hash, uint value)
{
    hash ^= value;
    hash *= 16777619u;
    hash ^= hash >> 16u;
    return hash;
}

uint encoded_hash_value(uint value, uint invalid)
{
    return value == invalid ? 0u : value + 1u;
}

uint generic_receiver_arg_hash(uint count)
{
    uint hash = mix_hash(2166136261u, count);
    for (uint ordinal = 0u; ordinal < count; ordinal += 1u)
    {
        hash = mix_hash(hash, encoded_hash_value(TYPE_REF_GENERIC_PARAM, TYPE_REF_INVALID));
        hash = mix_hash(hash, 0u);
    }
    return hash;
}

uint receiver_arg_hash_key(uint receiver_tag, uint receiver_payload, uint generic_receiver_args)
{
    uint count = receiver_arg_count(receiver_tag, receiver_payload);
    if (generic_receiver_args != 0u && count != 0u)
        return generic_receiver_arg_hash(count);
    if (receiver_tag != TYPE_REF_INSTANCE || receiver_payload >= active_token_count())
        return 0u;
    return type_instance_arg_hash[receiver_payload];
}

public struct MethodFixedKey : IFixedU32RowKey<MethodLookupKey>
{
    public static uint row_lane(uint row, uint lane)
    {
        uint active_tokens = active_token_count();
        uint fn_i = row < active_tokens ? sorted_method_key_order[row] : INVALID;
        if (fn_i >= active_tokens)
            return 0u;
        if (lane == 0u)
            return fixed_key_encode_nullable_u32(
                method_decl_receiver_ref_tag[fn_i],
                TYPE_REF_INVALID);
        if (lane == 1u)
            return fixed_key_encode_nullable_u32(
                receiver_payload_key(
                    method_decl_receiver_ref_tag[fn_i],
                    method_decl_receiver_ref_payload[fn_i]),
                INVALID);
        if (lane == 2u)
            return receiver_arg_count(
                method_decl_receiver_ref_tag[fn_i],
                method_decl_receiver_ref_payload[fn_i]) + 1u;
        if (lane == 3u)
            return receiver_arg_hash_key(
                method_decl_receiver_ref_tag[fn_i],
                method_decl_receiver_ref_payload[fn_i],
                0u);
        if (lane == 4u)
            return fixed_key_encode_nullable_u32(method_decl_name_id[fn_i], INVALID);
        return fixed_key_encode_nullable_u32(method_decl_module_id[fn_i], INVALID);
    }

    public static uint key_lane(MethodLookupKey key, uint lane)
    {
        if (lane == 0u)
            return fixed_key_encode_nullable_u32(key.receiver_tag, TYPE_REF_INVALID);
        if (lane == 1u)
            return fixed_key_encode_nullable_u32(
                receiver_payload_key(key.receiver_tag, key.receiver_payload),
                INVALID);
        if (lane == 2u)
            return receiver_arg_count(key.receiver_tag, key.receiver_payload) + 1u;
        if (lane == 3u)
            return key.receiver_arg_hash;
        if (lane == 4u)
            return fixed_key_encode_nullable_u32(key.name_id, INVALID);
        return fixed_key_encode_nullable_u32(key.module_id, INVALID);
    }
}

public struct MethodKeyCompare : IRowQueryCompare<MethodLookupKey>
{
    public static int compare(uint row, MethodLookupKey key)
    {
        return fixed_u32_row_key_compare<MethodLookupKey, MethodFixedKey>(
            row,
            key,
            6u);
    }
}

public struct MethodPrefixCompare : IRowQueryCompare<MethodLookupKey>
{
    public static int compare(uint row, MethodLookupKey key)
    {
        return fixed_u32_row_key_compare<MethodLookupKey, MethodFixedKey>(
            row,
            key,
            3u);
    }
}

bool method_key_identity_matches(uint fn_i, MethodLookupKey key)
{
    if (fn_i >= active_token_count())
        return false;
    if (method_decl_name_id[fn_i] != key.name_id)
        return false;
    return key.module_id == INVALID || method_decl_module_id[fn_i] == key.module_id;
}

bool same_receiver_arg_ref(uint left_tag, uint left_payload, uint right_tag, uint right_payload)
{
    if (left_tag != right_tag)
        return false;
    return type_ref_payload_key(left_tag, left_payload) ==
           type_ref_payload_key(right_tag, right_payload);
}

bool method_receiver_args_match(uint fn_i, MethodLookupKey key)
{
    uint decl_tag = method_decl_receiver_ref_tag[fn_i];
    uint decl_payload = method_decl_receiver_ref_payload[fn_i];
    if (decl_tag != key.receiver_tag)
        return false;
    if (receiver_payload_key(decl_tag, decl_payload) !=
        receiver_payload_key(key.receiver_tag, key.receiver_payload))
        return false;

    uint count = receiver_arg_count(key.receiver_tag, key.receiver_payload);
    if (receiver_arg_count(decl_tag, decl_payload) != count)
        return false;

    for (uint ordinal = 0u; ordinal < count; ordinal += 1u)
    {
        uint decl_arg_tag;
        uint decl_arg_payload;
        if (!receiver_arg_ref(decl_tag, decl_payload, ordinal, decl_arg_tag, decl_arg_payload))
            return false;

        if (key.generic_receiver_args != 0u)
        {
            if (decl_arg_tag != TYPE_REF_GENERIC_PARAM)
                return false;
            continue;
        }

        uint call_arg_tag;
        uint call_arg_payload;
        if (!receiver_arg_ref(
                key.receiver_tag,
                key.receiver_payload,
                ordinal,
                call_arg_tag,
                call_arg_payload) ||
            !same_receiver_arg_ref(
                decl_arg_tag,
                decl_arg_payload,
                call_arg_tag,
                call_arg_payload))
            return false;
    }

    return true;
}

bool method_status_resolvable(uint fn_i)
{
    if (fn_i >= active_token_count())
        return false;
    uint status = method_key_status[fn_i];
    return status == METHOD_KEY_STATUS_PUBLIC_OK || status == METHOD_KEY_STATUS_PRIVATE_OK;
}

uint matching_method_in_range(QueryRange range, MethodLookupKey key)
{
    if (range.end > active_token_count() || range.end < range.begin)
        return INVALID;

    uint found_fn_i = INVALID;
    for (uint row = range.begin; row < range.end; row += 1u)
    {
        uint fn_i = sorted_method_key_order[row];
        if (!method_status_resolvable(fn_i) ||
            !method_key_identity_matches(fn_i, key) ||
            !method_receiver_args_match(fn_i, key))
            continue;
        if (found_fn_i != INVALID)
            return INVALID;
        found_fn_i = fn_i;
    }
    return found_fn_i;
}

uint find_method(uint module_id, uint receiver_tag, uint receiver_payload, uint name_id)
{
    if (module_id == INVALID || receiver_tag == TYPE_REF_INVALID || receiver_payload == INVALID ||
        name_id == INVALID)
        return INVALID;
    if (!receiver_instance_resolved(receiver_tag, receiver_payload))
        return INVALID;

    MethodLookupKey key;
    key.module_id = module_id;
    key.receiver_tag = receiver_tag;
    key.receiver_payload = receiver_payload;
    key.receiver_arg_hash = receiver_arg_hash_key(receiver_tag, receiver_payload, 0u);
    key.name_id = name_id;
    key.generic_receiver_args = 0u;

    QueryRange exact_range = equal_range_query<MethodLookupKey, MethodPrefixCompare>(
        active_token_count(),
        key);
    uint exact_fn_i = matching_method_in_range(exact_range, key);
    uint generic_fn_i = INVALID;
    if (receiver_arg_count(receiver_tag, receiver_payload) != 0u)
    {
        key.generic_receiver_args = 1u;
        key.receiver_arg_hash = receiver_arg_hash_key(receiver_tag, receiver_payload, 1u);
        QueryRange generic_range = equal_range_query<MethodLookupKey, MethodPrefixCompare>(
            active_token_count(),
            key);
        generic_fn_i = matching_method_in_range(generic_range, key);
    }

    // Specialization is not a proven relation yet; overlapping exact/generic
    // receiver keys must fail closed instead of picking one method locally.
    if (exact_fn_i != INVALID && generic_fn_i != INVALID)
        return INVALID;

    return exact_fn_i != INVALID ? exact_fn_i : generic_fn_i;
}

bool unique_visible_method_in_range(
    uint method_i,
    QueryRange range,
    MethodLookupKey key,
    out uint visible_fn_i)
{
    visible_fn_i = INVALID;
    if (range.end > active_token_count() || range.end < range.begin)
        return false;

    for (uint row = range.begin; row < range.end; row += 1u)
    {
        uint fn_i = sorted_method_key_order[row];
        uint candidate = method_key_identity_matches(fn_i, key) &&
                         method_receiver_args_match(fn_i, key)
            ? visibility_checked_method(method_i, fn_i)
            : INVALID;
        if (candidate == INVALID)
            continue;
        if (visible_fn_i != INVALID)
            return false;
        visible_fn_i = candidate;
    }
    return true;
}

uint find_visible_method_for_receiver(uint method_i, uint receiver_tag, uint receiver_payload, uint name_id)
{
    if (!receiver_instance_resolved(receiver_tag, receiver_payload))
        return INVALID;

    uint call_site_module = method_i < active_token_count() ? method_call_site_module_id[method_i]
                                                            : INVALID;
    uint local_fn_i = visibility_checked_method(
        method_i,
        find_method(call_site_module, receiver_tag, receiver_payload, name_id));
    if (local_fn_i != INVALID)
        return local_fn_i;

    uint exact_fn_i = INVALID;
    MethodLookupKey key;
    key.module_id = INVALID;
    key.receiver_tag = receiver_tag;
    key.receiver_payload = receiver_payload;
    key.receiver_arg_hash = receiver_arg_hash_key(receiver_tag, receiver_payload, 0u);
    key.name_id = name_id;
    key.generic_receiver_args = 0u;
    QueryRange range = equal_range_query<MethodLookupKey, MethodPrefixCompare>(
        active_token_count(),
        key);
    if (!unique_visible_method_in_range(method_i, range, key, exact_fn_i))
        return INVALID;

    if (receiver_arg_count(receiver_tag, receiver_payload) == 0u)
        return exact_fn_i;

    uint generic_fn_i = INVALID;
    key.generic_receiver_args = 1u;
    key.receiver_arg_hash = receiver_arg_hash_key(receiver_tag, receiver_payload, 1u);
    range = equal_range_query<MethodLookupKey, MethodPrefixCompare>(
        active_token_count(),
        key);
    if (!unique_visible_method_in_range(method_i, range, key, generic_fn_i))
        return INVALID;

    if (exact_fn_i != INVALID && generic_fn_i != INVALID)
        return INVALID;

    return exact_fn_i != INVALID ? exact_fn_i : generic_fn_i;
}

uint find_visible_method(uint method_i, uint receiver_tag, uint receiver_payload, uint name_id)
{
    uint fn_i = find_visible_method_for_receiver(method_i, receiver_tag, receiver_payload, name_id);
    if (fn_i != INVALID)
        return fn_i;

    if (receiver_tag != TYPE_REF_INSTANCE)
        return INVALID;

    uint scalar_ty = type_code_for_ref(receiver_tag, receiver_payload);
    if (scalar_ty == TY_UNKNOWN)
        return INVALID;

    return find_visible_method_for_receiver(method_i, TYPE_REF_SCALAR, scalar_ty, name_id);
}

uint visibility_checked_method(uint method_i, uint fn_i)
{
    if (fn_i >= active_token_count())
        return INVALID;

    uint status = method_key_status[fn_i];
    if (status == METHOD_KEY_STATUS_PUBLIC_OK)
        return fn_i;
    uint call_site_module = method_i < active_token_count() ? method_call_site_module_id[method_i]
                                                            : INVALID;
    uint decl_module = fn_i < active_token_count() ? method_decl_module_id[fn_i] : INVALID;
    if (status == METHOD_KEY_STATUS_PRIVATE_OK && call_site_module != INVALID &&
        call_site_module == decl_module)
        return fn_i;
    return INVALID;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint i = linear_thread_id(dtid);
    if (i >= active_token_count())
        return;

    if (method_call_name_id[i] == INVALID)
        return;

    call_fn_index[i] = INVALID;
    call_return_type[i] = TY_UNKNOWN;
    call_return_type_token[i] = INVALID;

    uint fn_i = find_visible_method(i,
                                    method_call_receiver_ref_tag[i],
                                    method_call_receiver_ref_payload[i],
                                    method_call_name_id[i]);
    if (fn_i == INVALID)
        return;

    uint ret_ty = substituted_receiver_return_type(
        method_call_receiver_ref_tag[i],
        method_call_receiver_ref_payload[i],
        fn_i,
        call_return_type[fn_i]);
    if (ret_ty == TY_UNKNOWN)
        return;
    call_fn_index[i] = fn_i;
    call_return_type[i] = ret_ty;
    call_return_type_token[i] = substituted_receiver_return_token(
        method_call_receiver_ref_tag[i],
        method_call_receiver_ref_payload[i],
        fn_i,
        call_return_type_token[fn_i]);
}
