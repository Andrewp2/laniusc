// GPU sorted method-table resolver.
//
// Scheduling contract:
// - Dispatch after method-call keys are marked and method declaration keys are
//   sorted/validated.
// - This pass binary-searches sorted_method_key_order using
//   (module_id, receiver type-ref tag/payload, method name id) and writes the
//   resolved function token plus return type metadata.
// - It does not inspect source bytes, hash token text, compare names by
//   spelling, perform CPU lookup, or use the legacy direct method hash table.

import fixed_key;
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
StructuredBuffer<uint> type_instance_decl_token;

RWStructuredBuffer<uint> call_fn_index;
RWStructuredBuffer<uint> call_return_type;
RWStructuredBuffer<uint> call_return_type_token;

static const uint INVALID = 0xffffffffu;
static const uint TYPE_REF_INVALID = 0u;
static const uint TYPE_REF_GENERIC_PARAM = 2u;
static const uint TYPE_REF_INSTANCE = 3u;
static const uint TY_STRUCT_BASE = 4096u;
static const uint TY_ENUM_BASE = 6144u;
static const uint TY_GENERIC_BASE = 8192u;
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

uint receiver_payload_key(uint receiver_tag, uint receiver_payload)
{
    if (receiver_tag == TYPE_REF_INSTANCE && receiver_payload < active_token_count())
    {
        uint decl_token = type_instance_decl_token[receiver_payload];
        if (decl_token != INVALID)
            return decl_token;
        decl_token = resolved_nominal_decl_token(receiver_payload);
        if (decl_token != INVALID)
            return decl_token;
    }
    if (receiver_tag == TYPE_REF_GENERIC_PARAM)
    {
        uint decl_token = resolved_nominal_decl_token(receiver_payload);
        if (decl_token != INVALID)
            return decl_token;
    }
    return receiver_payload;
}

public struct MethodLookupKey
{
    uint module_id;
    uint receiver_tag;
    uint receiver_payload;
    uint name_id;
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
            return fixed_key_encode_nullable_u32(method_decl_module_id[fn_i], INVALID);
        if (lane == 1u)
            return fixed_key_encode_nullable_u32(
                method_decl_receiver_ref_tag[fn_i],
                TYPE_REF_INVALID);
        if (lane == 2u)
            return fixed_key_encode_nullable_u32(
                receiver_payload_key(
                    method_decl_receiver_ref_tag[fn_i],
                    method_decl_receiver_ref_payload[fn_i]),
                INVALID);
        return fixed_key_encode_nullable_u32(method_decl_name_id[fn_i], INVALID);
    }

    public static uint key_lane(MethodLookupKey key, uint lane)
    {
        if (lane == 0u)
            return fixed_key_encode_nullable_u32(key.module_id, INVALID);
        if (lane == 1u)
            return fixed_key_encode_nullable_u32(key.receiver_tag, TYPE_REF_INVALID);
        if (lane == 2u)
            return fixed_key_encode_nullable_u32(
                receiver_payload_key(key.receiver_tag, key.receiver_payload),
                INVALID);
        return fixed_key_encode_nullable_u32(key.name_id, INVALID);
    }
}

public struct MethodKeyCompare : IRowQueryCompare<MethodLookupKey>
{
    public static int compare(uint row, MethodLookupKey key)
    {
        return fixed_u32_row_key_compare<MethodLookupKey, MethodFixedKey>(
            row,
            key,
            4u);
    }
}

uint find_method(uint module_id, uint receiver_tag, uint receiver_payload, uint name_id)
{
    if (module_id == INVALID || receiver_tag == TYPE_REF_INVALID || receiver_payload == INVALID ||
        name_id == INVALID)
        return INVALID;

    MethodLookupKey key;
    key.module_id = module_id;
    key.receiver_tag = receiver_tag;
    key.receiver_payload = receiver_payload;
    key.name_id = name_id;
    uint row = find_equal_query<MethodLookupKey, MethodKeyCompare>(active_token_count(), key);
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

uint find_visible_method(uint method_i, uint receiver_tag, uint receiver_payload, uint name_id)
{
    uint modules = active_module_count();
    [loop]
    for (uint module_id = 0u; module_id < modules; module_id += 1u)
    {
        uint fn_i = find_method(module_id, receiver_tag, receiver_payload, name_id);
        fn_i = visibility_checked_method(method_i, fn_i);
        if (fn_i != INVALID)
            return fn_i;
    }
    return INVALID;
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

    uint ret_ty = call_return_type[fn_i];
    call_fn_index[i] = fn_i;
    call_return_type[i] = ret_ty;
    call_return_type_token[i] = call_return_type_token[fn_i];
}
