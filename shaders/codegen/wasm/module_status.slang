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

uint linear_dispatch_id(uint3 tid)
{
    return linear_dispatch_thread_id_2d(tid, DISPATCH_X_STRIDE);
}

bool prior_module_or_error(uint mode, uint error_code)
{
    return mode == 1u || mode == 2u || mode == 5u || error_code != 0u;
}

uint function_signature_type_entry_len(uint fn_token)
{
    uint param_count = fn_token == INVALID ? 0u : call_param_count[fn_token];
    uint ret = fn_token == INVALID ? TY_VOID : call_return_type[fn_token];
    uint result_count = ret == TY_VOID ? 0u : 1u;
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
