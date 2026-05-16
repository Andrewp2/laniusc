// GPU method-key radix stable scatter.
//
// Scheduling contract:
// - Dispatch after type_check_methods_04_sort_keys.slang and GPU scans over
//   radix bucket counts for the same key_step.
// - This pass performs one stable scatter over method keys ordered by
//   (module_id, receiver type-ref tag/payload, method name id).
// - It does not resolve methods, inspect source bytes, hash token text, perform
//   CPU lookup, or apply same-source shortcuts.

struct Params
{
    uint method_capacity;
    uint reserved;
    uint n_blocks;
    uint key_step;
};

ConstantBuffer<Params> gParams;

StructuredBuffer<uint> method_decl_impl_node;
StructuredBuffer<uint> method_decl_receiver_ref_tag;
StructuredBuffer<uint> method_decl_receiver_ref_payload;
StructuredBuffer<uint> method_decl_module_id;
StructuredBuffer<uint> method_decl_name_id;
StructuredBuffer<uint> module_type_path_type;
StructuredBuffer<uint> type_instance_decl_token;
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
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;
static const uint RADIX_BUCKETS = 257u;

uint linear_group_id(uint3 gid)
{
    return gid.x + gid.y * MAX_GROUPS_X;
}

uint encoded_id(uint value)
{
    return value == INVALID ? 0u : value + 1u;
}

bool valid_method_record(uint fn_i)
{
    return fn_i < gParams.method_capacity && method_decl_impl_node[fn_i] != INVALID &&
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
    if (token_i >= gParams.method_capacity)
        return INVALID;
    return decl_token_from_type_code(module_type_path_type[token_i]);
}

uint receiver_payload_key(uint fn_i)
{
    uint payload = method_decl_receiver_ref_payload[fn_i];
    uint tag = method_decl_receiver_ref_tag[fn_i];
    if (tag == TYPE_REF_INSTANCE && payload < gParams.method_capacity)
    {
        uint decl_token = type_instance_decl_token[payload];
        if (decl_token != INVALID)
            return decl_token;
        decl_token = resolved_nominal_decl_token(payload);
        if (decl_token != INVALID)
            return decl_token;
    }
    if (tag == TYPE_REF_GENERIC_PARAM)
    {
        uint decl_token = resolved_nominal_decl_token(payload);
        if (decl_token != INVALID)
            return decl_token;
    }
    return payload;
}

uint method_key_field(uint fn_i, uint field_i)
{
    if (!valid_method_record(fn_i))
        return 0u;

    if (field_i == 0u)
        return encoded_id(method_decl_name_id[fn_i]);
    if (field_i == 1u)
        return encoded_id(receiver_payload_key(fn_i));
    if (field_i == 2u)
        return method_decl_receiver_ref_tag[fn_i] + 1u;
    return encoded_id(method_decl_module_id[fn_i]);
}

uint method_key_radix_key(uint fn_i, uint key_step)
{
    uint field_i = min(key_step / 4u, 3u);
    uint byte_i = key_step & 3u;
    uint value = method_key_field(fn_i, field_i);
    return (value >> (byte_i * 8u)) & 0xffu;
}

uint local_same_key_rank(uint block_begin, uint lane, uint key)
{
    uint rank = 0u;
    [loop]
    for (uint j = 0u; j < lane; j += 1u)
    {
        uint order_j = block_begin + j;
        if (order_j < gParams.method_capacity)
        {
            uint prev_fn_i = method_key_order_in[order_j];
            if (method_key_radix_key(prev_fn_i, gParams.key_step) == key)
                rank += 1u;
        }
    }
    return rank;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 gid: SV_GroupID, uint3 ltid: SV_GroupThreadID)
{
    uint block_idx = linear_group_id(gid);
    if (block_idx >= gParams.n_blocks)
        return;

    uint lane = ltid.x;
    uint order_i = block_idx * WG_SIZE + lane;
    if (order_i >= gParams.method_capacity)
        return;

    uint fn_i = method_key_order_in[order_i];
    uint key = method_key_radix_key(fn_i, gParams.key_step);
    uint rank = local_same_key_rank(block_idx * WG_SIZE, lane, key);
    uint block_prefix = radix_block_bucket_prefix[block_idx * RADIX_BUCKETS + key];
    uint dst = radix_bucket_base[key] + block_prefix + rank;

    if (dst < gParams.method_capacity)
        method_key_order_out[dst] = fn_i;
}
