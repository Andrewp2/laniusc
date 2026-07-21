// GPU method-key radix histogram.
//
// Scheduling contract:
// - Dispatch after type_check_methods_03_seed_key_order.slang or the previous
//   stable scatter pass has initialized method_key_order_in.
// - For key_step 0..23, the host schedules histogram, GPU bucket-prefix scan,
//   GPU bucket-base scan, and stable scatter.
// - key_step walks the fixed method key from least-significant to
//   most-significant: defining module id, method name id, bounded receiver
//   type-argument row hash/count, receiver nominal payload, then receiver
//   type-ref tag.
//   That leaves receiver/name as the searchable prefix and module as a
//   duplicate/visibility tie-breaker.
// - Invalid records encode to sentinel 0, while real ids encode as id + 1.
// - This pass only counts radix buckets. It does not resolve methods, inspect
//   source bytes, hash token text, perform CPU lookup, or apply same-source
//   shortcuts.

import gpu_index;
import radix;

struct Params
{
    uint method_capacity;
    uint reserved;
    uint n_blocks;
    uint key_step;
};

ConstantBuffer<Params> gParams;

StructuredBuffer<uint> token_count;
StructuredBuffer<uint> method_decl_method_row;
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
StructuredBuffer<uint> type_instance_arg_hash;
StructuredBuffer<uint> method_key_order_in;

RWStructuredBuffer<uint> radix_block_histogram;

static const uint INVALID = 0xffffffffu;
static const uint TYPE_REF_INVALID = 0u;
static const uint TYPE_REF_GENERIC_PARAM = 2u;
static const uint TYPE_REF_INSTANCE = 3u;
static const uint TY_STRUCT_BASE = 4096u;
static const uint TY_ENUM_BASE = 6144u;
static const uint TY_GENERIC_BASE = 8192u;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;
static const uint RADIX_BUCKETS = RADIX_U8_SENTINEL_BUCKETS;

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
    return fn_i < active_method_capacity() && method_decl_method_row[fn_i] != INVALID &&
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
    return type_instance_arg_count[payload];
}

uint receiver_arg_hash(uint fn_i)
{
    uint tag = method_decl_receiver_ref_tag[fn_i];
    uint payload = method_decl_receiver_ref_payload[fn_i];
    if (tag != TYPE_REF_INSTANCE || payload >= active_method_capacity())
        return 0u;
    return type_instance_arg_hash[payload];
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
        return receiver_arg_hash(fn_i);
    if (field_i == 3u)
        return receiver_arg_count(fn_i) + 1u;
    if (field_i == 4u)
        return encode_nullable_id(receiver_payload_key(fn_i), INVALID);
    return method_decl_receiver_ref_tag[fn_i] + 1u;
}

uint method_key_radix_key(uint fn_i, uint key_step)
{
    uint field_i = radix_field_index(key_step, 5u);
    uint value = method_key_field(fn_i, field_i);
    return radix_byte_key(value, key_step);
}

public struct MethodKeyRadixSource : IRadixU8KeySource
{
    public static uint active_count()
    {
        return active_method_capacity();
    }

    public static uint ordered_row(uint order_i)
    {
        return method_key_order_in[order_i];
    }

    public static uint radix_key(uint row, uint key_step)
    {
        return method_key_radix_key(row, key_step);
    }
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 gid: SV_GroupID, uint3 ltid: SV_GroupThreadID)
{
    uint block_idx = linear_group_id(gid);
    uint lane = ltid.x;
    radix_u8_histogram_block<MethodKeyRadixSource>(
        block_idx,
        lane,
        gParams.n_blocks,
        gParams.key_step,
        WG_SIZE,
        RADIX_BUCKETS,
        radix_block_histogram);
}
