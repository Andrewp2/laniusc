// Scatter structural bytes for scalar binary direct-call fragments. Call
// argument bytes are owned by the argument scatter passes, and the non-call
// operand is owned by body_scatter_conversion_expr's parallel expression
// forest. This pass deliberately leaves both ranges untouched.

import gpu_index;
import prefix_scan;
import call_relocation;

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
StructuredBuffer<uint4> body_fragment_aux;
StructuredBuffer<uint> body_scan_local_prefix;
StructuredBuffer<uint> body_scan_block_prefix;
StructuredBuffer<uint> status;
StructuredBuffer<uint> wasm_agg_call_arg_count_by_fragment;
StructuredBuffer<uint> wasm_agg_call_arg_count_local_prefix;
StructuredBuffer<uint> wasm_agg_call_arg_count_block_prefix;
StructuredBuffer<uint> wasm_agg_call_arg_len;
StructuredBuffer<uint> wasm_agg_call_arg_byte_local_prefix;
StructuredBuffer<uint> wasm_agg_call_arg_byte_block_prefix;

RWStructuredBuffer<uint> body_words;

static const uint INVALID = 0xffffffffu;
static const uint BODY_FRAGMENT_LET_BINARY_DIRECT_CALL_I32 = 46u;
static const uint BODY_FRAGMENT_RETURN_BINARY_DIRECT_CALL_I32 = 29u;
static const uint WASM_LOCAL_SET = 0x21u;
static const uint WASM_CALL = 0x10u;
static const uint WASM_RETURN = 0x0fu;
static const uint WG_SIZE = 256u;
static const uint DISPATCH_X_STRIDE = 16776960u;

uint linear_dispatch_id(uint3 tid)
{
    return linear_dispatch_thread_id_2d(tid, DISPATCH_X_STRIDE);
}

uint body_prefix_for_fragment(uint fragment_i)
{
    return global_exclusive_prefix(
        fragment_i,
        WG_SIZE,
        body_scan_local_prefix,
        body_scan_block_prefix);
}

uint arg_count_prefix_for_fragment(uint fragment_i)
{
    return global_exclusive_prefix(
        fragment_i,
        WG_SIZE,
        wasm_agg_call_arg_count_local_prefix,
        wasm_agg_call_arg_count_block_prefix);
}

uint arg_byte_prefix_for_record(uint record_i)
{
    return global_exclusive_prefix(
        record_i,
        WG_SIZE,
        wasm_agg_call_arg_byte_local_prefix,
        wasm_agg_call_arg_byte_block_prefix);
}

uint arg_bytes_for_fragment(uint fragment_i)
{
    uint count = wasm_agg_call_arg_count_by_fragment[fragment_i];
    if (count == 0u)
        return 0u;
    uint first_record = arg_count_prefix_for_fragment(fragment_i);
    uint last_record = first_record + count - 1u;
    return arg_byte_prefix_for_record(last_record) +
           wasm_agg_call_arg_len[last_record] -
           arg_byte_prefix_for_record(first_record);
}

uint u32_leb_len(uint value)
{
    for (uint i = 0u; i < 5u; i += 1u)
    {
        value >>= 7u;
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
        value >>= 7u;
        if (value != 0u)
            byte_value |= 0x80u;
        if (i == byte_i)
            return byte_value;
        if (value == 0u)
            return 0u;
    }
    return 0u;
}

uint local_set_byte(uint local_index, uint byte_i)
{
    return byte_i == 0u ? WASM_LOCAL_SET : u32_leb_byte(local_index, byte_i - 1u);
}

bool fragment_for_body_byte(uint body_byte_i, out uint fragment_i)
{
    fragment_i = INVALID;
    uint lo = 0u;
    uint hi = gScan.n_items;
    for (uint guard = 0u; guard < 32u && lo < hi; guard += 1u)
    {
        uint mid = lo + ((hi - lo) >> 1u);
        uint start = body_prefix_for_fragment(mid);
        uint end = start + body_fragment_len[mid];
        if (end <= body_byte_i)
            lo = mid + 1u;
        else
            hi = mid;
    }
    if (lo >= gScan.n_items)
        return false;
    uint start = body_prefix_for_fragment(lo);
    uint len = body_fragment_len[lo];
    if (body_byte_i < start || body_byte_i >= start + len)
        return false;
    fragment_i = lo;
    return true;
}

bool fragment_layout(
    uint fragment_i,
    uint4 meta,
    uint4 aux,
    out uint arg_start,
    out uint arg_len,
    out uint expr_start,
    out uint expr_len)
{
    arg_start = 0u;
    arg_len = arg_bytes_for_fragment(fragment_i);
    expr_start = 0u;
    expr_len = 0u;

    uint len = body_fragment_len[fragment_i];
    uint call_tail_len = 1u + wasm_call_index_len(aux.x);
    uint fixed_len = arg_len + call_tail_len + 2u;
    if (meta.x == BODY_FRAGMENT_LET_BINARY_DIRECT_CALL_I32)
    {
        uint store_len = 1u + u32_leb_len(meta.y);
        fixed_len = arg_len + call_tail_len + 1u + store_len;
        if (fixed_len > len)
            return false;
        expr_len = len - fixed_len;
        expr_start = arg_len + call_tail_len;
        return expr_len != 0u;
    }

    if (fixed_len > len)
        return false;
    expr_len = len - fixed_len;
    bool call_on_right = (meta.w >> 8u) != 0u;
    expr_start = call_on_right ? 0u : arg_len + call_tail_len;
    arg_start = call_on_right ? expr_len : 0u;
    return expr_len != 0u;
}

uint structural_byte(
    uint4 meta,
    uint4 aux,
    uint byte_i,
    uint arg_start,
    uint arg_len,
    uint expr_start,
    uint expr_len)
{
    uint call_start = meta.x == BODY_FRAGMENT_RETURN_BINARY_DIRECT_CALL_I32 &&
                              (meta.w >> 8u) != 0u
                          ? arg_start + arg_len
                          : arg_len;
    uint call_tail_len = 1u + wasm_call_index_len(aux.x);
    if (byte_i == call_start)
        return WASM_CALL;
    if (byte_i < call_start + call_tail_len)
        return wasm_call_index_byte(aux.x, byte_i - call_start - 1u);

    uint op_i = expr_start + expr_len;
    if (meta.x == BODY_FRAGMENT_RETURN_BINARY_DIRECT_CALL_I32 &&
        (meta.w >> 8u) != 0u)
    {
        op_i = call_start + call_tail_len;
    }
    if (byte_i == op_i)
        return meta.x == BODY_FRAGMENT_LET_BINARY_DIRECT_CALL_I32
                   ? aux.w & 0xffu
                   : meta.w & 0xffu;
    if (meta.x == BODY_FRAGMENT_RETURN_BINARY_DIRECT_CALL_I32)
        return WASM_RETURN;
    return local_set_byte(meta.y, byte_i - op_i - 1u);
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    uint body_byte_i = linear_dispatch_id(tid);
    if (body_byte_i >= gScan.out_capacity || status[2u] != 0u)
        return;

    uint fragment_i = INVALID;
    if (!fragment_for_body_byte(body_byte_i, fragment_i))
        return;
    uint4 meta = body_fragment_meta[fragment_i];
    if (meta.x != BODY_FRAGMENT_LET_BINARY_DIRECT_CALL_I32 &&
        meta.x != BODY_FRAGMENT_RETURN_BINARY_DIRECT_CALL_I32)
    {
        return;
    }

    uint arg_start = 0u;
    uint arg_len = 0u;
    uint expr_start = 0u;
    uint expr_len = 0u;
    if (!fragment_layout(
            fragment_i,
            meta,
            body_fragment_aux[fragment_i],
            arg_start,
            arg_len,
            expr_start,
            expr_len))
    {
        return;
    }

    uint offset = body_prefix_for_fragment(fragment_i);
    uint byte_i = body_byte_i - offset;
    if ((byte_i >= arg_start && byte_i < arg_start + arg_len) ||
        (byte_i >= expr_start && byte_i < expr_start + expr_len))
    {
        return;
    }
    body_words[body_byte_i] = structural_byte(
        meta,
        body_fragment_aux[fragment_i],
        byte_i,
        arg_start,
        arg_len,
        expr_start,
        expr_len);
}
