// GPU sorted method-key validation.
//
// Scheduling contract:
// - Dispatch after the method key radix sort has produced
//   sorted_method_key_order.
// - Adjacent equal valid keys are duplicate inherent methods in the same module
//   for the same receiver type-ref and interned method name.
// - This pass writes per-method validation results and reduces invalid or
//   duplicate method declarations into the compiler-wide type-check status. It
//   does not resolve calls, inspect source bytes, hash token text, perform CPU
//   lookup, or apply same-source shortcuts.

struct Params
{
    uint method_capacity;
    uint reserved;
    uint n_blocks;
    uint key_step;
};

ConstantBuffer<Params> gParams;

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
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

static const uint METHOD_KEY_STATUS_PRIVATE_OK = 0u;
static const uint METHOD_KEY_STATUS_DUPLICATE = 1u;
static const uint METHOD_KEY_STATUS_INVALID_MODULE = 2u;
static const uint METHOD_KEY_STATUS_INVALID_RECEIVER = 3u;
static const uint METHOD_KEY_STATUS_INVALID_NAME = 4u;
static const uint METHOD_KEY_STATUS_PUBLIC_OK = 5u;
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

bool is_method_decl(uint fn_i)
{
    return fn_i < gParams.method_capacity && method_decl_impl_node[fn_i] != INVALID;
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
    if (method_decl_name_id[fn_i] == INVALID)
        return METHOD_KEY_STATUS_INVALID_NAME;

    return METHOD_KEY_STATUS_PRIVATE_OK;
}

bool method_keys_equal(uint left_fn_i, uint right_fn_i)
{
    if (invalid_method_status(left_fn_i) != METHOD_KEY_STATUS_PRIVATE_OK ||
        invalid_method_status(right_fn_i) != METHOD_KEY_STATUS_PRIVATE_OK)
        return false;

    return method_decl_module_id[left_fn_i] == method_decl_module_id[right_fn_i] &&
           method_decl_receiver_ref_tag[left_fn_i] == method_decl_receiver_ref_tag[right_fn_i] &&
           receiver_payload_key(left_fn_i) == receiver_payload_key(right_fn_i) &&
           method_decl_name_id[left_fn_i] == method_decl_name_id[right_fn_i];
}

uint error_token_for_method(uint fn_i)
{
    if (fn_i < gParams.method_capacity)
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
    uint old;
    InterlockedMin(status[1], token_i, old);
    if (token_i <= old)
    {
        status[0] = 0u;
        status[2] = code;
        status[3] = detail;
    }
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint i = linear_thread_id(dtid);
    if (i >= gParams.method_capacity)
        return;

    uint fn_i = sorted_method_key_order[i];
    if (fn_i >= gParams.method_capacity)
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
    if (i == 0u)
        return;

    uint prev_fn_i = sorted_method_key_order[i - 1u];
    if (prev_fn_i >= gParams.method_capacity)
        return;

    if (!method_keys_equal(prev_fn_i, fn_i))
        return;

    method_key_status[fn_i] = METHOD_KEY_STATUS_DUPLICATE;
    method_key_duplicate_of[fn_i] = prev_fn_i;
    record_error(error_token_for_method(fn_i), ERR_BAD_HIR, METHOD_KEY_STATUS_DUPLICATE);
}
