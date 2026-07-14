// Pack dynamic type entries and function bodies into independent object sections.

import byte_packing;
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

StructuredBuffer<uint> module_words;
StructuredBuffer<uint> body_words;
StructuredBuffer<uint> body_plan;
StructuredBuffer<uint> wasm_type_scan_block_prefix;
RWStructuredBuffer<uint> object_type_words;
RWStructuredBuffer<uint> object_body_words;

static const uint DISPATCH_X_STRIDE = 16776960u;
static const uint DYNAMIC_TYPE_BASE = 774u;
static const uint BODY_PLAN_BODY_LEN = 3u;

uint linear_dispatch_id(uint3 tid)
{
    return linear_dispatch_thread_id_2d(tid, DISPATCH_X_STRIDE);
}

uint module_byte(uint pos)
{
    uint word = module_words[pos >> 2u];
    return (word >> ((pos & 3u) * 8u)) & 0xffu;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    uint word_i = linear_dispatch_id(tid);
    uint pos = word_i * 4u;
    uint type_len = inclusive_scan_total(gScan.n_blocks, wasm_type_scan_block_prefix);
    uint body_len = body_plan[BODY_PLAN_BODY_LEN];
    if (pos < type_len)
    {
        object_type_words[word_i] = pack_u8x4(
            pos + 0u < type_len ? module_byte(DYNAMIC_TYPE_BASE + pos + 0u) : 0u,
            pos + 1u < type_len ? module_byte(DYNAMIC_TYPE_BASE + pos + 1u) : 0u,
            pos + 2u < type_len ? module_byte(DYNAMIC_TYPE_BASE + pos + 2u) : 0u,
            pos + 3u < type_len ? module_byte(DYNAMIC_TYPE_BASE + pos + 3u) : 0u);
    }
    if (pos < body_len)
    {
        object_body_words[word_i] = pack_u8x4(
            pos + 0u < body_len ? body_words[pos + 0u] & 0xffu : 0u,
            pos + 1u < body_len ? body_words[pos + 1u] & 0xffu : 0u,
            pos + 2u < body_len ? body_words[pos + 2u] & 0xffu : 0u,
            pos + 3u < body_len ? body_words[pos + 3u] & 0xffu : 0u);
    }
}
