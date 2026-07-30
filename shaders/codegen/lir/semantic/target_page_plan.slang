import codegen.lowering_ir;
import gpu_index;

struct Params
{
    uint semantic_capacity;
    uint target_capacity;
    uint page_count;
    uint page_rows;
};

ConstantBuffer<Params> gParams;
StructuredBuffer<uint> semantic_lir_total;
StructuredBuffer<uint> target_lir_offset;
StructuredBuffer<uint> target_lir_total;
RWStructuredBuffer<TargetSemanticPage> target_semantic_pages;

static const uint DISPATCH_X_STRIDE = 16776960u;

uint semantic_owner(uint target_row, uint semantic_count)
{
    uint lo = 0u;
    uint hi = semantic_count;
    while (lo + 1u < hi)
    {
        uint mid = lo + (hi - lo) / 2u;
        if (target_lir_offset[mid] <= target_row) lo = mid;
        else hi = mid;
    }
    return lo;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint page_id = linear_dispatch_thread_id_2d(dtid, DISPATCH_X_STRIDE);
    if (page_id >= gParams.page_count) return;

    uint semantic_count = min(gParams.semantic_capacity, semantic_lir_total[0u]);
    uint target_total = min(gParams.target_capacity, target_lir_total[0u]);
    uint target_start = page_id * gParams.page_rows;
    uint target_count = target_start < target_total
        ? min(gParams.page_rows, target_total - target_start) : 0u;

    TargetSemanticPage page;
    page.target_start = target_start;
    page.target_count = target_count;
    if (target_count == 0u || semantic_count == 0u)
    {
        page.semantic_start = 0u;
        page.semantic_count = 0u;
    }
    else
    {
        uint first = semantic_owner(target_start, semantic_count);
        uint last = semantic_owner(target_start + target_count - 1u, semantic_count);
        page.semantic_start = first;
        page.semantic_count = last - first + 1u;
    }
    target_semantic_pages[page_id] = page;
}
