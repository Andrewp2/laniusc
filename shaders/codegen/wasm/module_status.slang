// Publish final WASM module status from body status and module capacity.

import gpu_index;
import prefix_scan;

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
StructuredBuffer<uint> wasm_type_entry_len_by_slot;
StructuredBuffer<uint> wasm_type_scan_local_prefix;
StructuredBuffer<uint> wasm_type_scan_block_prefix;
StructuredBuffer<uint> hir_string_pool_len;
RWStructuredBuffer<uint> status;

static const uint TYPE_SECTION_PAYLOAD_LEN = 756u;
static const uint TYPE_COUNT = 114u;
static const uint TYPE_ENTRIES_LEN = TYPE_SECTION_PAYLOAD_LEN - 1u;
static const uint IMPORT_SECTION_LEN = 712u;
static const uint MEMORY_SECTION_LEN = 17u;
static const uint EXPORT_SECTION_LEN = 31u;
static const uint BODY_PLAN_FUNCTION_COUNT = 31u;
static const uint MODULE_STATUS_SLOT_COUNT = 2u;
static const uint DISPATCH_X_STRIDE = 16776960u;
static const uint TYPE_SCAN_WG_SIZE = 256u;

uint linear_dispatch_id(uint3 tid)
{
    return linear_dispatch_thread_id_2d(tid, DISPATCH_X_STRIDE);
}

bool prior_module_or_error(uint mode, uint error_code)
{
    return mode == 1u || mode == 2u || mode == 5u || error_code != 0u;
}

uint dynamic_type_entries_len(uint function_count)
{
    if (function_count == 0u)
        return 0u;
    uint last = function_count - 1u;
    return global_exclusive_prefix(last, TYPE_SCAN_WG_SIZE, wasm_type_scan_local_prefix, wasm_type_scan_block_prefix) +
           wasm_type_entry_len_by_slot[last];
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
    return 24u + hir_string_pool_len[0u];
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
