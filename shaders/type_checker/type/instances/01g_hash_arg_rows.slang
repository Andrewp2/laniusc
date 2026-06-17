// Hash compact named type-instance argument rows for method receiver lookup.
//
// The hash is an index key only. Consumers still compare the compact rows for
// equality before accepting a match, so hash collisions cannot change type
// checking behavior.

struct Params
{
    uint n_tokens;
    uint source_len;
    uint n_hir_nodes;
};

ConstantBuffer<Params> gParams;

StructuredBuffer<uint> token_count;
StructuredBuffer<uint> module_type_path_type;
StructuredBuffer<uint> type_instance_decl_token;
StructuredBuffer<uint> type_instance_arg_start;
StructuredBuffer<uint> type_instance_arg_count;
StructuredBuffer<uint> type_instance_arg_ref_tag;
StructuredBuffer<uint> type_instance_arg_ref_payload;
StructuredBuffer<uint> type_instance_arg_row_start;
StructuredBuffer<uint> type_instance_arg_row_count_out;
StructuredBuffer<uint> type_instance_arg_row_ref_tag;
StructuredBuffer<uint> type_instance_arg_row_ref_payload;

RWStructuredBuffer<uint> type_instance_arg_hash;

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

uint linear_thread_id(uint3 dtid)
{
    return dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE;
}

uint active_token_count()
{
    return min(token_count[0], gParams.n_tokens);
}

bool valid_token(uint token)
{
    return token != INVALID && token < active_token_count();
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
    if (!valid_token(token_i))
        return INVALID;
    return decl_token_from_type_code(module_type_path_type[token_i]);
}

uint type_ref_payload_key(uint tag, uint payload)
{
    if (tag == TYPE_REF_GENERIC_PARAM)
        return INVALID;

    if (tag == TYPE_REF_INSTANCE && valid_token(payload))
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

uint instance_arg_ref_index(uint instance_i, uint slot)
{
    uint start = type_instance_arg_start[instance_i];
    return start == INVALID ? INVALID : start + slot;
}

uint instance_arg_row_ref_index(uint instance_i, uint ordinal)
{
    uint start = type_instance_arg_row_start[instance_i];
    uint ref_i = start == INVALID ? INVALID : start + ordinal;
    return ref_i != INVALID && ref_i < type_instance_arg_row_count_out[0u]
        ? ref_i
        : INVALID;
}

bool instance_arg_ref(uint instance_i, uint ordinal, out uint tag, out uint payload)
{
    tag = TYPE_REF_INVALID;
    payload = INVALID;
    if (!valid_token(instance_i) || ordinal >= type_instance_arg_count[instance_i])
        return false;

    uint row_ref_i = instance_arg_row_ref_index(instance_i, ordinal);
    if (row_ref_i != INVALID)
    {
        tag = type_instance_arg_row_ref_tag[row_ref_i];
        payload = type_instance_arg_row_ref_payload[row_ref_i];
        if (tag != TYPE_REF_INVALID)
            return true;
    }

    if (ordinal >= TYPE_INSTANCE_ARG_REF_STRIDE)
        return false;

    uint fixed_ref_i = instance_arg_ref_index(instance_i, ordinal);
    if (fixed_ref_i == INVALID)
        return false;

    tag = type_instance_arg_ref_tag[fixed_ref_i];
    payload = type_instance_arg_ref_payload[fixed_ref_i];
    return tag != TYPE_REF_INVALID;
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

uint type_instance_arg_row_hash(uint instance_i)
{
    uint count = type_instance_arg_count[instance_i];
    uint hash = mix_hash(2166136261u, count);
    uint total_rows = type_instance_arg_row_count_out[0u];
    [loop]
    for (uint ordinal = 0u; ordinal < count; ordinal += 1u)
    {
        if (ordinal >= total_rows)
            return 0u;

        uint tag;
        uint payload;
        if (!instance_arg_ref(instance_i, ordinal, tag, payload))
            return 0u;

        hash = mix_hash(hash, encoded_hash_value(tag, TYPE_REF_INVALID));
        hash = mix_hash(
            hash,
            encoded_hash_value(type_ref_payload_key(tag, payload), INVALID));
    }
    return hash;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint token_i = linear_thread_id(dtid);
    if (!valid_token(token_i))
        return;

    type_instance_arg_hash[token_i] = type_instance_arg_row_hash(token_i);
}
