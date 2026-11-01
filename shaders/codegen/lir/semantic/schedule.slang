import codegen.lir.semantic.common;
import codegen.lir.semantic.materialize;
import codegen.lir.schedule.common;
import codegen.lowering_ir;
import hir_records;
import gpu_index;

// The first dispatch of `lir.semantic.scatter`: each semantic row's owner
// and execution schedule. Scatter then materializes the row from its owner.
StructuredBuffer<uint> semantic_lir_total;
RWStructuredBuffer<TargetScheduleKey> semantic_lir_schedule;
RWStructuredBuffer<uint> semantic_owner_by_instruction;

static const uint DISPATCH_X_STRIDE = 16776960u;

uint owner_for_semantic_row(uint row, uint hir_count)
{
    // Find the first HIR interval whose exclusive end is greater than `row`.
    // Prefix offsets are monotone even across zero-width syntax nodes, so this
    // remains correct without a retained inverse table.
    uint lo = 0u;
    uint hi = hir_count;
    while (lo < hi)
    {
        uint mid = lo + (hi - lo) / 2u;
        uint end = semantic_lir_offset[mid] + semantic_lir_count[mid];
        if (end <= row) lo = mid + 1u;
        else hi = mid;
    }
    return lo;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint row = linear_dispatch_thread_id_2d(dtid, DISPATCH_X_STRIDE);
    uint hir_count = min(gParams.n_hir_nodes, compact_hir_count[0u]);
    uint total = min(gParams.lir_capacity, semantic_lir_total[0u]);
    if (row >= total || hir_count == 0u) return;
    uint node = owner_for_semantic_row(row, hir_count);
    // Scatter skips a row whose owner is out of range.
    semantic_owner_by_instruction[row] = node;
    if (node >= hir_count || semantic_lir_count[node] == 0u) return;
    uint local_row = row - semantic_lir_offset[node];
    if (local_row >= semantic_lir_count[node]) return;
    // Count owns body admission. Ordinary block syntax has no LIR rows; the
    // sole row it publishes for a function body is its unit fallthrough.
    SemanticLirSchedule schedule;
    if (compact_hir_core[node].kind == 6u)
    {
        HirCore body = compact_hir_core[node];
        schedule.execution_region = body.token_end > body.token_start
            ? body.token_end - 1u : body.token_end;
        schedule.execution_rank = 0xffffffffu;
        schedule.execution_tie = 0xffffffffu;
    }
    else schedule = place_semantic_schedule(node, local_row, hir_count);
    semantic_lir_schedule[row] = target_schedule_pack(schedule, gParams.schedule_packed_bits);
}
