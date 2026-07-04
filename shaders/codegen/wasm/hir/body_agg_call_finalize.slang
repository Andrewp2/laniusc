// Finalize aggregate direct-call fragment sizes from scanned ABI argument bytes.

import atomics;
import body_common;

struct ScanParams
{
    uint n_items;
    uint n_blocks;
    uint scan_step;
    uint out_capacity;
};

ConstantBuffer<ScanParams> gScan;

StructuredBuffer<uint> wasm_agg_call_arg_count_by_fragment;
StructuredBuffer<uint> wasm_agg_call_arg_count_local_prefix;
StructuredBuffer<uint> wasm_agg_call_arg_count_block_prefix;
StructuredBuffer<uint> wasm_agg_call_arg_len;
StructuredBuffer<uint> wasm_agg_call_arg_byte_local_prefix;
StructuredBuffer<uint> wasm_agg_call_arg_byte_block_prefix;

RWStructuredBuffer<uint> body_fragment_len;
RWStructuredBuffer<uint4> body_fragment_meta;
RWStructuredBuffer<uint4> body_fragment_aux;

static const uint BODY_FRAGMENT_LET_AGG_DIRECT_CALL_I32 = 44u;
static const uint BODY_FRAGMENT_RETURN_AGG_DIRECT_CALL_I32 = 45u;
static const uint ARG_WG_SIZE = 256u;

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

uint aggregate_call_tail_len(uint kind, uint4 meta, uint4 aux)
{
    uint call_tail = 1u + u32_leb_len(aux.x);
    if (kind == BODY_FRAGMENT_LET_AGG_DIRECT_CALL_I32)
        return call_tail + local_set_len(meta.y);
    if (kind == BODY_FRAGMENT_RETURN_AGG_DIRECT_CALL_I32)
        return call_tail + 1u;
    if (kind == BODY_FRAGMENT_LET_BINARY_DIRECT_CALL_I32)
    {
        uint expr_len = 0u;
        if (!direct_call_arg_expr_and_len(meta.w, expr_len))
            return 0u;
        return call_tail + expr_len + 1u + local_set_len(meta.y);
    }
    return 0u;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    uint fragment_i = linear_dispatch_id(tid);
    if (fragment_i >= gScan.n_items)
        return;

    uint4 meta = body_fragment_meta[fragment_i];
    uint kind = meta.x;
    if (kind != BODY_FRAGMENT_LET_AGG_DIRECT_CALL_I32 &&
        kind != BODY_FRAGMENT_RETURN_AGG_DIRECT_CALL_I32 &&
        kind != BODY_FRAGMENT_LET_BINARY_DIRECT_CALL_I32)
    {
        return;
    }

    uint4 aux = body_fragment_aux[fragment_i];
    uint arg_bytes = arg_bytes_for_fragment(fragment_i);
    uint tail_len = aggregate_call_tail_len(kind, meta, aux);
    uint old_len = body_fragment_len[fragment_i];
    uint new_len = arg_bytes + tail_len;
    if (new_len == old_len)
        return;

    body_fragment_len[fragment_i] = new_len;
    uint owner_fn = kind == BODY_FRAGMENT_RETURN_AGG_DIRECT_CALL_I32
                        ? node_enclosing_fn_token(meta.y)
                        : node_enclosing_fn_token(meta.z);
    if (valid_token(owner_fn))
        atomic_u32_add(wasm_func_body_len_by_token, owner_fn, new_len - old_len);
}
