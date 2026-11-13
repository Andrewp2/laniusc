// Computes transitive value liveness, one lane per observable root. A lane
// marks its root live and walks the values the root reads, depth first. The
// lane that marks a value live owns it and walks its dependencies in turn, so
// each live value is expanded exactly once and no lane waits on another. Work
// is proportional to live nodes and local operand arity.
//
// The walk keeps no stack: a value records the reader that claimed it and the
// reader's next dependency, and the lane returns along that record.

import codegen.lowering_ir;
import codegen.optimization_ir;
import codegen.lir.optimization.execution_owner;
import codegen.lir.x86.liveness_dependencies;
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
StructuredBuffer<uint> opt_ir_source_hir;
StructuredBuffer<uint> semantic_function_id_by_hir;
StructuredBuffer<SemanticLirCallArg> semantic_lir_call_args;
StructuredBuffer<SemanticLirAggregateElement>
    semantic_lir_aggregate_elements;
StructuredBuffer<X86LivenessDependencies> x86_liveness_dependencies;
RWStructuredBuffer<uint> x86_last_use_by_semantic;
RWStructuredBuffer<uint> x86_live_by_semantic;
// Two words per value: the reader that claimed it, then that reader's next
// dependency ordinal.
RWStructuredBuffer<uint> x86_liveness_walk;

static const uint INVALID = 0xffffffffu;
static const uint DISPATCH_X_STRIDE = 16776960u;

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

uint function_for_node(uint row)
{
    uint owner = opt_ir_source_hir[row];
    return owner < gParams.function_capacity
        ? semantic_function_id_by_hir[owner] : INVALID;
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

    uint node = root;
    uint ordinal = 0u;
    // A lane enters each value it owns once and returns to it once per
    // dependency it claimed there.
    uint budget = 2u * total + 2u;
    for (uint step = 0u; step < budget; ++step)
    {
        X86LivenessDependencies deps = x86_liveness_dependencies[node];
        uint count = deps.fixed_count + deps.variable_count;
        uint claimed = INVALID;
        while (ordinal < count && claimed == INVALID)
        {
            uint value = INVALID;
            if (ordinal < deps.fixed_count)
                value = ordinal == 0u ? deps.fixed0
                    : ordinal == 1u ? deps.fixed1 : deps.fixed2;
            else
            {
                uint index = deps.variable_start + (ordinal - deps.fixed_count);
                if (deps.variable_kind == VARIABLE_CALL_ARGUMENTS)
                {
                    SemanticLirCallArg argument = semantic_lir_call_args[index];
                    if (argument.call_instruction == node)
                        value = argument.value_instruction;
                }
                else
                {
                    SemanticLirAggregateElement element =
                        semantic_lir_aggregate_elements[index];
                    if (element.aggregate_instruction == node)
                        value = element.value_instruction;
                }
            }
            ordinal += 1u;
            if (!opt_ir_node_is_executable(value, total) ||
                function_for_node(value) != deps.function_id) continue;
            uint ignored;
            InterlockedMax(x86_last_use_by_semantic[value], deps.position, ignored);
            if (atomic_u32_compare_exchange(
                    x86_live_by_semantic, value, 0u, X86_SEMANTIC_LIVE) != 0u)
                continue;
            // Constants and other leaves are complete as soon as they are
            // marked. A wide aggregate should not push and immediately pop a
            // walk record for each literal element.
            X86LivenessDependencies child = x86_liveness_dependencies[value];
            if (child.fixed_count + child.variable_count == 0u) continue;
            x86_liveness_walk[2u * value] = node;
            x86_liveness_walk[2u * value + 1u] = ordinal;
            claimed = value;
        }
        if (claimed != INVALID)
        {
            node = claimed;
            ordinal = 0u;
            continue;
        }
        if (node == root) return;
        ordinal = x86_liveness_walk[2u * node + 1u];
        node = x86_liveness_walk[2u * node];
    }
}
