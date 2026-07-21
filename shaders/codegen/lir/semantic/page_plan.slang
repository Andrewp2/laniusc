import gpu_index;

struct Params
{
    uint hir_capacity;
    uint semantic_capacity;
    uint page_rows;
    uint max_pages;
};

struct SemanticLirPage
{
    uint semantic_start;
    uint semantic_count;
    uint hir_start;
    uint hir_count;
};

struct LirDispatchArgs
{
    uint x;
    uint y;
    uint z;
    uint reserved;
};

ConstantBuffer<Params> gParams;
StructuredBuffer<uint> compact_hir_count;
StructuredBuffer<uint> semantic_lir_count;
StructuredBuffer<uint> semantic_lir_offset;
StructuredBuffer<uint> semantic_lir_total;
RWStructuredBuffer<uint> semantic_page_count;
RWByteAddressBuffer semantic_pages;
RWStructuredBuffer<LirDispatchArgs> semantic_page_dispatch;

static const uint DISPATCH_X_STRIDE = 16776960u;

uint first_hir_intersecting(uint logical_row, uint hir_count)
{
    uint low = 0u;
    uint high = hir_count;
    while (low < high)
    {
        uint middle = low + ((high - low) >> 1u);
        uint row_end = semantic_lir_offset[middle] + semantic_lir_count[middle];
        if (row_end <= logical_row)
            low = middle + 1u;
        else
            high = middle;
    }
    return low;
}

uint first_hir_starting_at_or_after(uint logical_row, uint low, uint hir_count)
{
    uint high = hir_count;
    while (low < high)
    {
        uint middle = low + ((high - low) >> 1u);
        if (semantic_lir_offset[middle] < logical_row)
            low = middle + 1u;
        else
            high = middle;
    }
    return low;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint page_id = linear_dispatch_thread_id_2d(dtid, DISPATCH_X_STRIDE);
    if (page_id >= gParams.max_pages) return;

    uint total = min(gParams.semantic_capacity, semantic_lir_total[0u]);
    uint pages = gParams.page_rows == 0u
        ? 0u
        : min(gParams.max_pages, (total + gParams.page_rows - 1u) / gParams.page_rows);
    if (page_id == 0u) semantic_page_count[0u] = pages;

    SemanticLirPage page = SemanticLirPage(0u, 0u, 0u, 0u);
    LirDispatchArgs dispatch = LirDispatchArgs(0u, 1u, 1u, 0u);
    if (page_id < pages)
    {
        uint hir_count = min(gParams.hir_capacity, compact_hir_count[0u]);
        uint semantic_start = page_id * gParams.page_rows;
        uint semantic_end = min(total, semantic_start + gParams.page_rows);
        uint hir_start = first_hir_intersecting(semantic_start, hir_count);
        uint hir_end = first_hir_starting_at_or_after(semantic_end, hir_start, hir_count);
        page.semantic_start = semantic_start;
        page.semantic_count = semantic_end - semantic_start;
        page.hir_start = hir_start;
        page.hir_count = hir_end - hir_start;
        dispatch.x = (page.hir_count + 255u) / 256u;
    }
    uint descriptor_offset = page_id * 256u;
    semantic_pages.Store4(
        descriptor_offset,
        uint4(page.semantic_start, page.semantic_count, page.hir_start, page.hir_count));
    semantic_page_dispatch[page_id] = dispatch;
}
