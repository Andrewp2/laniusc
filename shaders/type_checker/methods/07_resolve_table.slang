// GPU sorted method-table resolver.
//
// Scheduling contract:
// - Dispatch after method-call keys are marked and method declaration keys are
//   sorted/validated.
// - This pass binary-searches sorted_method_key_order using
//   (receiver type-ref tag/payload, bounded receiver type-argument refs,
//   method name id, module id) and writes the resolved function token plus
//   return type metadata. Cross-module visibility uses an equal range over the
//   receiver/name prefix rather than scanning every module.
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
    return min(type_instance_arg_count[receiver_payload], TYPE_INSTANCE_ARG_REF_STRIDE);
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

uint receiver_arg_ref_tag_raw(uint receiver_tag, uint receiver_payload, uint slot)
{
    uint arg_i = receiver_arg_ref_index(receiver_tag, receiver_payload, slot);
    return arg_i == INVALID ? TYPE_REF_INVALID : type_instance_arg_ref_tag[arg_i];
}

uint receiver_arg_ref_payload_raw(uint receiver_tag, uint receiver_payload, uint slot)
{
    uint arg_i = receiver_arg_ref_index(receiver_tag, receiver_payload, slot);
    return arg_i == INVALID ? INVALID : type_instance_arg_ref_payload[arg_i];
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

    uint decl_arg_i = receiver_arg_ref_index(decl_receiver_tag, decl_receiver_payload, slot);
    if (decl_arg_i == INVALID)
        return false;
    if (type_instance_arg_ref_tag[decl_arg_i] != TYPE_REF_GENERIC_PARAM ||
        type_instance_arg_ref_payload[decl_arg_i] != ret_payload)
        return false;

    uint call_arg_i = receiver_arg_ref_index(receiver_tag, receiver_payload, slot);
    if (call_arg_i == INVALID)
    {
        ty = fallback_ty;
        return true;
    }

    uint resolved_ty = type_code_for_ref(
        type_instance_arg_ref_tag[call_arg_i],
        type_instance_arg_ref_payload[call_arg_i]);
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
        if (ret_tag == TYPE_REF_GENERIC_PARAM && ret_payload != INVALID)
        {
            uint decl_receiver_tag = method_decl_receiver_ref_tag[fn_i];
            uint decl_receiver_payload = method_decl_receiver_ref_payload[fn_i];
            uint decl_arg_count = receiver_arg_count(decl_receiver_tag, decl_receiver_payload);
            uint ty = TY_UNKNOWN;
            if (substituted_receiver_return_type_slot(
                    receiver_tag, receiver_payload, decl_receiver_tag, decl_receiver_payload,
                    decl_arg_count, ret_payload, fallback_ty, 0u, ty))
                return ty;
            if (substituted_receiver_return_type_slot(
                    receiver_tag, receiver_payload, decl_receiver_tag, decl_receiver_payload,
                    decl_arg_count, ret_payload, fallback_ty, 1u, ty))
                return ty;
            if (substituted_receiver_return_type_slot(
                    receiver_tag, receiver_payload, decl_receiver_tag, decl_receiver_payload,
                    decl_arg_count, ret_payload, fallback_ty, 2u, ty))
                return ty;
            if (substituted_receiver_return_type_slot(
                    receiver_tag, receiver_payload, decl_receiver_tag, decl_receiver_payload,
                    decl_arg_count, ret_payload, fallback_ty, 3u, ty))
                return ty;
        }
    }

    if (fallback_ty < TY_GENERIC_BASE)
        return fallback_ty;

    uint slot = fallback_ty - TY_GENERIC_BASE;
    if (slot >= TYPE_INSTANCE_ARG_REF_STRIDE)
        return fallback_ty;

    uint arg_i = receiver_arg_ref_index(receiver_tag, receiver_payload, slot);
    if (arg_i == INVALID)
        return fallback_ty;

    uint ty = type_code_for_ref(
        type_instance_arg_ref_tag[arg_i],
        type_instance_arg_ref_payload[arg_i]);
    return ty == TY_UNKNOWN ? fallback_ty : ty;
}

uint receiver_arg_ref_tag_key(uint receiver_tag, uint receiver_payload, uint slot)
{
    return receiver_arg_ref_tag_raw(receiver_tag, receiver_payload, slot);
}

uint receiver_arg_ref_payload_key(uint receiver_tag, uint receiver_payload, uint slot)
{
    uint arg_i = receiver_arg_ref_index(receiver_tag, receiver_payload, slot);
    if (arg_i == INVALID)
        return INVALID;
    return type_ref_payload_key(
        type_instance_arg_ref_tag[arg_i],
        type_instance_arg_ref_payload[arg_i]);
}

public struct MethodLookupKey
{
    uint module_id;
    uint receiver_tag;
    uint receiver_payload;
    uint name_id;
    uint generic_receiver_args;
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
            return fixed_key_encode_nullable_u32(
                receiver_arg_ref_tag_key(
                    method_decl_receiver_ref_tag[fn_i],
                    method_decl_receiver_ref_payload[fn_i],
                    0u),
                TYPE_REF_INVALID);
        if (lane == 4u)
            return fixed_key_encode_nullable_u32(
                receiver_arg_ref_payload_key(
                    method_decl_receiver_ref_tag[fn_i],
                    method_decl_receiver_ref_payload[fn_i],
                    0u),
                INVALID);
        if (lane == 5u)
            return fixed_key_encode_nullable_u32(
                receiver_arg_ref_tag_key(
                    method_decl_receiver_ref_tag[fn_i],
                    method_decl_receiver_ref_payload[fn_i],
                    1u),
                TYPE_REF_INVALID);
        if (lane == 6u)
            return fixed_key_encode_nullable_u32(
                receiver_arg_ref_payload_key(
                    method_decl_receiver_ref_tag[fn_i],
                    method_decl_receiver_ref_payload[fn_i],
                    1u),
                INVALID);
        if (lane == 7u)
            return fixed_key_encode_nullable_u32(
                receiver_arg_ref_tag_key(
                    method_decl_receiver_ref_tag[fn_i],
                    method_decl_receiver_ref_payload[fn_i],
                    2u),
                TYPE_REF_INVALID);
        if (lane == 8u)
            return fixed_key_encode_nullable_u32(
                receiver_arg_ref_payload_key(
                    method_decl_receiver_ref_tag[fn_i],
                    method_decl_receiver_ref_payload[fn_i],
                    2u),
                INVALID);
        if (lane == 9u)
            return fixed_key_encode_nullable_u32(
                receiver_arg_ref_tag_key(
                    method_decl_receiver_ref_tag[fn_i],
                    method_decl_receiver_ref_payload[fn_i],
                    3u),
                TYPE_REF_INVALID);
        if (lane == 10u)
            return fixed_key_encode_nullable_u32(
                receiver_arg_ref_payload_key(
                    method_decl_receiver_ref_tag[fn_i],
                    method_decl_receiver_ref_payload[fn_i],
                    3u),
                INVALID);
        if (lane == 11u)
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
        {
            if (key.generic_receiver_args != 0u &&
                0u < receiver_arg_count(key.receiver_tag, key.receiver_payload))
                return fixed_key_encode_nullable_u32(TYPE_REF_GENERIC_PARAM, TYPE_REF_INVALID);
            return fixed_key_encode_nullable_u32(
                receiver_arg_ref_tag_key(key.receiver_tag, key.receiver_payload, 0u),
                TYPE_REF_INVALID);
        }
        if (lane == 4u)
        {
            if (key.generic_receiver_args != 0u &&
                0u < receiver_arg_count(key.receiver_tag, key.receiver_payload))
                return fixed_key_encode_nullable_u32(INVALID, INVALID);
            return fixed_key_encode_nullable_u32(
                receiver_arg_ref_payload_key(key.receiver_tag, key.receiver_payload, 0u),
                INVALID);
        }
        if (lane == 5u)
        {
            if (key.generic_receiver_args != 0u &&
                1u < receiver_arg_count(key.receiver_tag, key.receiver_payload))
                return fixed_key_encode_nullable_u32(TYPE_REF_GENERIC_PARAM, TYPE_REF_INVALID);
            return fixed_key_encode_nullable_u32(
                receiver_arg_ref_tag_key(key.receiver_tag, key.receiver_payload, 1u),
                TYPE_REF_INVALID);
        }
        if (lane == 6u)
        {
            if (key.generic_receiver_args != 0u &&
                1u < receiver_arg_count(key.receiver_tag, key.receiver_payload))
                return fixed_key_encode_nullable_u32(INVALID, INVALID);
            return fixed_key_encode_nullable_u32(
                receiver_arg_ref_payload_key(key.receiver_tag, key.receiver_payload, 1u),
                INVALID);
        }
        if (lane == 7u)
        {
            if (key.generic_receiver_args != 0u &&
                2u < receiver_arg_count(key.receiver_tag, key.receiver_payload))
                return fixed_key_encode_nullable_u32(TYPE_REF_GENERIC_PARAM, TYPE_REF_INVALID);
            return fixed_key_encode_nullable_u32(
                receiver_arg_ref_tag_key(key.receiver_tag, key.receiver_payload, 2u),
                TYPE_REF_INVALID);
        }
        if (lane == 8u)
        {
            if (key.generic_receiver_args != 0u &&
                2u < receiver_arg_count(key.receiver_tag, key.receiver_payload))
                return fixed_key_encode_nullable_u32(INVALID, INVALID);
            return fixed_key_encode_nullable_u32(
                receiver_arg_ref_payload_key(key.receiver_tag, key.receiver_payload, 2u),
                INVALID);
        }
        if (lane == 9u)
        {
            if (key.generic_receiver_args != 0u &&
                3u < receiver_arg_count(key.receiver_tag, key.receiver_payload))
                return fixed_key_encode_nullable_u32(TYPE_REF_GENERIC_PARAM, TYPE_REF_INVALID);
            return fixed_key_encode_nullable_u32(
                receiver_arg_ref_tag_key(key.receiver_tag, key.receiver_payload, 3u),
                TYPE_REF_INVALID);
        }
        if (lane == 10u)
        {
            if (key.generic_receiver_args != 0u &&
                3u < receiver_arg_count(key.receiver_tag, key.receiver_payload))
                return fixed_key_encode_nullable_u32(INVALID, INVALID);
            return fixed_key_encode_nullable_u32(
                receiver_arg_ref_payload_key(key.receiver_tag, key.receiver_payload, 3u),
                INVALID);
        }
        if (lane == 11u)
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
            13u);
    }
}

public struct MethodPrefixCompare : IRowQueryCompare<MethodLookupKey>
{
    public static int compare(uint row, MethodLookupKey key)
    {
        return fixed_u32_row_key_compare<MethodLookupKey, MethodFixedKey>(
            row,
            key,
            12u);
    }
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
    key.name_id = name_id;
    key.generic_receiver_args = 0u;

    uint exact_row = find_equal_query<MethodLookupKey, MethodKeyCompare>(active_token_count(), key);
    uint generic_row = INVALID;
    if (receiver_arg_count(receiver_tag, receiver_payload) != 0u)
    {
        key.generic_receiver_args = 1u;
        generic_row = find_equal_query<MethodLookupKey, MethodKeyCompare>(active_token_count(), key);
    }

    // Specialization is not a proven relation yet; overlapping exact/generic
    // receiver keys must fail closed instead of picking one method locally.
    if (exact_row != INVALID && generic_row != INVALID)
        return INVALID;

    uint row = exact_row != INVALID ? exact_row : generic_row;
    if (row == INVALID)
        return INVALID;

    uint fn_i = sorted_method_key_order[row];
    if (fn_i >= active_token_count())
        return INVALID;

    uint status = method_key_status[fn_i];
    if (status == METHOD_KEY_STATUS_PUBLIC_OK || status == METHOD_KEY_STATUS_PRIVATE_OK)
        return fn_i;
    return INVALID;
}

bool unique_visible_method_in_range(uint method_i, QueryRange range, out uint visible_fn_i)
{
    visible_fn_i = INVALID;
    if (range.end > active_token_count() || range.end < range.begin)
        return false;

    uint candidate_count = range.end - range.begin;
    if (candidate_count == 0u)
        return true;
    if (candidate_count != 1u)
        return false;

    uint fn_i = sorted_method_key_order[range.begin];
    visible_fn_i = visibility_checked_method(method_i, fn_i);
    return true;
}

uint find_visible_method(uint method_i, uint receiver_tag, uint receiver_payload, uint name_id)
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
    key.name_id = name_id;
    key.generic_receiver_args = 0u;
    QueryRange range = equal_range_query<MethodLookupKey, MethodPrefixCompare>(
        active_token_count(),
        key);
    if (!unique_visible_method_in_range(method_i, range, exact_fn_i))
        return INVALID;

    if (receiver_arg_count(receiver_tag, receiver_payload) == 0u)
        return exact_fn_i;

    uint generic_fn_i = INVALID;
    key.generic_receiver_args = 1u;
    range = equal_range_query<MethodLookupKey, MethodPrefixCompare>(
        active_token_count(),
        key);
    if (!unique_visible_method_in_range(method_i, range, generic_fn_i))
        return INVALID;

    if (exact_fn_i != INVALID && generic_fn_i != INVALID)
        return INVALID;

    return exact_fn_i != INVALID ? exact_fn_i : generic_fn_i;
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
    call_return_type_token[i] = call_return_type_token[fn_i];
}
