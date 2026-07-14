// Finalize plain scalar direct-call fragment sizes from scanned ABI argument bytes.

import atomics;
import gpu_index;
import call_relocation;

struct Params
{
    uint n_tokens;
    uint source_len;
    uint out_capacity;
    uint n_hir_nodes;
};

struct ScanParams
{
    uint n_items;
    uint n_blocks;
    uint scan_step;
    uint out_capacity;
};

ConstantBuffer<Params> gParams;
ConstantBuffer<ScanParams> gScan;

StructuredBuffer<uint> hir_token_pos;
StructuredBuffer<uint> enclosing_fn;
StructuredBuffer<uint> wasm_agg_call_arg_count_by_fragment;
StructuredBuffer<uint> wasm_agg_call_arg_count_local_prefix;
StructuredBuffer<uint> wasm_agg_call_arg_count_block_prefix;
StructuredBuffer<uint> wasm_agg_call_arg_len;
StructuredBuffer<uint> wasm_agg_call_arg_byte_local_prefix;
StructuredBuffer<uint> wasm_agg_call_arg_byte_block_prefix;

RWStructuredBuffer<uint> wasm_func_body_len_by_token;
RWStructuredBuffer<uint> body_fragment_len;
RWStructuredBuffer<uint4> body_fragment_meta;
RWStructuredBuffer<uint4> body_fragment_aux;

static const uint INVALID = 0xffffffffu;
static const uint BODY_FRAGMENT_PRINT_DIRECT_CALL_I64 = 23u;
static const uint BODY_FRAGMENT_RETURN_DIRECT_CALL_I32 = 24u;
static const uint BODY_FRAGMENT_LET_DIRECT_CALL_I32 = 25u;
static const uint BODY_FRAGMENT_ASSIGN_DIRECT_CALL_I32 = 26u;
static const uint BODY_FRAGMENT_ASSIGN_COMPOUND_DIRECT_CALL_I32 = 27u;
static const uint ARG_WG_SIZE = 256u;
static const uint DISPATCH_X_STRIDE = 16776960u;

uint linear_dispatch_id(uint3 tid)
{
    return linear_dispatch_thread_id_2d(tid, DISPATCH_X_STRIDE);
}

bool valid_token(uint token)
{
    return token != INVALID && token < gParams.n_tokens;
}

bool valid_node(uint node)
{
    return node != INVALID && node < gParams.n_hir_nodes;
}

uint node_enclosing_fn_token(uint node)
{
    if (!valid_node(node))
        return INVALID;
    uint token = hir_token_pos[node];
    if (!valid_token(token))
        return INVALID;
    uint encoded_fn = enclosing_fn[token];
    return encoded_fn == 0u ? INVALID : encoded_fn - 1u;
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

uint local_index_len(uint local_index)
{
    return 1u + u32_leb_len(local_index);
}

uint wasm_global_exclusive_prefix(
    uint item_i,
    uint workgroup_size,
    StructuredBuffer<uint> local_prefix,
    StructuredBuffer<uint> block_prefix)
{
    uint block_i = item_i / workgroup_size;
    uint prior_blocks = block_i == 0u ? 0u : block_prefix[block_i - 1u];
    return prior_blocks + local_prefix[item_i];
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

uint direct_call_tail_len(uint kind, uint4 meta, uint4 aux)
{
    uint call_tail = 1u + wasm_call_index_len(aux.x);
    if (kind == BODY_FRAGMENT_LET_DIRECT_CALL_I32 ||
        kind == BODY_FRAGMENT_ASSIGN_DIRECT_CALL_I32)
        return call_tail + local_index_len(meta.y);
    if (kind == BODY_FRAGMENT_RETURN_DIRECT_CALL_I32)
        return call_tail + 1u;
    if (kind == BODY_FRAGMENT_PRINT_DIRECT_CALL_I64)
        return call_tail + 3u;
    if (kind == BODY_FRAGMENT_ASSIGN_COMPOUND_DIRECT_CALL_I32)
        return local_index_len(meta.y) + call_tail + 1u + local_index_len(meta.y);
    return 0u;
}

uint direct_fragment_owner_fn(uint kind, uint4 meta)
{
    return kind == BODY_FRAGMENT_PRINT_DIRECT_CALL_I64 ||
           kind == BODY_FRAGMENT_RETURN_DIRECT_CALL_I32
               ? node_enclosing_fn_token(meta.y)
               : node_enclosing_fn_token(meta.z);
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
    if (kind != BODY_FRAGMENT_PRINT_DIRECT_CALL_I64 &&
        kind != BODY_FRAGMENT_RETURN_DIRECT_CALL_I32 &&
        kind != BODY_FRAGMENT_LET_DIRECT_CALL_I32 &&
        kind != BODY_FRAGMENT_ASSIGN_DIRECT_CALL_I32 &&
        kind != BODY_FRAGMENT_ASSIGN_COMPOUND_DIRECT_CALL_I32)
    {
        return;
    }

    uint4 aux = body_fragment_aux[fragment_i];
    uint arg_bytes = arg_bytes_for_fragment(fragment_i);
    uint tail_len = direct_call_tail_len(kind, meta, aux);
    uint old_len = body_fragment_len[fragment_i];
    uint new_len = arg_bytes + tail_len;
    if (new_len == old_len)
        return;

    body_fragment_len[fragment_i] = new_len;
    uint owner_fn = direct_fragment_owner_fn(kind, meta);
    if (valid_token(owner_fn))
        atomic_u32_add(wasm_func_body_len_by_token, owner_fn, new_len - old_len);
}
