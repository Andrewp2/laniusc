// Direct x86_64 instruction byte offsets.
//
// This pass computes an exclusive prefix sum over GPU-produced instruction
// sizes. The current backend fits in one workgroup; later larger instruction
// windows can add the usual block-sum/apply passes.

struct Params
{
    uint n_tokens;
    uint source_len;
    uint out_capacity;
    uint n_hir_nodes;
};

ConstantBuffer<Params> gParams;

StructuredBuffer<uint> x86_inst_size;
StructuredBuffer<uint> size_status;

RWStructuredBuffer<uint> x86_inst_byte_offset;
RWStructuredBuffer<uint> x86_text_len;
RWStructuredBuffer<uint> text_status;

static const uint DISPATCH_X_STRIDE = 16776960u;
static const uint INVALID = 0xffffffffu;
static const uint MAX_TEXT_OFFSET_LANES = 256u;
static const uint X86_SIZE_OK = 1u;
static const uint X86_TEXT_OK = 1u;
static const uint X86_ERR_TEXT_OFFSET = 9u;

groupshared uint scan_values[256];

uint linear_dispatch_id(uint3 tid)
{
    return tid.x + tid.y * DISPATCH_X_STRIDE;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    uint inst_i = linear_dispatch_id(tid);
    uint lane = tid.x;
    bool size_ok = size_status[0u] == X86_SIZE_OK && size_status[1u] == 0u;
    uint inst_count = size_ok ? size_status[3u] : 0u;
    bool count_ok = inst_count <= MAX_TEXT_OFFSET_LANES;
    bool ok = size_ok && count_ok;

    uint own_size = ok && lane < inst_count ? x86_inst_size[lane] : 0u;
    scan_values[lane] = own_size;
    GroupMemoryBarrierWithGroupSync();

    [loop]
    for (uint step = 1u; step < MAX_TEXT_OFFSET_LANES; step <<= 1u)
    {
        uint addend = lane >= step ? scan_values[lane - step] : 0u;
        GroupMemoryBarrierWithGroupSync();
        scan_values[lane] += addend;
        GroupMemoryBarrierWithGroupSync();
    }

    if (inst_i == 0u)
    {
        text_status[0u] = ok ? X86_TEXT_OK : 0u;
        text_status[1u] = ok ? 0u : (!size_ok ? size_status[1u] : X86_ERR_TEXT_OFFSET);
        text_status[2u] = ok ? INVALID : (!size_ok ? size_status[2u] : inst_count);
        text_status[3u] = ok ? inst_count : 0u;
    }

    if (!ok || inst_i >= inst_count)
        return;

    uint inclusive = scan_values[lane];
    x86_inst_byte_offset[inst_i] = inclusive - own_size;
    if (inst_i + 1u == inst_count)
        x86_text_len[0u] = inclusive;
}
