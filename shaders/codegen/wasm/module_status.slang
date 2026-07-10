// Publish final WASM module status from body status and module capacity.

import gpu_index;

struct Params
{
    uint n_tokens;
    uint source_len;
    uint out_capacity;
    uint n_hir_nodes;
};

ConstantBuffer<Params> gParams;

StructuredBuffer<uint> body_plan;
StructuredBuffer<uint> body_status;
StructuredBuffer<uint> wasm_func_token_by_slot;
StructuredBuffer<uint> call_return_type;
StructuredBuffer<uint> call_param_count;
StructuredBuffer<uint> call_param_type;
StructuredBuffer<uint> call_param_row_count_out;
StructuredBuffer<uint> call_param_row_fn_token;
StructuredBuffer<uint> call_param_row_ordinal;
StructuredBuffer<uint> call_param_row_type;
StructuredBuffer<uint> call_param_row_start;
StructuredBuffer<uint> call_param_row_count;
StructuredBuffer<uint> method_decl_receiver_mode;
RWStructuredBuffer<uint> status;

static const uint TYPE_SECTION_PAYLOAD_LEN = 756u;
static const uint TYPE_COUNT = 114u;
static const uint TYPE_ENTRIES_LEN = TYPE_SECTION_PAYLOAD_LEN - 1u;
static const uint IMPORT_SECTION_LEN = 521u;
static const uint MEMORY_SECTION_LEN = 17u;
static const uint EXPORT_SECTION_LEN = 31u;
static const uint BODY_PLAN_FUNCTION_COUNT = 31u;
static const uint MODULE_STATUS_SLOT_COUNT = 2u;
static const uint DISPATCH_X_STRIDE = 16776960u;
static const uint INVALID = 0xffffffffu;
static const uint TY_VOID = 1u;
static const uint TY_BOOL = 2u;
static const uint TY_INT = 3u;
static const uint TY_UINT = 4u;
static const uint TY_FLOAT = 5u;
static const uint TY_STRING = 7u;
static const uint TY_ARRAY_BASE = 128u;
static const uint METHOD_RECEIVER_SELF = 1u;
static const uint METHOD_RECEIVER_REF_SELF = 2u;

uint linear_dispatch_id(uint3 tid)
{
    return linear_dispatch_thread_id_2d(tid, DISPATCH_X_STRIDE);
}

bool prior_module_or_error(uint mode, uint error_code)
{
    return mode == 1u || mode == 2u || mode == 5u || error_code != 0u;
}

bool method_receiver_param(uint fn_token, uint ordinal)
{
    if (fn_token == INVALID || ordinal != 0u)
        return false;
    uint mode = method_decl_receiver_mode[fn_token];
    return mode == METHOD_RECEIVER_SELF || mode == METHOD_RECEIVER_REF_SELF;
}

uint call_param_type_value(uint fn_token, uint ordinal)
{
    if (fn_token == INVALID)
        return 0u;

    uint start = call_param_row_start[fn_token];
    uint count = call_param_row_count[fn_token];
    uint row_limit = call_param_row_count_out[0u];
    if (start == INVALID || ordinal >= count || start > row_limit || ordinal > row_limit - start)
        return method_receiver_param(fn_token, ordinal) ? TY_ARRAY_BASE : 0u;

    uint row = start + ordinal;
    if (row >= row_limit ||
        call_param_row_fn_token[row] != fn_token ||
        call_param_row_ordinal[row] != ordinal)
    {
        return method_receiver_param(fn_token, ordinal) ? TY_ARRAY_BASE : 0u;
    }

    uint ty = call_param_row_type[row];
    return ty == 0u && method_receiver_param(fn_token, ordinal) ? TY_ARRAY_BASE : ty;
}

uint wasm_param_abi_width(uint ty)
{
    return ty == TY_STRING ? 2u : 1u;
}

uint function_signature_param_count(uint fn_token)
{
    if (fn_token == INVALID)
        return 0u;

    uint count = call_param_count[fn_token];
    uint total = 0u;
    for (uint ordinal = 0u; ordinal < count; ordinal += 1u)
        total += wasm_param_abi_width(call_param_type_value(fn_token, ordinal));
    return total;
}

uint function_signature_type_entry_len(uint fn_token)
{
    uint param_count = function_signature_param_count(fn_token);
    uint ret = fn_token == INVALID ? TY_VOID : call_return_type[fn_token];
    uint result_count =
        ret == TY_BOOL || ret == TY_INT || ret == TY_UINT || ret == TY_FLOAT || ret >= TY_ARRAY_BASE
            ? 1u
            : 0u;
    return 1u + 5u + param_count + 1u + result_count;
}

uint dynamic_type_entries_len(uint function_count)
{
    uint total = 0u;
    for (uint slot = 0u; slot < function_count; slot += 1u)
    {
        uint fn_token = wasm_func_token_by_slot[slot];
        total += function_signature_type_entry_len(fn_token);
    }
    return total;
}

uint type_section_payload_len(uint function_count)
{
    return 5u + TYPE_ENTRIES_LEN + dynamic_type_entries_len(function_count);
}

uint type_section_len(uint function_count)
{
    return 6u + type_section_payload_len(function_count);
}

uint module_body_start(uint function_count)
{
    uint function_section_len = 11u + function_count * 5u;
    uint code_header_len = 11u;
    return 8u +
           type_section_len(function_count) +
           IMPORT_SECTION_LEN +
           function_section_len +
           MEMORY_SECTION_LEN +
           EXPORT_SECTION_LEN +
           code_header_len;
}

uint data_section_len()
{
    return 24u + gParams.source_len;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    uint slot = linear_dispatch_id(tid);
    uint input_mode = status[1u];
    uint input_error_code = status[2u];
    GroupMemoryBarrierWithGroupSync();

    if (slot >= MODULE_STATUS_SLOT_COUNT ||
        prior_module_or_error(input_mode, input_error_code))
        return;

    uint body_len = body_status[0u];
    bool body_ok = body_status[1u] != 0u;
    uint module_len =
        module_body_start(body_plan[BODY_PLAN_FUNCTION_COUNT]) + body_len + data_section_len();
    bool ok = body_ok && module_len <= gParams.out_capacity;

    if (slot == 0u)
        status[0u] = module_len;
    else
        status[1u] = ok ? 3u : 0u;
}
