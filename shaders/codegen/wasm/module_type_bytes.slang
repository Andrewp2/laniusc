// Scatter dynamic WASM function-type entries with one workgroup per function.
//
// Each lane owns a contiguous parameter chunk. A workgroup scan over chunk ABI
// widths gives every lane its final byte range, keeping per-lane work near
// parameter_count / 256 without allocating a flattened-signature buffer.

import atomics;
import prefix_scan;

struct Params
{
    uint n_tokens;
    uint source_len;
    uint out_capacity;
    uint n_hir_nodes;
};

ConstantBuffer<Params> gParams;
StructuredBuffer<uint> body_status;
StructuredBuffer<uint> body_plan;
StructuredBuffer<uint> wasm_func_token_by_slot;
StructuredBuffer<uint> wasm_type_scan_local_prefix;
StructuredBuffer<uint> wasm_type_scan_block_prefix;
StructuredBuffer<uint> call_return_type;
StructuredBuffer<uint> call_param_count;
StructuredBuffer<uint> call_param_row_count_out;
StructuredBuffer<uint> call_param_row_fn_token;
StructuredBuffer<uint> call_param_row_ordinal;
StructuredBuffer<uint> call_param_row_type;
StructuredBuffer<uint> call_param_row_start;
StructuredBuffer<uint> call_param_row_count;
StructuredBuffer<uint> method_decl_receiver_mode;
StructuredBuffer<uint> status;
RWStructuredBuffer<uint> out_words;

static const uint MAX_GROUPS_X = 65535u;
static const uint TYPE_SCAN_WG_SIZE = 256u;
static const uint TYPE_ENTRIES_LEN = 755u;
static const uint DYNAMIC_TYPE_BASE = 8u + 6u + 5u + TYPE_ENTRIES_LEN;
static const uint BODY_PLAN_FUNCTION_COUNT = 31u;
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
static const uint WASM_VALTYPE_I32 = 0x7fu;
static const uint WASM_VALTYPE_F32 = 0x7du;

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

uint param_abi_width(uint ty)
{
    return ty == TY_STRING ? 2u : 1u;
}

uint result_type(uint fn_token)
{
    uint ret = valid_token(fn_token) ? call_return_type[fn_token] : TY_VOID;
    if (ret == TY_BOOL || ret == TY_INT || ret == TY_UINT || ret >= TY_ARRAY_BASE)
        return WASM_VALTYPE_I32;
    return ret == TY_FLOAT ? WASM_VALTYPE_F32 : 0u;
}

uint leb5_byte(uint value, uint i)
{
    uint byte_value = (value >> (i * 7u)) & 0x7fu;
    return i < 4u ? byte_value | 0x80u : byte_value;
}

void write_byte(uint pos, uint value)
{
    if (pos >= gParams.out_capacity)
        return;
    atomic_u32_or(out_words, pos >> 2u, (value & 0xffu) << ((pos & 3u) * 8u));
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 gid: SV_GroupID, uint3 ltid: SV_GroupThreadID)
{
    if (status[1u] == 1u || status[1u] == 2u || status[1u] == 5u || status[2u] != 0u ||
        body_status[1u] == 0u)
        return;

    uint slot = linear_group_id(gid);
    uint function_count = body_plan[BODY_PLAN_FUNCTION_COUNT];
    if (slot >= function_count || slot >= gParams.n_tokens)
        return;

    uint fn_token = wasm_func_token_by_slot[slot];
    uint count = valid_token(fn_token) ? call_param_count[fn_token] : 0u;
    uint chunk_size = (count + 255u) / 256u;
    uint begin = min(count, ltid.x * chunk_size);
    uint end = min(count, begin + chunk_size);

    uint local_width = 0u;
    for (uint ordinal = begin; ordinal < end; ordinal += 1u)
        local_width += param_abi_width(call_param_type_value(fn_token, ordinal));
    uint inclusive_width = prefix_scan_inclusive<uint, ParamWidthAdd, 256>(
        ltid.x,
        local_width,
        param_width_prefix);
    uint lane_start = inclusive_width - local_width;
    uint entry_start = DYNAMIC_TYPE_BASE + global_exclusive_prefix(
        slot,
        TYPE_SCAN_WG_SIZE,
        wasm_type_scan_local_prefix,
        wasm_type_scan_block_prefix);

    uint cursor = lane_start;
    for (uint ordinal = begin; ordinal < end; ordinal += 1u)
    {
        uint ty = call_param_type_value(fn_token, ordinal);
        uint value_type = ty == TY_FLOAT ? WASM_VALTYPE_F32 : WASM_VALTYPE_I32;
        write_byte(entry_start + 6u + cursor, value_type);
        cursor += 1u;
        if (ty == TY_STRING)
        {
            write_byte(entry_start + 6u + cursor, WASM_VALTYPE_I32);
            cursor += 1u;
        }
    }

    if (ltid.x == 255u)
    {
        uint total_width = inclusive_width;
        write_byte(entry_start, 0x60u);
        for (uint i = 0u; i < 5u; i += 1u)
            write_byte(entry_start + 1u + i, leb5_byte(total_width, i));
        uint ret = result_type(fn_token);
        write_byte(entry_start + 6u + total_width, ret == 0u ? 0u : 1u);
        if (ret != 0u)
            write_byte(entry_start + 7u + total_width, ret);
    }
}
