import codegen.lir.semantic.common;
import codegen.lir.semantic.materialize;
import codegen.lir.schedule.common;
import codegen.lowering_ir;
import hir_records;
import gpu_index;

StructuredBuffer<uint> semantic_lir_total;
RWStructuredBuffer<SemanticLirCore> semantic_lir_core;
RWStructuredBuffer<SemanticLirOperands> semantic_lir_operands;
RWStructuredBuffer<uint> semantic_lir_layout_word_offset;
// The schedule dispatch before this one publishes each row's owner.
StructuredBuffer<uint> semantic_owner_by_instruction;

static const uint DISPATCH_X_STRIDE = 16776960u;

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint row = linear_dispatch_thread_id_2d(dtid, DISPATCH_X_STRIDE);
    uint hir_count = min(gParams.n_hir_nodes, compact_hir_count[0u]);
    uint total = min(gParams.lir_capacity, semantic_lir_total[0u]);
    if (row >= total || hir_count == 0u) return;
    uint node = semantic_owner_by_instruction[row];
    if (node >= hir_count || semantic_lir_count[node] == 0u) return;
    uint local_row = row - semantic_lir_offset[node];
    if (local_row >= semantic_lir_count[node]) return;
    bool body_return = compact_hir_core[node].kind == 6u;
    if (row < gParams.resident_rows)
    {
        SemanticLirRow result;
        if (body_return)
        {
            result.core.type_id = 1u;
            result.core.type_ref_payload = 1u;
            result.core.value_word_count = 0u;
            result.core.flags = (1u << SEMANTIC_LIR_TYPE_REF_TAG_SHIFT) |
                (SEMANTIC_LIR_OP_RETURN << SEMANTIC_LIR_OP_SHIFT);
            result.operands.result = LIR_INVALID;
            result.operands.a = LIR_INVALID;
            result.operands.b = LIR_INVALID;
            result.operands.c = LIR_INVALID;
            result.layout_word_offset = LIR_INVALID;
        }
        else result = materialize_semantic_lir_row(node, local_row, hir_count);
        semantic_lir_core[row] = result.core;
        semantic_lir_operands[row] = result.operands;
        semantic_lir_layout_word_offset[row] = result.layout_word_offset;
    }
}
