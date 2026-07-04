// Scatter aggregate direct-call argument bytes from dense scanned records.

import body_arg_byte_common;

struct ScanParams
{
    uint n_items;
    uint n_blocks;
    uint scan_step;
    uint out_capacity;
};

ConstantBuffer<ScanParams> gBodyScan;
ConstantBuffer<ScanParams> gArgScan;

StructuredBuffer<uint> status;
StructuredBuffer<uint> body_fragment_len;
StructuredBuffer<uint4> body_fragment_meta;
StructuredBuffer<uint4> body_fragment_aux;
StructuredBuffer<uint> body_scan_local_prefix;
StructuredBuffer<uint> body_scan_block_prefix;
StructuredBuffer<uint> wasm_agg_call_arg_count_by_fragment;
StructuredBuffer<uint> wasm_agg_call_arg_count_local_prefix;
StructuredBuffer<uint> wasm_agg_call_arg_count_block_prefix;
StructuredBuffer<uint> wasm_agg_call_arg_len;
StructuredBuffer<uint4> wasm_agg_call_arg_meta;
StructuredBuffer<uint4> wasm_agg_call_arg_aux;
StructuredBuffer<uint> wasm_agg_call_arg_byte_local_prefix;
StructuredBuffer<uint> wasm_agg_call_arg_byte_block_prefix;

RWStructuredBuffer<uint> body_words;

static const uint BODY_FRAGMENT_LET_AGG_DIRECT_CALL_I32 = 44u;
static const uint BODY_FRAGMENT_RETURN_AGG_DIRECT_CALL_I32 = 45u;
static const uint BODY_FRAGMENT_LET_BINARY_DIRECT_CALL_I32 = 46u;
static const uint ARG_WG_SIZE = 256u;

uint body_prefix_for_fragment(uint fragment_i)
{
    return wasm_global_exclusive_prefix(
        fragment_i,
        ARG_WG_SIZE,
        body_scan_local_prefix,
        body_scan_block_prefix);
}

uint arg_count_prefix_for_fragment(uint fragment_i)
{
    return wasm_global_exclusive_prefix(
        fragment_i,
        ARG_WG_SIZE,
        wasm_agg_call_arg_count_local_prefix,
        wasm_agg_call_arg_count_block_prefix);
}

uint arg_byte_prefix_for_record(uint record_i)
{
    return wasm_global_exclusive_prefix(
        record_i,
        ARG_WG_SIZE,
        wasm_agg_call_arg_byte_local_prefix,
        wasm_agg_call_arg_byte_block_prefix);
}

bool fragment_for_body_byte(uint body_byte_i, out uint fragment_i)
{
    fragment_i = INVALID;
    uint lo = 0u;
    uint hi = gBodyScan.n_items;
    for (uint guard = 0u; guard < 32u; guard += 1u)
    {
        if (lo >= hi)
            break;
        uint mid = lo + ((hi - lo) >> 1u);
        uint start = body_prefix_for_fragment(mid);
        uint end = start + body_fragment_len[mid];
        if (end <= body_byte_i)
            lo = mid + 1u;
        else
            hi = mid;
    }
    if (lo >= gBodyScan.n_items)
        return false;
    uint start = body_prefix_for_fragment(lo);
    uint len = body_fragment_len[lo];
    if (body_byte_i < start || body_byte_i >= start + len)
        return false;
    fragment_i = lo;
    return true;
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

bool record_for_arg_byte(
    uint first_record,
    uint record_count,
    uint arg_global_byte,
    out uint record_i)
{
    record_i = INVALID;
    uint lo = first_record;
    uint hi = first_record + record_count;
    for (uint guard = 0u; guard < 32u; guard += 1u)
    {
        if (lo >= hi)
            break;
        uint mid = lo + ((hi - lo) >> 1u);
        uint start = arg_byte_prefix_for_record(mid);
        uint end = start + wasm_agg_call_arg_len[mid];
        if (end <= arg_global_byte)
            lo = mid + 1u;
        else
            hi = mid;
    }
    if (lo >= first_record + record_count || lo >= gArgScan.n_items)
        return false;
    uint start = arg_byte_prefix_for_record(lo);
    uint len = wasm_agg_call_arg_len[lo];
    if (arg_global_byte < start || arg_global_byte >= start + len)
        return false;
    record_i = lo;
    return true;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    uint body_byte_i = linear_dispatch_id(tid);
    if (body_byte_i >= gBodyScan.out_capacity || status[2u] != 0u)
        return;

    uint fragment_i = INVALID;
    if (!fragment_for_body_byte(body_byte_i, fragment_i))
        return;

    uint4 fragment_meta = body_fragment_meta[fragment_i];
    if (fragment_meta.x != BODY_FRAGMENT_LET_AGG_DIRECT_CALL_I32 &&
        fragment_meta.x != BODY_FRAGMENT_RETURN_AGG_DIRECT_CALL_I32 &&
        fragment_meta.x != BODY_FRAGMENT_LET_BINARY_DIRECT_CALL_I32)
    {
        return;
    }

    uint fragment_start = body_prefix_for_fragment(fragment_i);
    uint byte_i = body_byte_i - fragment_start;
    uint arg_bytes = arg_bytes_for_fragment(fragment_i);
    if (byte_i >= arg_bytes)
        return;

    uint first_record = arg_count_prefix_for_fragment(fragment_i);
    uint record_count = wasm_agg_call_arg_count_by_fragment[fragment_i];
    uint arg_global_byte = arg_byte_prefix_for_record(first_record) + byte_i;
    uint record_i = INVALID;
    if (!record_for_arg_byte(first_record, record_count, arg_global_byte, record_i))
        return;

    uint record_start = arg_byte_prefix_for_record(record_i);
    uint4 arg_meta = wasm_agg_call_arg_meta[record_i];
    uint4 arg_aux = wasm_agg_call_arg_aux[record_i];
    body_words[body_byte_i] =
        direct_call_abi_arg_byte(
            arg_meta.z,
            arg_aux.x,
            arg_meta.w,
            arg_global_byte - record_start);
}
