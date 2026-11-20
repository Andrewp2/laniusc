import codegen.lir.lowering_ir;
import shared.collectives.program_prefix_scan;
import shared.collectives.step_program;

struct Params
{
    uint semantic_capacity;
    uint target_capacity;
    uint page_count;
    uint page_rows;
};

ConstantBuffer<Params> gParams;
StructuredBuffer<uint> opt_ir_total;
StructuredBuffer<uint> target_lir_count;
RWStructuredBuffer<uint> target_lir_offset;
RWStructuredBuffer<uint> target_lir_total;
RWStructuredBuffer<TargetSemanticPage> target_semantic_pages;

struct Launch { uint groups; uint slot; uint options; uint reserved; };
ConstantBuffer<Launch> program_launch;
RWStructuredBuffer<uint> scan_group_sums;

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

void plan_page(uint page_id, uint semantic_count, uint target_total)
{
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

[shader("compute")]
[numthreads(STEP_PROGRAM_GROUP_LANES, 1, 1)]
void main(uint3 group : SV_GroupID, uint3 local : SV_GroupThreadID)
{
    StepProgram program = step_program_begin(group, local, program_launch.groups, program_launch.slot);
    uint rows = min(gParams.semantic_capacity, opt_ir_total[0u]);
    if (!step_program_prefix_scan(program, rows, target_lir_count,
            target_lir_offset, target_lir_total, scan_group_sums)) return;
    if (!step_barrier(program)) return;

    uint total = min(gParams.target_capacity, target_lir_total[0u]);
    uint live_pages = total / gParams.page_rows + uint(total % gParams.page_rows != 0u);
    for (uint row = program.lane; row < min(live_pages, gParams.page_count); row += program.lanes)
        plan_page(row, rows, total);
    step_program_end(program);
}
