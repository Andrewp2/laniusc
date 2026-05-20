// Direct x86_64 instruction byte offsets.
//
// This pass computes an exclusive prefix sum over GPU-produced instruction
// sizes. The current backend fits in one workgroup; later larger instruction
// windows can add the usual block-sum/apply passes.

import gpu_index;
import prefix_scan;

struct ScanParams
{
    uint n_items;
    uint n_blocks;
    uint scan_step;
};

ConstantBuffer<ScanParams> gScan;

StructuredBuffer<uint> x86_inst_size;
StructuredBuffer<uint> size_status;
StructuredBuffer<uint> x86_text_scan_local_prefix;
StructuredBuffer<uint> x86_text_scan_block_prefix;

RWStructuredBuffer<uint> x86_inst_byte_offset;
RWStructuredBuffer<uint> x86_text_len;
RWStructuredBuffer<uint> text_status;

static const uint DISPATCH_X_STRIDE = 16776960u;
static const uint INVALID = 0xffffffffu;
static const uint X86_SIZE_OK = 1u;
static const uint X86_TEXT_OK = 1u;
static const uint X86_ERR_TEXT_OFFSET = 9u;

uint linear_dispatch_id(uint3 tid)
{
    return linear_dispatch_thread_id_2d(tid, DISPATCH_X_STRIDE);
}

uint scanned_prefix_for_inst(uint inst_i)
{
    return global_exclusive_prefix(
        inst_i,
        256u,
        x86_text_scan_local_prefix,
        x86_text_scan_block_prefix);
}

uint saturating_sum_or_oob(uint left, uint right)
{
    uint sum = left + right;
    return sum < left ? 0xffffffffu : sum;
}

uint scanned_total(uint inst_count)
{
    if (inst_count == 0u)
        return 0u;
    uint last_inst = inst_count - 1u;
    return saturating_sum_or_oob(scanned_prefix_for_inst(last_inst), x86_inst_size[last_inst]);
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    uint inst_i = linear_dispatch_id(tid);
    bool size_ok = size_status[0u] == X86_SIZE_OK && size_status[1u] == 0u;
    uint inst_count = size_ok ? size_status[3u] : 0u;
    bool count_ok = inst_count <= gScan.n_items;
    bool ok = size_ok && count_ok;

    if (inst_i == 0u)
    {
        text_status[0u] = ok ? X86_TEXT_OK : 0u;
        text_status[1u] = ok ? 0u : (!size_ok ? size_status[1u] : X86_ERR_TEXT_OFFSET);
        text_status[2u] = ok ? INVALID : (!size_ok ? size_status[2u] : inst_count);
        text_status[3u] = ok ? inst_count : 0u;
        x86_text_len[0u] = ok ? scanned_total(inst_count) : 0u;
    }

    if (!ok || inst_i >= inst_count)
        return;

    x86_inst_byte_offset[inst_i] = scanned_prefix_for_inst(inst_i);
}
