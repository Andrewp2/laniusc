// Scatter aggregate-backed range for-loop open fragments.

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
StructuredBuffer<uint4> body_fragment_aux;
StructuredBuffer<uint> body_scan_local_prefix;
StructuredBuffer<uint> body_scan_block_prefix;
StructuredBuffer<uint> status;

RWStructuredBuffer<uint> body_words;

static const uint INVALID = 0xffffffffu;
static const uint BODY_FRAGMENT_FOR_OPEN_AGG_RANGE_I32 = 49u;
static const uint BODY_FRAGMENT_FOR_OPEN_ARRAY_I32 = 55u;
static const uint WASM_I32_CONST = 0x41u;
static const uint WASM_I32_LOAD = 0x28u;
static const uint WASM_BLOCK = 0x02u;
static const uint WASM_LOOP = 0x03u;
static const uint WASM_LOCAL_GET = 0x20u;
static const uint WASM_LOCAL_SET = 0x21u;
static const uint WASM_BR_IF = 0x0du;
static const uint WASM_BLOCK_TYPE_EMPTY = 0x40u;
static const uint WASM_I32_GE_S = 0x4eu;
static const uint WASM_I32_ADD = 0x6au;
static const uint WASM_I32_MUL = 0x6cu;
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

uint local_get_len(uint local_index)
{
    return 1u + u32_leb_len(local_index);
}

uint local_set_len(uint local_index)
{
    return 1u + u32_leb_len(local_index);
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

uint memarg_load_byte(uint offset, uint byte_i)
{
    if (byte_i == 0u)
        return WASM_I32_LOAD;
    if (byte_i == 1u)
        return 2u;
    return u32_leb_byte(offset, byte_i - 2u);
}

uint memarg_len(uint offset)
{
    return 2u + u32_leb_len(offset);
}

uint range_bound_byte(uint range_local, uint field_index, uint byte_i)
{
    uint get_len = local_get_len(range_local);
    if (byte_i < get_len)
        return local_get_byte(range_local, byte_i);
    return memarg_load_byte(field_index * 4u, byte_i - get_len);
}

uint for_open_agg_range_i32_fragment_byte(
    uint binding_local,
    uint range_local,
    uint end_local,
    uint byte_i)
{
    uint start_len = local_get_len(range_local) + memarg_len(0u);
    if (byte_i < start_len)
        return range_bound_byte(range_local, 0u, byte_i);

    uint binding_set_start = start_len;
    uint binding_set_len = local_set_len(binding_local);
    if (byte_i < binding_set_start + binding_set_len)
        return local_set_byte(binding_local, byte_i - binding_set_start);

    uint end_start = binding_set_start + binding_set_len;
    uint end_len = local_get_len(range_local) + memarg_len(4u);
    if (byte_i < end_start + end_len)
        return range_bound_byte(range_local, 1u, byte_i - end_start);

    uint end_set_start = end_start + end_len;
    uint end_set_len = local_set_len(end_local);
    if (byte_i < end_set_start + end_set_len)
        return local_set_byte(end_local, byte_i - end_set_start);

    uint block_start = end_set_start + end_set_len;
    if (byte_i == block_start + 0u)
        return WASM_BLOCK;
    if (byte_i == block_start + 1u)
        return WASM_BLOCK_TYPE_EMPTY;
    if (byte_i == block_start + 2u)
        return WASM_LOOP;
    if (byte_i == block_start + 3u)
        return WASM_BLOCK_TYPE_EMPTY;

    uint condition_start = block_start + 4u;
    uint binding_get_len = local_get_len(binding_local);
    if (byte_i < condition_start + binding_get_len)
        return local_get_byte(binding_local, byte_i - condition_start);

    uint end_get_start = condition_start + binding_get_len;
    uint end_get_len = local_get_len(end_local);
    if (byte_i < end_get_start + end_get_len)
        return local_get_byte(end_local, byte_i - end_get_start);

    uint ge_i = end_get_start + end_get_len;
    if (byte_i == ge_i)
        return WASM_I32_GE_S;
    if (byte_i == ge_i + 1u)
        return WASM_BR_IF;
    if (byte_i == ge_i + 2u)
        return 1u;
    if (byte_i == ge_i + 3u)
        return WASM_BLOCK;
    return WASM_BLOCK_TYPE_EMPTY;
}

uint for_open_array_i32_fragment_byte(
    uint binding_local,
    uint array_local,
    uint index_local,
    uint array_len,
    uint byte_i)
{
    if (byte_i < 2u)
        return i32_const_byte(0u, byte_i);
    uint index_set_start = 2u;
    uint index_set_len = local_set_len(index_local);
    if (byte_i < index_set_start + index_set_len)
        return local_set_byte(index_local, byte_i - index_set_start);

    uint block_start = index_set_start + index_set_len;
    if (byte_i == block_start + 0u)
        return WASM_BLOCK;
    if (byte_i == block_start + 1u)
        return WASM_BLOCK_TYPE_EMPTY;
    if (byte_i == block_start + 2u)
        return WASM_LOOP;
    if (byte_i == block_start + 3u)
        return WASM_BLOCK_TYPE_EMPTY;

    uint condition_start = block_start + 4u;
    uint index_get_len = local_get_len(index_local);
    if (byte_i < condition_start + index_get_len)
        return local_get_byte(index_local, byte_i - condition_start);
    uint length_start = condition_start + index_get_len;
    uint length_len = 1u + i32_sleb_len(array_len);
    if (byte_i < length_start + length_len)
        return i32_const_byte(array_len, byte_i - length_start);
    uint ge_i = length_start + length_len;
    if (byte_i == ge_i)
        return WASM_I32_GE_S;
    if (byte_i == ge_i + 1u)
        return WASM_BR_IF;
    if (byte_i == ge_i + 2u)
        return 1u;

    uint load_start = ge_i + 3u;
    uint array_get_len = local_get_len(array_local);
    if (byte_i < load_start + array_get_len)
        return local_get_byte(array_local, byte_i - load_start);
    uint load_index_start = load_start + array_get_len;
    if (byte_i < load_index_start + index_get_len)
        return local_get_byte(index_local, byte_i - load_index_start);
    uint scale_start = load_index_start + index_get_len;
    if (byte_i < scale_start + 2u)
        return i32_const_byte(4u, byte_i - scale_start);
    if (byte_i == scale_start + 2u)
        return WASM_I32_MUL;
    if (byte_i == scale_start + 3u)
        return WASM_I32_ADD;
    uint load_i = scale_start + 4u;
    if (byte_i < load_i + memarg_len(0u))
        return memarg_load_byte(0u, byte_i - load_i);
    uint binding_set_start = load_i + memarg_len(0u);
    uint binding_set_len = local_set_len(binding_local);
    if (byte_i < binding_set_start + binding_set_len)
        return local_set_byte(binding_local, byte_i - binding_set_start);
    uint inner_block_start = binding_set_start + binding_set_len;
    if (byte_i == inner_block_start)
        return WASM_BLOCK;
    return WASM_BLOCK_TYPE_EMPTY;
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
    if (meta.x == BODY_FRAGMENT_FOR_OPEN_AGG_RANGE_I32)
    {
        body_words[offset + byte_i] =
            for_open_agg_range_i32_fragment_byte(meta.y, meta.z, meta.w, byte_i);
        return;
    }
    if (meta.x == BODY_FRAGMENT_FOR_OPEN_ARRAY_I32)
    {
        body_words[offset + byte_i] = for_open_array_i32_fragment_byte(
            meta.y,
            meta.z,
            meta.w,
            body_fragment_aux[token_i].x,
            byte_i);
    }
}
