// Project per-function type records and body lengths from retained GPU metadata.

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
StructuredBuffer<uint> wasm_func_token_by_slot;
StructuredBuffer<uint> wasm_type_entry_len_by_slot;
StructuredBuffer<uint> wasm_type_scan_local_prefix;
StructuredBuffer<uint> wasm_type_scan_block_prefix;
StructuredBuffer<uint> wasm_func_body_len_by_token;
StructuredBuffer<uint> decl_id_by_name_token;
StructuredBuffer<uint> interface_public_decl_index_by_local;
RWStructuredBuffer<uint> object_function_record;
RWStructuredBuffer<uint> object_body_len_by_slot;

static const uint INVALID = 0xffffffffu;
static const uint WG_SIZE = 256u;
static const uint DISPATCH_X_STRIDE = 16776960u;
static const uint BODY_PLAN_FUNCTION_COUNT = 31u;

uint linear_dispatch_id(uint3 tid)
{
    return linear_dispatch_thread_id_2d(tid, DISPATCH_X_STRIDE);
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    uint slot = linear_dispatch_id(tid);
    if (slot >= gParams.n_tokens)
        return;
    uint function_count = min(body_plan[BODY_PLAN_FUNCTION_COUNT], gParams.n_tokens);
    if (slot >= function_count)
    {
        object_body_len_by_slot[slot] = 0u;
        return;
    }

    uint fn_token = wasm_func_token_by_slot[slot];
    uint type_len = wasm_type_entry_len_by_slot[slot];
    uint type_start = global_exclusive_prefix(
        slot,
        WG_SIZE,
        wasm_type_scan_local_prefix,
        wasm_type_scan_block_prefix);
    // The retained table stores the Wasm body payload size. The durable code
    // section record also owns the maximally padded five-byte size prefix.
    uint body_len = fn_token < gParams.n_tokens
        ? 5u + wasm_func_body_len_by_token[fn_token]
        : 0u;
    uint local_decl = fn_token < gParams.n_tokens
        ? decl_id_by_name_token[fn_token]
        : INVALID;
    uint symbol_index = local_decl < gParams.n_tokens
        ? interface_public_decl_index_by_local[local_decl]
        : INVALID;

    uint base = slot * 6u;
    object_function_record[base + 0u] = type_start;
    object_function_record[base + 1u] = type_len;
    object_function_record[base + 2u] = 0u;
    object_function_record[base + 3u] = body_len;
    object_function_record[base + 4u] = symbol_index;
    object_function_record[base + 5u] = 0u;
    object_body_len_by_slot[slot] = body_len;
}
