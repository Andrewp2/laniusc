// Scatter scanned WASM body fragments into the body byte stream.

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

static const uint INVALID = 0xffffffffu;
static const uint BODY_FRAGMENT_LOCAL_DECL_COUNT = 1u;
static const uint BODY_FRAGMENT_PRINT_I64 = 2u;
static const uint BODY_FRAGMENT_RETURN_I32 = 3u;
static const uint WASM_PRINT_I64_FUNC_INDEX = 0u;
static const uint WASM_I32_CONST = 0x41u;
static const uint WASM_I64_CONST = 0x42u;
static const uint WASM_CALL = 0x10u;
static const uint WASM_END = 0x0bu;
static const uint WG_SIZE = 256u;
static const uint BODY_FRAGMENT_MAX_BYTES = 8u;
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

uint return_i32_fragment_byte(uint value, uint byte_i)
{
    if (byte_i == 0u)
        return WASM_I32_CONST;

    uint value_len = i32_sleb_len(value);
    if (byte_i <= value_len)
        return i32_sleb_byte(value, byte_i - 1u);

    return WASM_END;
}

uint fragment_byte(uint4 meta, uint byte_i)
{
    uint kind = meta.x;
    uint value = meta.y;

    if (kind == BODY_FRAGMENT_LOCAL_DECL_COUNT)
        return 0u;
    if (kind == BODY_FRAGMENT_PRINT_I64)
        return print_i64_fragment_byte(value, byte_i);
    if (kind == BODY_FRAGMENT_RETURN_I32)
        return return_i32_fragment_byte(value, byte_i);

    return 0u;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    uint slot_i = linear_dispatch_id(tid);
    uint token_i = slot_i / BODY_FRAGMENT_MAX_BYTES;
    uint byte_i = slot_i - token_i * BODY_FRAGMENT_MAX_BYTES;
    if (token_i >= gScan.n_items || status[2u] != 0u)
        return;

    uint len = body_fragment_len[token_i];
    if (byte_i >= len)
        return;

    uint offset = body_prefix_for_token(token_i);
    uint4 meta = body_fragment_meta[token_i];
    body_words[offset + byte_i] = fragment_byte(meta, byte_i);
}
