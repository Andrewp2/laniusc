import codegen.lir.semantic.common;
import codegen.lir.semantic.materialize;
import codegen.lowering_ir;
import gpu_index;

RWStructuredBuffer<SemanticLirCore> semantic_lir_core;
RWStructuredBuffer<SemanticLirOperands> semantic_lir_operands;
RWStructuredBuffer<SemanticLirSchedule> semantic_lir_schedule;
RWStructuredBuffer<uint> semantic_owner_by_instruction;
RWStructuredBuffer<uint> semantic_op_by_instruction;

static const uint DISPATCH_X_STRIDE = 16776960u;

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint node = linear_dispatch_thread_id_2d(dtid, DISPATCH_X_STRIDE);
    uint hir_count = min(gParams.n_hir_nodes, compact_hir_count[0u]);
    if (node >= hir_count || semantic_lir_count[node] == 0u) return;
    uint first_row = semantic_lir_offset[node];
    uint local_count = semantic_lir_count[node];
    for (uint local_row = 0u; local_row < local_count; ++local_row)
    {
        uint row = first_row + local_row;
        if (row >= gParams.lir_capacity) continue;
        semantic_lir_schedule[row] = semantic_schedule(
            node,
            local_row,
            local_count,
            hir_count,
            compact_hir_core[node],
            compact_hir_links[node],
            compact_hir_payload[node]);
        semantic_owner_by_instruction[row] = node;
        uint op = semantic_lir_local_op(
            compact_hir_core[node],
            compact_hir_payload[node],
            local_row,
            local_count);
        if (op == SEMANTIC_LIR_OP_CALL && semantic_call_kind[node] == 2u)
            op = SEMANTIC_LIR_OP_CALL_INTRINSIC;
        else if (op == SEMANTIC_LIR_OP_CALL && semantic_call_kind[node] == 3u)
            op = SEMANTIC_LIR_OP_CALL_HOST;
        else if (op == SEMANTIC_LIR_OP_CALL && semantic_call_kind[node] == 4u)
            op = SEMANTIC_LIR_OP_CALL_SYMBOL;
        semantic_op_by_instruction[row] = op;
        if (row < gParams.reserved1)
        {
            SemanticLirRow result =
                materialize_semantic_lir_row(node, local_row, hir_count);
            semantic_lir_core[row] = result.core;
            semantic_lir_operands[row] = result.operands;
        }
    }
}
