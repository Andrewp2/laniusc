import codegen.lir.semantic.common;
import codegen.lir.semantic.materialize;
import codegen.lir.schedule.common;
import codegen.lowering_ir;
import gpu_index;

StructuredBuffer<uint> semantic_lir_total;
RWStructuredBuffer<SemanticLirCore> semantic_lir_core;
RWStructuredBuffer<SemanticLirOperands> semantic_lir_operands;
RWStructuredBuffer<uint> semantic_lir_layout_word_offset;
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
    if (node >= hir_count || semantic_lir_count[node] == 0u) return;
    uint first_row = semantic_lir_offset[node];
    uint local_count = semantic_lir_count[node];
    uint local_row = row - first_row;
    if (local_row >= local_count) return;
    SemanticLirSchedule schedule = semantic_schedule(
        node, local_row, local_count, hir_count, compact_hir_core[node],
        compact_hir_links[node], compact_hir_payload[node]);
    semantic_lir_schedule[row] =
        target_schedule_pack(schedule, gParams.schedule_packed_bits);
    semantic_owner_by_instruction[row] = node;
    uint op = semantic_materialized_op(node, local_row, local_count);
    if (op == SEMANTIC_LIR_OP_CALL && semantic_call_kind[node] == 2u)
        op = SEMANTIC_LIR_OP_CALL_INTRINSIC;
    else if (op == SEMANTIC_LIR_OP_CALL && semantic_call_kind[node] == 3u)
        op = SEMANTIC_LIR_OP_CALL_HOST;
    else if (op == SEMANTIC_LIR_OP_CALL && semantic_call_kind[node] == 4u)
        op = SEMANTIC_LIR_OP_CALL_SYMBOL;
    else if (op == SEMANTIC_LIR_OP_CALL && semantic_call_kind[node] == 5u)
        op = SEMANTIC_LIR_OP_AGGREGATE_NEW;
    if (row < gParams.resident_rows)
    {
        SemanticLirRow result =
            materialize_semantic_lir_row(node, local_row, hir_count);
        semantic_lir_core[row] = result.core;
        semantic_lir_operands[row] = result.operands;
        semantic_lir_layout_word_offset[row] = result.layout_word_offset;
    }
}
