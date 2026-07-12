// Publish one dynamic WASM type-entry length per function slot.

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
StructuredBuffer<uint> call_return_type;
StructuredBuffer<uint> call_param_count;
StructuredBuffer<uint> call_param_row_count_out;
StructuredBuffer<uint> call_param_row_fn_token;
StructuredBuffer<uint> call_param_row_ordinal;
StructuredBuffer<uint> call_param_row_type;
StructuredBuffer<uint> call_param_row_start;
StructuredBuffer<uint> call_param_row_count;
StructuredBuffer<uint> method_decl_receiver_mode;
RWStructuredBuffer<uint> wasm_type_entry_len_by_slot;

static const uint MAX_GROUPS_X = 65535u;
static const uint INVALID = 0xffffffffu;
static const uint BODY_PLAN_FUNCTION_COUNT = 31u;
static const uint TY_VOID = 1u;
static const uint TY_BOOL = 2u;
static const uint TY_INT = 3u;
static const uint TY_UINT = 4u;
static const uint TY_FLOAT = 5u;
static const uint TY_STRING = 7u;
static const uint TY_ARRAY_BASE = 128u;
static const uint METHOD_RECEIVER_SELF = 1u;
static const uint METHOD_RECEIVER_REF_SELF = 2u;

groupshared uint param_width_prefix[256];

public struct ParamWidthAdd : IPrefixScanOp<uint>
{
    public static uint identity() { return 0u; }
    public static uint combine(uint left, uint right) { return left + right; }
}

uint linear_group_id(uint3 gid)
{
    return gid.x + gid.y * MAX_GROUPS_X;
}

bool valid_token(uint token)
{
    return token != INVALID && token < gParams.n_tokens;
}

bool method_receiver_param(uint fn_token, uint ordinal)
{
    uint mode = valid_token(fn_token) ? method_decl_receiver_mode[fn_token] : 0u;
    return ordinal == 0u &&
           (mode == METHOD_RECEIVER_SELF || mode == METHOD_RECEIVER_REF_SELF);
}

uint call_param_type_value(uint fn_token, uint ordinal)
{
    if (!valid_token(fn_token) || ordinal >= call_param_count[fn_token])
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
        return method_receiver_param(fn_token, ordinal) ? TY_ARRAY_BASE : 0u;
    uint ty = call_param_row_type[row];
    return ty == 0u && method_receiver_param(fn_token, ordinal) ? TY_ARRAY_BASE : ty;
}

uint function_signature_param_chunk_width(uint fn_token, uint lane)
{
    if (!valid_token(fn_token))
        return 0u;
    uint total = 0u;
    uint count = call_param_count[fn_token];
    uint chunk_size = (count + 255u) / 256u;
    uint begin = min(count, lane * chunk_size);
    uint end = min(count, begin + chunk_size);
    for (uint ordinal = begin; ordinal < end; ordinal += 1u)
        total += call_param_type_value(fn_token, ordinal) == TY_STRING ? 2u : 1u;
    return total;
}

uint function_signature_result_count(uint fn_token)
{
    uint ret = valid_token(fn_token) ? call_return_type[fn_token] : TY_VOID;
    return ret == TY_BOOL || ret == TY_INT || ret == TY_UINT ||
           ret == TY_FLOAT || ret >= TY_ARRAY_BASE
               ? 1u
               : 0u;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 gid: SV_GroupID, uint3 ltid: SV_GroupThreadID)
{
    uint slot = linear_group_id(gid);
    if (slot >= gParams.n_tokens)
        return;
    uint function_count = body_plan[BODY_PLAN_FUNCTION_COUNT];
    if (slot >= function_count)
    {
        if (ltid.x == 0u)
            wasm_type_entry_len_by_slot[slot] = 0u;
        return;
    }
    uint fn_token = wasm_func_token_by_slot[slot];
    uint local_width = function_signature_param_chunk_width(fn_token, ltid.x);
    uint total_width = prefix_scan_inclusive<uint, ParamWidthAdd, 256>(
        ltid.x,
        local_width,
        param_width_prefix);
    if (ltid.x == 255u)
    {
        wasm_type_entry_len_by_slot[slot] =
            1u + 5u + total_width + 1u + function_signature_result_count(fn_token);
    }
}
