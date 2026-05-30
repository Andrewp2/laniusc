// GPU sorted method-key validation.
//
// Scheduling contract:
// - Dispatch after the method key radix sort has produced
//   sorted_method_key_order.
// - Adjacent equal valid keys are duplicate inherent methods in the same module
//   for the same receiver type-ref, bounded receiver type-argument refs, and
//   interned method name.
// - This pass writes per-method validation results and reduces invalid or
//   duplicate method declarations into the compiler-wide type-check status. It
//   does not resolve calls, inspect source bytes, hash token text, perform CPU
//   lookup, or apply same-source shortcuts.

import fixed_key;
import sorted_runs;
import status;

struct Params
{
    uint method_capacity;
    uint reserved;
    uint n_blocks;
    uint key_step;
};

ConstantBuffer<Params> gParams;

StructuredBuffer<uint> token_count;
StructuredBuffer<uint> module_count_out;
StructuredBuffer<uint> sorted_method_key_order;
StructuredBuffer<uint> method_decl_impl_node;
StructuredBuffer<uint> method_decl_receiver_ref_tag;
StructuredBuffer<uint> method_decl_receiver_ref_payload;
StructuredBuffer<uint> method_decl_module_id;
StructuredBuffer<uint> method_decl_name_token;
StructuredBuffer<uint> method_decl_name_id;
StructuredBuffer<uint> method_decl_visibility;
StructuredBuffer<uint> module_type_path_type;
StructuredBuffer<uint> type_instance_decl_token;
StructuredBuffer<uint> type_instance_arg_start;
StructuredBuffer<uint> type_instance_arg_count;
StructuredBuffer<uint> type_instance_arg_ref_tag;
StructuredBuffer<uint> type_instance_arg_ref_payload;

RWStructuredBuffer<uint> method_key_status;
RWStructuredBuffer<uint> method_key_duplicate_of;
RWStructuredBuffer<uint> status;

static const uint INVALID = 0xffffffffu;
static const uint TYPE_REF_INVALID = 0u;
static const uint TYPE_REF_GENERIC_PARAM = 2u;
static const uint TYPE_REF_INSTANCE = 3u;
static const uint TY_STRUCT_BASE = 4096u;
static const uint TY_ENUM_BASE = 6144u;
static const uint TY_GENERIC_BASE = 8192u;
static const uint TYPE_INSTANCE_ARG_REF_STRIDE = 4u;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

static const uint METHOD_KEY_STATUS_PRIVATE_OK = 0u;
static const uint METHOD_KEY_STATUS_DUPLICATE = 1u;
static const uint METHOD_KEY_STATUS_INVALID_MODULE = 2u;
static const uint METHOD_KEY_STATUS_INVALID_RECEIVER = 3u;
static const uint METHOD_KEY_STATUS_INVALID_NAME = 4u;
static const uint METHOD_KEY_STATUS_PUBLIC_OK = 5u;
static const uint METHOD_KEY_STATUS_INVALID_RECEIVER_ARG = 6u;
static const uint METHOD_VIS_PUBLIC = 1u;
static const uint ERR_BAD_HIR = 6u;

uint linear_thread_id(uint3 dtid)
{
    return dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE;
}

uint active_module_count()
{
    return max(1u, min(module_count_out[0], gParams.method_capacity));
}

uint active_method_capacity()
{
    return min(token_count[0], gParams.method_capacity);
}

bool is_method_decl(uint fn_i)
{
    return fn_i < active_method_capacity() && method_decl_impl_node[fn_i] != INVALID;
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
    if (token_i >= active_method_capacity())
        return INVALID;
    return decl_token_from_type_code(module_type_path_type[token_i]);
}

uint type_ref_payload_key(uint tag, uint payload)
{
    if (tag == TYPE_REF_GENERIC_PARAM)
        return INVALID;

    if (tag == TYPE_REF_INSTANCE && payload < gParams.method_capacity)
    {
        uint decl_token = type_instance_decl_token[payload];
        if (decl_token != INVALID)
            return decl_token;
        decl_token = resolved_nominal_decl_token(payload);
        if (decl_token != INVALID)
            return decl_token;
    }
    return payload;
}

uint receiver_payload_key(uint fn_i)
{
    return type_ref_payload_key(
        method_decl_receiver_ref_tag[fn_i],
        method_decl_receiver_ref_payload[fn_i]);
}

uint receiver_arg_count(uint fn_i)
{
    uint tag = method_decl_receiver_ref_tag[fn_i];
    uint payload = method_decl_receiver_ref_payload[fn_i];
    if (tag != TYPE_REF_INSTANCE || payload >= active_method_capacity())
        return 0u;
    return min(type_instance_arg_count[payload], TYPE_INSTANCE_ARG_REF_STRIDE);
}

bool receiver_args_valid(uint fn_i)
{
    uint tag = method_decl_receiver_ref_tag[fn_i];
    uint payload = method_decl_receiver_ref_payload[fn_i];
    if (tag != TYPE_REF_INSTANCE)
        return true;
    if (payload >= active_method_capacity())
        return false;
    if (type_instance_decl_token[payload] == INVALID)
        return false;

    uint arg_count = type_instance_arg_count[payload];
    if (arg_count > TYPE_INSTANCE_ARG_REF_STRIDE)
        return false;
    if (arg_count == 0u)
        return true;

    uint start = type_instance_arg_start[payload];
    if (start == INVALID)
        return false;

    [loop]
    for (uint slot = 0u; slot < TYPE_INSTANCE_ARG_REF_STRIDE && slot < arg_count; slot += 1u)
    {
        uint arg_i = start + slot;
        if (type_instance_arg_ref_tag[arg_i] == TYPE_REF_INVALID ||
            type_instance_arg_ref_payload[arg_i] == INVALID)
            return false;
    }
    return true;
}

uint receiver_arg_ref_index(uint fn_i, uint slot)
{
    uint tag = method_decl_receiver_ref_tag[fn_i];
    uint payload = method_decl_receiver_ref_payload[fn_i];
    if (tag != TYPE_REF_INSTANCE || payload >= active_method_capacity())
        return INVALID;
    if (slot >= receiver_arg_count(fn_i))
        return INVALID;
    uint start = type_instance_arg_start[payload];
    return start == INVALID ? INVALID : start + slot;
}

uint receiver_arg_ref_tag_key(uint fn_i, uint slot)
{
    uint arg_i = receiver_arg_ref_index(fn_i, slot);
    return arg_i == INVALID ? TYPE_REF_INVALID : type_instance_arg_ref_tag[arg_i];
}

uint receiver_arg_ref_payload_key(uint fn_i, uint slot)
{
    uint arg_i = receiver_arg_ref_index(fn_i, slot);
    if (arg_i == INVALID)
        return INVALID;
    return type_ref_payload_key(
        type_instance_arg_ref_tag[arg_i],
        type_instance_arg_ref_payload[arg_i]);
}

uint invalid_method_status(uint fn_i)
{
    if (!is_method_decl(fn_i))
        return METHOD_KEY_STATUS_INVALID_NAME;

    uint module_id = method_decl_module_id[fn_i];
    if (module_id == INVALID || module_id >= active_module_count())
        return METHOD_KEY_STATUS_INVALID_MODULE;
    if (method_decl_receiver_ref_tag[fn_i] == TYPE_REF_INVALID ||
        method_decl_receiver_ref_payload[fn_i] == INVALID)
        return METHOD_KEY_STATUS_INVALID_RECEIVER;
    if (!receiver_args_valid(fn_i))
        return METHOD_KEY_STATUS_INVALID_RECEIVER_ARG;
    if (method_decl_name_id[fn_i] == INVALID)
        return METHOD_KEY_STATUS_INVALID_NAME;

    return METHOD_KEY_STATUS_PRIVATE_OK;
}

public struct MethodValidationFixedKey : IFixedU32RowKey<uint>
{
    public static uint row_lane(uint fn_i, uint lane)
    {
        if (lane == 0u)
            return fixed_key_encode_nullable_u32(
                method_decl_receiver_ref_tag[fn_i],
                TYPE_REF_INVALID);
        if (lane == 1u)
            return fixed_key_encode_nullable_u32(receiver_payload_key(fn_i), INVALID);
        if (lane == 2u)
            return receiver_arg_count(fn_i) + 1u;
        if (lane == 3u)
            return fixed_key_encode_nullable_u32(
                receiver_arg_ref_tag_key(fn_i, 0u),
                TYPE_REF_INVALID);
        if (lane == 4u)
            return fixed_key_encode_nullable_u32(
                receiver_arg_ref_payload_key(fn_i, 0u),
                INVALID);
        if (lane == 5u)
            return fixed_key_encode_nullable_u32(
                receiver_arg_ref_tag_key(fn_i, 1u),
                TYPE_REF_INVALID);
        if (lane == 6u)
            return fixed_key_encode_nullable_u32(
                receiver_arg_ref_payload_key(fn_i, 1u),
                INVALID);
        if (lane == 7u)
            return fixed_key_encode_nullable_u32(
                receiver_arg_ref_tag_key(fn_i, 2u),
                TYPE_REF_INVALID);
        if (lane == 8u)
            return fixed_key_encode_nullable_u32(
                receiver_arg_ref_payload_key(fn_i, 2u),
                INVALID);
        if (lane == 9u)
            return fixed_key_encode_nullable_u32(
                receiver_arg_ref_tag_key(fn_i, 3u),
                TYPE_REF_INVALID);
        if (lane == 10u)
            return fixed_key_encode_nullable_u32(
                receiver_arg_ref_payload_key(fn_i, 3u),
                INVALID);
        if (lane == 11u)
            return fixed_key_encode_nullable_u32(method_decl_name_id[fn_i], INVALID);
        return fixed_key_encode_nullable_u32(method_decl_module_id[fn_i], INVALID);
    }

    public static uint key_lane(uint fn_i, uint lane)
    {
        return row_lane(fn_i, lane);
    }
}

bool method_keys_equal(uint left_fn_i, uint right_fn_i)
{
    if (invalid_method_status(left_fn_i) != METHOD_KEY_STATUS_PRIVATE_OK ||
        invalid_method_status(right_fn_i) != METHOD_KEY_STATUS_PRIVATE_OK)
        return false;

    return fixed_u32_row_key_equal<uint, MethodValidationFixedKey>(
        left_fn_i,
        right_fn_i,
        13u);
}

public struct MethodKeyEquality : ISortedRunEquality
{
    public static bool equal(uint left_item, uint right_item)
    {
        return method_keys_equal(left_item, right_item);
    }
}

uint error_token_for_method(uint fn_i)
{
    if (fn_i < active_method_capacity())
    {
        uint name_token = method_decl_name_token[fn_i];
        if (name_token != INVALID)
            return name_token;
        if (fn_i != INVALID)
            return fn_i;
    }
    return 0u;
}

void record_error(uint token_i, uint code, uint detail)
{
    record_min_token_error(status, token_i, code, detail);
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint i = linear_thread_id(dtid);
    uint method_count = active_method_capacity();
    if (i >= method_count)
        return;

    uint fn_i;
    if (!sorted_order_item(
        i,
        method_count,
        method_count,
        sorted_method_key_order,
        fn_i))
        return;

    method_key_duplicate_of[fn_i] = INVALID;
    if (!is_method_decl(fn_i))
    {
        method_key_status[fn_i] = METHOD_KEY_STATUS_PRIVATE_OK;
        return;
    }

    uint status = invalid_method_status(fn_i);
    if (status != METHOD_KEY_STATUS_PRIVATE_OK)
    {
        method_key_status[fn_i] = status;
        record_error(error_token_for_method(fn_i), ERR_BAD_HIR, status);
        return;
    }

    method_key_status[fn_i] =
        method_decl_visibility[fn_i] == METHOD_VIS_PUBLIC ? METHOD_KEY_STATUS_PUBLIC_OK
                                                          : METHOD_KEY_STATUS_PRIVATE_OK;
    uint prev_fn_i;
    if (!sorted_adjacent_duplicate<MethodKeyEquality>(
        i,
        method_count,
        method_count,
        sorted_method_key_order,
        fn_i,
        prev_fn_i))
        return;
    method_key_status[fn_i] = METHOD_KEY_STATUS_DUPLICATE;
    method_key_duplicate_of[fn_i] = prev_fn_i;
    record_error(error_token_for_method(fn_i), ERR_BAD_HIR, METHOD_KEY_STATUS_DUPLICATE);
}
