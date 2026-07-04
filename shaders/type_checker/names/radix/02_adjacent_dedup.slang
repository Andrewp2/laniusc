// Paper-aligned name radix foundation.
//
// GPU-only scheduling contract:
// - Dispatch after the final radix scatter has produced sorted_name_order.
// - name_count_in is the GPU-written compact name count from lexeme scatter.
// - Adjacent equal strings are deduplicated by byte equality against the
//   previous sorted span.
// - run_head_mask is then scanned on the GPU and consumed by the id assignment
//   pass.

import gpu_index;
import byte_packing;
import sorted.runs;

struct Params
{
    uint name_count;
    uint source_len;
};

ConstantBuffer<Params> gParams;

struct NameSpan
{
    uint start;
    uint len;
    uint kind;
    uint token_index;
};

StructuredBuffer<NameSpan> name_spans;
StructuredBuffer<uint> name_count_in;
StructuredBuffer<uint> sorted_name_order;
ByteAddressBuffer source_bytes;
ByteAddressBuffer language_symbol_bytes;
RWStructuredBuffer<uint> run_head_mask;
RWStructuredBuffer<uint> adjacent_equal_mask;

static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;
static const uint NAME_KIND_LANGUAGE_SYMBOL = 3u;
static const uint NAME_RADIX_MAX_BYTES = 64u;

uint linear_thread_id(uint3 dtid)
{
    return linear_dispatch_thread_id_2d(dtid, MAX_GROUPS_X * WG_SIZE);
}

uint load_source_byte(uint byte_index)
{
    return byte_address_load_u8_bounded(source_bytes, byte_index, gParams.source_len);
}

uint load_language_symbol_byte(uint byte_index)
{
    return byte_address_load_u8(language_symbol_bytes, byte_index);
}

uint load_name_byte(NameSpan span, uint byte_offset)
{
    uint idx = span.start + byte_offset;
    return span.kind == NAME_KIND_LANGUAGE_SYMBOL ? load_language_symbol_byte(idx)
                                                  : load_source_byte(idx);
}

uint active_name_count()
{
    return min(name_count_in[0], gParams.name_count);
}

bool byte_equal_name_spans(uint left_name_i, uint right_name_i)
{
    uint name_count = active_name_count();
    if (left_name_i >= name_count || right_name_i >= name_count)
        return false;

    NameSpan a = name_spans[left_name_i];
    NameSpan b = name_spans[right_name_i];
    if (a.len != b.len)
        return false;
    // The scatter pass has already recorded ERR_NAME_LIMIT for longer spans.
    // Keep dedup bounded by the same radix limit while the status path fails
    // the compile closed.
    if (a.len > NAME_RADIX_MAX_BYTES)
        return false;

    for (uint i = 0u; i < NAME_RADIX_MAX_BYTES; i += 1u)
    {
        if (i >= a.len)
            continue;

        if (load_name_byte(a, i) != load_name_byte(b, i))
            return false;
    }
    return true;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint i = linear_thread_id(dtid);
    if (i >= gParams.name_count)
        return;

    uint name_count = active_name_count();
    if (i >= name_count)
    {
        adjacent_equal_mask[i] = 0u;
        run_head_mask[i] = 0u;
        return;
    }

    uint equal_prev = 0u;
    if (i > 0u)
    {
        uint prev_name_i = sorted_name_order[i - 1u];
        uint name_i = sorted_name_order[i];
        equal_prev = byte_equal_name_spans(prev_name_i, name_i) ? 1u : 0u;
    }

    uint is_head = sorted_run_head_flag(equal_prev != 0u);
    adjacent_equal_mask[i] = equal_prev;
    run_head_mask[i] = is_head;
}
