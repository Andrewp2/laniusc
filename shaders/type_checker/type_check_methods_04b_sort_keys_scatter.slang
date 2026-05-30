// GPU method-key radix stable scatter.
//
// Scheduling contract:
// - Dispatch after type_check_methods_04_sort_keys.slang and GPU scans over
//   radix bucket counts for the same key_step.
// - This pass performs one stable scatter over method keys ordered by
//   (receiver type-ref tag/payload, bounded receiver type-argument refs,
//   method name id, module id). Module id is the least-significant tie-breaker
//   so calls can range-query by receiver/name without scanning every module.
// - It does not resolve methods, inspect source bytes, hash token text, perform
//   CPU lookup, or apply same-source shortcuts.

import gpu_index;
import radix;
import scatter;

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
StructuredBuffer<uint> type_instance_arg_start;
StructuredBuffer<uint> type_instance_arg_count;
StructuredBuffer<uint> type_instance_arg_ref_tag;
StructuredBuffer<uint> type_instance_arg_ref_payload;
StructuredBuffer<uint> method_key_order_in;
StructuredBuffer<uint> radix_bucket_base;
StructuredBuffer<uint> radix_block_bucket_prefix;

RWStructuredBuffer<uint> method_key_order_out;

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
static const uint RADIX_BUCKETS = RADIX_U8_SENTINEL_BUCKETS;

groupshared uint local_radix_keys[256];

uint linear_group_id(uint3 gid)
{
    return linear_group_id_2d(gid, MAX_GROUPS_X);
}

uint active_method_capacity()
{
    return min(token_count[0], gParams.method_capacity);
}

bool valid_method_record(uint fn_i)
{
    return fn_i < active_method_capacity() && method_decl_impl_node[fn_i] != INVALID &&
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

uint method_key_field(uint fn_i, uint field_i)
{
    if (!valid_method_record(fn_i))
        return 0u;

    if (field_i == 0u)
        return encode_nullable_id(method_decl_module_id[fn_i], INVALID);
    if (field_i == 1u)
        return encode_nullable_id(method_decl_name_id[fn_i], INVALID);
    if (field_i == 2u)
        return encode_nullable_id(receiver_arg_ref_payload_key(fn_i, 3u), INVALID);
    if (field_i == 3u)
        return encode_nullable_id(receiver_arg_ref_tag_key(fn_i, 3u), TYPE_REF_INVALID);
    if (field_i == 4u)
        return encode_nullable_id(receiver_arg_ref_payload_key(fn_i, 2u), INVALID);
    if (field_i == 5u)
        return encode_nullable_id(receiver_arg_ref_tag_key(fn_i, 2u), TYPE_REF_INVALID);
    if (field_i == 6u)
        return encode_nullable_id(receiver_arg_ref_payload_key(fn_i, 1u), INVALID);
    if (field_i == 7u)
        return encode_nullable_id(receiver_arg_ref_tag_key(fn_i, 1u), TYPE_REF_INVALID);
    if (field_i == 8u)
        return encode_nullable_id(receiver_arg_ref_payload_key(fn_i, 0u), INVALID);
    if (field_i == 9u)
        return encode_nullable_id(receiver_arg_ref_tag_key(fn_i, 0u), TYPE_REF_INVALID);
    if (field_i == 10u)
        return receiver_arg_count(fn_i) + 1u;
    if (field_i == 11u)
        return encode_nullable_id(receiver_payload_key(fn_i), INVALID);
    return method_decl_receiver_ref_tag[fn_i] + 1u;
}

uint method_key_radix_key(uint fn_i, uint key_step)
{
    uint field_i = radix_field_index(key_step, 12u);
    uint value = method_key_field(fn_i, field_i);
    return radix_byte_key(value, key_step);
}

public struct MethodKeyScatterSource : IStableRadixScatterSource<uint>
{
    public static uint active_count()
    {
        return active_method_capacity();
    }

    public static uint inactive_value()
    {
        return 0u;
    }

    public static uint ordered_value(uint order_i)
    {
        return method_key_order_in[order_i];
    }

    public static uint radix_key(uint value, uint key_step)
    {
        return method_key_radix_key(value, key_step);
    }
}

public struct MethodKeyOrderOutSink : IScatterSink<uint>
{
    public static void store(uint dst, uint value)
    {
        method_key_order_out[dst] = value;
    }
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 gid: SV_GroupID, uint3 ltid: SV_GroupThreadID)
{
    uint block_idx = linear_group_id(gid);
    uint lane = ltid.x;
    stable_radix_scatter_block<uint, MethodKeyScatterSource, MethodKeyOrderOutSink, 256>(
        block_idx,
        lane,
        gParams.n_blocks,
        gParams.key_step,
        RADIX_BUCKETS,
        radix_bucket_base,
        radix_block_bucket_prefix,
        local_radix_keys);
}
