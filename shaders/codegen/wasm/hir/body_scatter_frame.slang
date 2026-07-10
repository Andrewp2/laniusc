// Scatter WASM function frame fragments into the body byte stream.

import gpu_index;
import prefix_scan;

struct ScanParams
{
    uint n_items;
    uint n_blocks;
    uint scan_step;
    uint out_capacity;
};

ConstantBuffer<ScanParams> gScan;

StructuredBuffer<uint> body_fragment_len;
StructuredBuffer<uint4> body_fragment_meta;
StructuredBuffer<uint> body_scan_local_prefix;
StructuredBuffer<uint> body_scan_block_prefix;
StructuredBuffer<uint> status;

RWStructuredBuffer<uint> body_words;

static const uint BODY_FRAGMENT_FUNCTION_HEADER = 22u;
static const uint BODY_FRAGMENT_FUNCTION_END = 28u;
static const uint BODY_FRAGMENT_PRINT_I64 = 2u;
static const uint BODY_FRAGMENT_PRINT_LOCAL_I64 = 7u;
static const uint BODY_FRAGMENT_WHILE_CLOSE = 15u;
static const uint BODY_FRAGMENT_IF_ELSE = 17u;
static const uint BODY_FRAGMENT_IF_END = 18u;
static const uint BODY_FRAGMENT_BRANCH = 19u;
static const uint WASM_UNREACHABLE = 0x00u;
static const uint WASM_ELSE = 0x05u;
static const uint WASM_END = 0x0bu;
static const uint WASM_BR = 0x0cu;
static const uint WASM_CALL = 0x10u;
static const uint WASM_LOCAL_GET = 0x20u;
static const uint WASM_I64_CONST = 0x42u;
static const uint WASM_I64_EXTEND_I32_S = 0xacu;
static const uint WASM_VALTYPE_F32 = 0x7du;
static const uint WASM_VALTYPE_I32 = 0x7fu;
static const uint WASM_PRINT_I64_FUNC_INDEX = 0u;
static const uint WG_SIZE = 256u;
static const uint DISPATCH_X_STRIDE = 16776960u;

uint linear_dispatch_id(uint3 tid)
{
    return linear_dispatch_thread_id_2d(tid, DISPATCH_X_STRIDE);
}

uint body_prefix_for_token(uint token_i)
{
    return global_exclusive_prefix(
        token_i,
        WG_SIZE,
        body_scan_local_prefix,
        body_scan_block_prefix);
}

uint u32_leb_len(uint value)
{
    for (uint i = 0u; i < 5u; i += 1u)
    {
        value = value >> 7u;
        if (value == 0u)
            return i + 1u;
    }
    return 5u;
}

uint u32_leb_byte(uint value, uint byte_i)
{
    for (uint i = 0u; i < 5u; i += 1u)
    {
        uint byte_value = value & 0x7fu;
        value = value >> 7u;
        if (value != 0u)
            byte_value |= 0x80u;
        if (i == byte_i)
            return byte_value;
        if (value == 0u)
            return 0u;
    }
    return 0u;
}

uint u32_leb5_byte(uint value, uint byte_i)
{
    uint byte_value = (value >> (byte_i * 7u)) & 0x7fu;
    if (byte_i < 4u)
        byte_value |= 0x80u;
    return byte_value;
}

uint i32_sleb_len(uint value)
{
    int current = int(value);
    for (uint i = 0u; i < 5u; i += 1u)
    {
        uint byte_value = uint(current) & 0x7fu;
        current = current >> 7;
        bool sign_bit_set = (byte_value & 0x40u) != 0u;
        bool done =
            (current == 0 && !sign_bit_set) ||
            (current == -1 && sign_bit_set) ||
            i == 4u;
        if (done)
            return i + 1u;
    }
    return 5u;
}

uint i32_sleb_byte(uint value, uint byte_i)
{
    int current = int(value);
    for (uint i = 0u; i < 5u; i += 1u)
    {
        uint byte_value = uint(current) & 0x7fu;
        current = current >> 7;
        bool sign_bit_set = (byte_value & 0x40u) != 0u;
        bool done =
            (current == 0 && !sign_bit_set) ||
            (current == -1 && sign_bit_set) ||
            i == 4u;
        if (!done)
            byte_value |= 0x80u;
        if (i == byte_i)
            return byte_value;
        if (done)
            return 0u;
    }
    return 0u;
}

uint local_get_byte(uint local_index, uint byte_i)
{
    if (byte_i == 0u)
        return WASM_LOCAL_GET;
    return u32_leb_byte(local_index, byte_i - 1u);
}

uint print_i64_fragment_byte(uint value, uint byte_i)
{
    if (byte_i == 0u)
        return WASM_I64_CONST;
    uint value_len = i32_sleb_len(value);
    if (byte_i <= value_len)
        return i32_sleb_byte(value, byte_i - 1u);
    if (byte_i == value_len + 1u)
        return WASM_CALL;
    return WASM_PRINT_I64_FUNC_INDEX;
}

uint print_local_i64_fragment_byte(uint local_index, uint byte_i)
{
    uint get_len = 1u + u32_leb_len(local_index);
    if (byte_i < get_len)
        return local_get_byte(local_index, byte_i);
    if (byte_i == get_len)
        return WASM_I64_EXTEND_I32_S;
    if (byte_i == get_len + 1u)
        return WASM_CALL;
    return WASM_PRINT_I64_FUNC_INDEX;
}

uint local_decl_fragment_byte(uint local_count, uint byte_i)
{
    if (local_count == 0u)
        return 0u;
    if (byte_i == 0u)
        return 2u;
    uint i32_count = local_count * 2u;
    uint i32_count_len = u32_leb_len(i32_count);
    if (byte_i <= i32_count_len)
        return u32_leb_byte(i32_count, byte_i - 1u);
    if (byte_i == i32_count_len + 1u)
        return WASM_VALTYPE_I32;
    uint second_count_start = i32_count_len + 2u;
    uint f32_count_len = u32_leb_len(local_count);
    if (byte_i < second_count_start + f32_count_len)
        return u32_leb_byte(local_count, byte_i - second_count_start);
    return WASM_VALTYPE_F32;
}

uint function_header_fragment_byte(uint body_size, uint local_count, uint byte_i)
{
    if (byte_i < 5u)
        return u32_leb5_byte(body_size, byte_i);
    return local_decl_fragment_byte(local_count, byte_i - 5u);
}

uint while_close_fragment_byte(uint byte_i)
{
    if (byte_i == 0u)
        return WASM_BR;
    if (byte_i == 1u)
        return 0u;
    return WASM_END;
}

uint branch_fragment_byte(uint depth, uint byte_i)
{
    if (byte_i == 0u)
        return WASM_BR;
    return u32_leb_byte(depth, byte_i - 1u);
}

bool scatter_frame_handles_kind(uint kind)
{
    return kind == BODY_FRAGMENT_FUNCTION_HEADER ||
           kind == BODY_FRAGMENT_FUNCTION_END ||
           kind == BODY_FRAGMENT_PRINT_I64 ||
           kind == BODY_FRAGMENT_PRINT_LOCAL_I64 ||
           kind == BODY_FRAGMENT_WHILE_CLOSE ||
           kind == BODY_FRAGMENT_IF_ELSE ||
           kind == BODY_FRAGMENT_IF_END ||
           kind == BODY_FRAGMENT_BRANCH;
}

uint frame_fragment_byte(uint4 meta, uint fragment_len, uint byte_i)
{
    if (meta.x == BODY_FRAGMENT_FUNCTION_HEADER)
        return function_header_fragment_byte(meta.y, meta.z, byte_i);
    if (meta.x == BODY_FRAGMENT_FUNCTION_END)
        return fragment_len == 1u || byte_i != 0u ? WASM_END : WASM_UNREACHABLE;
    if (meta.x == BODY_FRAGMENT_PRINT_I64)
        return print_i64_fragment_byte(meta.y, byte_i);
    if (meta.x == BODY_FRAGMENT_PRINT_LOCAL_I64)
        return print_local_i64_fragment_byte(meta.y, byte_i);
    if (meta.x == BODY_FRAGMENT_WHILE_CLOSE)
        return while_close_fragment_byte(byte_i);
    if (meta.x == BODY_FRAGMENT_IF_ELSE)
        return WASM_ELSE;
    if (meta.x == BODY_FRAGMENT_IF_END)
        return WASM_END;
    if (meta.x == BODY_FRAGMENT_BRANCH)
        return branch_fragment_byte(meta.y, byte_i);
    return 0u;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    uint body_byte_i = linear_dispatch_id(tid);
    if (body_byte_i >= gScan.out_capacity || status[2u] != 0u)
        return;

    uint lo = 0u;
    uint hi = gScan.n_items;
    for (uint guard = 0u; guard < 32u; guard += 1u)
    {
        if (lo >= hi)
            break;
        uint mid = lo + ((hi - lo) >> 1u);
        uint mid_start = body_prefix_for_token(mid);
        uint mid_end = mid_start + body_fragment_len[mid];
        if (mid_end <= body_byte_i)
            lo = mid + 1u;
        else
            hi = mid;
    }
    uint token_i = lo;
    if (token_i >= gScan.n_items)
        return;
    uint len = body_fragment_len[token_i];
    uint offset = body_prefix_for_token(token_i);
    if (body_byte_i < offset || body_byte_i >= offset + len)
        return;
    uint byte_i = body_byte_i - offset;
    if (byte_i >= len)
        return;

    uint4 meta = body_fragment_meta[token_i];
    if (!scatter_frame_handles_kind(meta.x))
        return;
    body_words[offset + byte_i] = frame_fragment_byte(meta, len, byte_i);
}
