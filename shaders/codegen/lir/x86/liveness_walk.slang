// The liveness walk shared by optimize_close and optimize_element_liveness.
// A lane that marks a value live owns it and walks its dependencies depth
// first, so each live value is expanded exactly once and no lane waits on
// another. The walk keeps no stack: a value records the reader that claimed
// it and the reader's next dependency, and the lane returns along that
// record.

import codegen.lowering_ir;
import codegen.optimization_ir;
import codegen.lir.optimization.execution_owner;
import codegen.lir.x86.liveness_dependencies;
import atomics;

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

uint x86_liveness_function(uint row, uint function_capacity)
{
    uint owner = opt_ir_source_hir[row];
    return owner < function_capacity
        ? semantic_function_id_by_hir[owner] : 0xffffffffu;
}

// The value a node reads as its dependency `ordinal`, or INVALID.
uint x86_liveness_dependency(X86LivenessDependencies deps, uint node, uint ordinal)
{
    if (ordinal < deps.fixed_count)
        return ordinal == 0u ? deps.fixed0
            : ordinal == 1u ? deps.fixed1 : deps.fixed2;
    uint index = deps.variable_start + (ordinal - deps.fixed_count);
    if (deps.variable_kind == VARIABLE_CALL_ARGUMENTS)
    {
        SemanticLirCallArg argument = semantic_lir_call_args[index];
        return argument.call_instruction == node
            ? argument.value_instruction : 0xffffffffu;
    }
    SemanticLirAggregateElement element = semantic_lir_aggregate_elements[index];
    return element.aggregate_instruction == node
        ? element.value_instruction : 0xffffffffu;
}

// Reader `node` at `position` in function `function_id` reads `value`:
// extend the value's last use and claim it. Returns true when this lane
// claimed a value that has dependencies of its own to walk.
bool x86_liveness_read(uint node, uint position, uint function_id, uint value,
                       uint total, uint function_capacity)
{
    if (!opt_ir_node_is_executable(value, total) ||
        x86_liveness_function(value, function_capacity) != function_id)
        return false;
    uint ignored;
    InterlockedMax(x86_last_use_by_semantic[value], position, ignored);
    if (atomic_u32_compare_exchange(
            x86_live_by_semantic, value, 0u, X86_SEMANTIC_LIVE) != 0u)
        return false;
    // Constants and other leaves are complete as soon as they are marked.
    X86LivenessDependencies child = x86_liveness_dependencies[value];
    return child.fixed_count + child.variable_count != 0u;
}

// Walks the dependencies of `root`, which this lane has already claimed.
// With `defer_elements`, aggregate elements are left to
// optimize_element_liveness, which reads each element of a live aggregate
// on its own lane; a wide literal then never runs on one lane.
void x86_liveness_walk_from(uint root, uint total, uint function_capacity,
                            bool defer_elements)
{
    uint node = root;
    uint ordinal = 0u;
    // A lane enters each value it owns once and returns to it once per
    // dependency it claimed there.
    uint budget = 2u * total + 2u;
    for (uint step = 0u; step < budget; ++step)
    {
        X86LivenessDependencies deps = x86_liveness_dependencies[node];
        uint count = deps.fixed_count +
            (defer_elements && deps.variable_kind == VARIABLE_AGGREGATE_ELEMENTS
                ? 0u : deps.variable_count);
        uint claimed = 0xffffffffu;
        while (ordinal < count && claimed == 0xffffffffu)
        {
            uint value = x86_liveness_dependency(deps, node, ordinal);
            ordinal += 1u;
            if (!x86_liveness_read(node, deps.position, deps.function_id, value,
                    total, function_capacity))
                continue;
            x86_liveness_walk[2u * value] = node;
            x86_liveness_walk[2u * value + 1u] = ordinal;
            claimed = value;
        }
        if (claimed != 0xffffffffu)
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
