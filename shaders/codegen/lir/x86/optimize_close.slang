// Computes transitive value liveness, one lane per observable root
// (lir/x86/liveness_walk.slang). A lane marks its root live and walks the
// values the root reads. Work is proportional to live nodes and local operand
// arity. Aggregate elements are read by optimize_element_liveness, one lane
// per element, after this pass.

import codegen.lowering_ir;
import codegen.optimization_ir;
import codegen.lir.optimization.execution_owner;
import codegen.lir.x86.liveness_walk;
import atomics;
import gpu_index;

struct Params
{
    uint semantic_capacity;
    uint call_arg_capacity;
    uint aggregate_capacity;
    uint function_capacity;
    uint token_capacity;
    uint reserved0;
    uint reserved1;
    uint reserved2;
};
ConstantBuffer<Params> gParams;
StructuredBuffer<uint> opt_ir_total;
StructuredBuffer<OptIrNodeCore> opt_ir_core;

static const uint DISPATCH_X_STRIDE = 16776960u;

// Values that optimize_close starts a walk from.
bool observable_root(OptIrNodeCore core)
{
    uint op = opt_ir_op(core);
    if ((core.flags & (SEMANTIC_LIR_FLAG_UNSUPPORTED |
                       SEMANTIC_LIR_FLAG_UNSUPPORTED_FOR_ITERABLE)) != 0u)
        return true;
    return op == SEMANTIC_LIR_OP_VALUE_SET ||
        op == SEMANTIC_LIR_OP_STORE || op == SEMANTIC_LIR_OP_PLACE_STORE ||
        op == SEMANTIC_LIR_OP_INDEX_ADDRESS || semantic_lir_is_call(op) ||
        (op >= SEMANTIC_LIR_OP_BLOCK_BEGIN && op <= SEMANTIC_LIR_OP_RETURN) ||
        op == SEMANTIC_LIR_OP_TRAP ||
        op == SEMANTIC_LIR_OP_DROP || op == SEMANTIC_LIR_OP_LOAD ||
        op == SEMANTIC_LIR_OP_AGGREGATE_COPY ||
        op == SEMANTIC_LIR_OP_DIV || op == SEMANTIC_LIR_OP_REM;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint root = linear_dispatch_thread_id_2d(dtid, DISPATCH_X_STRIDE);
    uint total = min(gParams.semantic_capacity, opt_ir_total[0u]);
    if (!opt_ir_node_is_executable(root, total) ||
        !observable_root(opt_ir_core[root])) return;
    // A root another root reads may already be owned by that reader's lane.
    if (atomic_u32_compare_exchange(
            x86_live_by_semantic, root, 0u, X86_SEMANTIC_LIVE) != 0u)
        return;
    x86_liveness_walk_from(root, total, gParams.function_capacity, true);
}
