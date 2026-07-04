// Scatter aggregate local base-pointer and direct-copy fragments.

import gpu_index;
import prefix_scan;

struct ScanParams
{
    uint n_items;
    uint n_blocks;
    uint scan_step;
    uint out_capacity;
};

struct Params
{
    uint n_tokens;
    uint source_len;
    uint out_capacity;
    uint n_hir_nodes;
};

ConstantBuffer<ScanParams> gScan;
ConstantBuffer<Params> gParams;

StructuredBuffer<uint> body_fragment_len;
StructuredBuffer<uint4> body_fragment_meta;
StructuredBuffer<uint> body_scan_local_prefix;
StructuredBuffer<uint> body_scan_block_prefix;
StructuredBuffer<uint> status;
StructuredBuffer<uint> wasm_agg_local_width_by_token;
StructuredBuffer<uint> wasm_agg_local_base_by_token;
StructuredBuffer<uint> wasm_agg_local_block_prefix;

RWStructuredBuffer<uint> body_words;

static const uint BODY_FRAGMENT_LET_ARRAY_I32 = 30u;
static const uint BODY_FRAGMENT_AGG_DIRECT_COPY_I32 = 43u;
static const uint WASM_I32_CONST = 0x41u;
static const uint WASM_LOCAL_GET = 0x20u;
static const uint WASM_LOCAL_SET = 0x21u;
static const uint WASM_PREFIX_MISC = 0xfcu;
static const uint WASM_MEMORY_COPY = 0x0au;
static const uint WG_SIZE = 256u;
static const uint DISPATCH_X_STRIDE = 16776960u;

uint linear_dispatch_id(uint3 tid)
{
    return linear_dispatch_thread_id_2d(tid, DISPATCH_X_STRIDE);
}

uint body_prefix_for_token(uint token_i)
{
    return global_exclusive_prefix(token_i, WG_SIZE, body_scan_local_prefix, body_scan_block_prefix);
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
    uint shift = byte_i * 7u;
    uint byte_value = (value >> shift) & 0x7fu;
    return (value >> (shift + 7u)) == 0u ? byte_value : (byte_value | 0x80u);
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

uint i32_const_byte(uint value, uint byte_i)
{
    if (byte_i == 0u)
        return WASM_I32_CONST;
    return i32_sleb_byte(value, byte_i - 1u);
}

uint local_get_byte(uint local_index, uint byte_i)
{
    if (byte_i == 0u)
        return WASM_LOCAL_GET;
    return u32_leb_byte(local_index, byte_i - 1u);
}

uint local_set_byte(uint local_index, uint byte_i)
{
    if (byte_i == 0u)
        return WASM_LOCAL_SET;
    return u32_leb_byte(local_index, byte_i - 1u);
}

uint align4(uint value)
{
    return (value + 3u) & ~3u;
}

uint aggregate_data_base()
{
    return align4((gParams.n_tokens + 1u) * 4u + gParams.source_len);
}

uint agg_local_base_slots(uint decl_token)
{
    return global_exclusive_prefix(decl_token, WG_SIZE, wasm_agg_local_base_by_token, wasm_agg_local_block_prefix);
}

uint let_array_i32_fragment_byte(uint local_index, uint base_address, uint byte_i)
{
    uint const_len = 1u + i32_sleb_len(base_address);
    if (byte_i < const_len)
        return i32_const_byte(base_address, byte_i);
    return local_set_byte(local_index, byte_i - const_len);
}

uint aggregate_direct_copy_i32_fragment_byte(uint local_index, uint decl_token, uint byte_i)
{
    uint width = decl_token < gParams.n_tokens ? wasm_agg_local_width_by_token[decl_token] : 0u;
    uint base_address = aggregate_data_base() + agg_local_base_slots(decl_token) * 4u;
    uint base_len = 1u + i32_sleb_len(base_address);
    if (byte_i < base_len)
        return i32_const_byte(base_address, byte_i);

    uint offset = base_len;
    uint local_ref_len = 1u + u32_leb_len(local_index);
    if (byte_i < offset + local_ref_len)
        return local_get_byte(local_index, byte_i - offset);
    offset += local_ref_len;

    uint copy_len_len = 1u + i32_sleb_len(width * 4u);
    if (byte_i < offset + copy_len_len)
        return i32_const_byte(width * 4u, byte_i - offset);
    offset += copy_len_len;

    if (byte_i == offset)
        return WASM_PREFIX_MISC;
    if (byte_i == offset + 1u)
        return WASM_MEMORY_COPY;
    if (byte_i == offset + 2u || byte_i == offset + 3u)
        return 0u;
    offset += 4u;

    if (byte_i < offset + base_len)
        return i32_const_byte(base_address, byte_i - offset);
    offset += base_len;

    return local_set_byte(local_index, byte_i - offset);
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

    uint4 meta = body_fragment_meta[token_i];
    uint byte_i = body_byte_i - offset;
    if (meta.x == BODY_FRAGMENT_LET_ARRAY_I32)
    {
        body_words[offset + byte_i] = let_array_i32_fragment_byte(meta.y, meta.z, byte_i);
        return;
    }
    if (meta.x == BODY_FRAGMENT_AGG_DIRECT_COPY_I32)
    {
        body_words[offset + byte_i] = aggregate_direct_copy_i32_fragment_byte(meta.y, meta.z, byte_i);
        return;
    }
}
