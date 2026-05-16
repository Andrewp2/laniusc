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

struct Params
{
    uint n_tokens;
    uint source_len;
    uint n_hir_nodes;
};

ConstantBuffer<Params> gParams;

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
    return dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE;
}

uint active_token_count()
{
    return gParams.n_tokens;
}

uint active_module_count()
{
    return max(1u, min(module_count_out[0], gParams.n_hir_nodes));
}

uint encoded_id(uint value)
{
    return value == INVALID ? 0u : value + 1u;
}

uint encoded_type_ref_tag(uint value)
{
    return value == TYPE_REF_INVALID ? 0u : value + 1u;
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

int compare_encoded(uint left, uint right)
{
    if (left < right)
        return -1;
    if (left > right)
        return 1;
    return 0;
}

int compare_method_key(uint row, uint module_id, uint receiver_tag, uint receiver_payload,
                       uint name_id)
{
    uint fn_i = row < gParams.n_tokens ? sorted_method_key_order[row] : INVALID;
    uint row_module = fn_i < gParams.n_tokens ? method_decl_module_id[fn_i] : INVALID;
    int cmp = compare_encoded(encoded_id(row_module), encoded_id(module_id));
    if (cmp != 0)
        return cmp;

    uint row_tag = fn_i < gParams.n_tokens ? method_decl_receiver_ref_tag[fn_i] : TYPE_REF_INVALID;
    cmp = compare_encoded(encoded_type_ref_tag(row_tag), encoded_type_ref_tag(receiver_tag));
    if (cmp != 0)
        return cmp;

    uint row_payload = fn_i < gParams.n_tokens ? receiver_payload_key(
                                                      method_decl_receiver_ref_tag[fn_i],
                                                      method_decl_receiver_ref_payload[fn_i])
                                                : INVALID;
    cmp = compare_encoded(encoded_id(row_payload),
                          encoded_id(receiver_payload_key(receiver_tag, receiver_payload)));
    if (cmp != 0)
        return cmp;

    uint row_name = fn_i < gParams.n_tokens ? method_decl_name_id[fn_i] : INVALID;
    return compare_encoded(encoded_id(row_name), encoded_id(name_id));
}

uint find_method(uint module_id, uint receiver_tag, uint receiver_payload, uint name_id)
{
    if (module_id == INVALID || receiver_tag == TYPE_REF_INVALID || receiver_payload == INVALID ||
        name_id == INVALID)
        return INVALID;

    uint lo = 0u;
    uint hi = gParams.n_tokens;
    [loop]
    for (uint guard = 0u; guard < 32u && lo < hi; guard += 1u)
    {
        uint mid = lo + ((hi - lo) >> 1u);
        int cmp = compare_method_key(mid, module_id, receiver_tag, receiver_payload, name_id);
        if (cmp < 0)
            lo = mid + 1u;
        else
            hi = mid;
    }

    if (lo >= gParams.n_tokens ||
        compare_method_key(lo, module_id, receiver_tag, receiver_payload, name_id) != 0)
        return INVALID;

    uint fn_i = sorted_method_key_order[lo];
    if (fn_i >= gParams.n_tokens)
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
    if (fn_i >= gParams.n_tokens)
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
