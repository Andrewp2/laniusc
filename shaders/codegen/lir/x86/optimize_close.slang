// Computes transitive value liveness with a persistent global work queue.
// Work is proportional to live nodes and local operand arity, never to a
// whole function assigned to one invocation.

import codegen.lowering_ir;
import codegen.optimization_ir;
import codegen.lir.optimization.ssa_sparse_work;
import atomics;

struct Params
{
    uint semantic_capacity;
    uint call_arg_capacity;
    uint aggregate_capacity;
    uint function_capacity;
    uint token_capacity;
    uint reserved0;
    uint worker_count;
    uint reserved2;
};
ConstantBuffer<Params> gParams;
StructuredBuffer<uint> opt_ir_total;
StructuredBuffer<OptIrNodeCore> opt_ir_core;
StructuredBuffer<OptIrNodeOperands> opt_ir_operands;
StructuredBuffer<uint> opt_ir_source_hir;
StructuredBuffer<uint> semantic_function_id_by_hir;
StructuredBuffer<uint> semantic_lir_call_arg_count_by_hir;
StructuredBuffer<uint> semantic_lir_call_arg_start_by_hir;
StructuredBuffer<SemanticLirCallArg> semantic_lir_call_args;
StructuredBuffer<uint> semantic_lir_aggregate_element_total;
StructuredBuffer<SemanticLirAggregateElement>
    semantic_lir_aggregate_elements;
StructuredBuffer<uint> x86_position_by_semantic;
StructuredBuffer<X86DeclarationAnalysis> x86_decl_analysis_by_token;
RWStructuredBuffer<uint> x86_last_use_by_semantic;
RWStructuredBuffer<uint> x86_live_by_semantic;
RWStructuredBuffer<uint> x86_liveness_work_state;
RWStructuredBuffer<uint> x86_liveness_work_queue;

static const uint INVALID = 0xffffffffu;

groupshared uint batch_begin;
groupshared uint batch_count;

uint function_for_node(uint row)
{
    uint owner = opt_ir_source_hir[row];
    return owner < gParams.function_capacity
        ? semantic_function_id_by_hir[owner] : INVALID;
}

void admit(uint value, uint position, uint total, uint function_id)
{
    if (value >= total || function_for_node(value) != function_id) return;
    uint ignored;
    InterlockedMax(x86_last_use_by_semantic[value], position, ignored);
    uint prior = atomic_u32_compare_exchange(
        x86_live_by_semantic, value, 0u, X86_SEMANTIC_LIVE);
    if (prior != 0u) return;
    uint required;
    ssa_work_publish(value, gParams.semantic_capacity,
        x86_liveness_work_state, x86_liveness_work_queue, required);
}

void admit_dependencies(uint row, uint total)
{
    uint position = x86_position_by_semantic[row];
    uint function_id = function_for_node(row);
    if (position == INVALID || function_id == INVALID) return;
    OptIrNodeCore core = opt_ir_core[row];
    OptIrNodeOperands operands = opt_ir_operands[row];
    uint op = opt_ir_op(core);
    if (op == SEMANTIC_LIR_OP_VALUE_GET)
    {
        if (operands.a < gParams.token_capacity)
        {
            uint definition = x86_decl_analysis_by_token[operands.a].definition;
            if (definition < total &&
                x86_position_by_semantic[definition] < position)
                admit(definition, position, total, function_id);
        }
    }
    else if (op == SEMANTIC_LIR_OP_VALUE_SET || op == SEMANTIC_LIR_OP_STORE)
    {
        if (op == SEMANTIC_LIR_OP_STORE &&
            (core.flags & (SEMANTIC_LIR_FLAG_INDEXED |
                           SEMANTIC_LIR_FLAG_FIELD)) != 0u)
        {
            admit(operands.a, position, total, function_id);
            if ((core.flags & SEMANTIC_LIR_FLAG_INDEXED) != 0u)
                admit(operands.b, position, total, function_id);
            admit(operands.c, position, total, function_id);
        }
        else admit(operands.b, position, total, function_id);
    }
    else if ((op >= SEMANTIC_LIR_OP_ADD && op <= SEMANTIC_LIR_OP_COMPARE) ||
             op == SEMANTIC_LIR_OP_LOGICAL_AND ||
             op == SEMANTIC_LIR_OP_LOGICAL_OR)
    {
        admit(operands.a, position, total, function_id);
        admit(operands.b, position, total, function_id);
    }
    else if (op == SEMANTIC_LIR_OP_NEGATE ||
             op == SEMANTIC_LIR_OP_LOGICAL_NOT ||
             op == SEMANTIC_LIR_OP_CONVERT || op == SEMANTIC_LIR_OP_DROP ||
             op == SEMANTIC_LIR_OP_ADDRESS || op == SEMANTIC_LIR_OP_RETURN)
        admit(operands.a, position, total, function_id);
    else if (op == SEMANTIC_LIR_OP_LOAD)
    {
        admit(operands.a, position, total, function_id);
        if ((core.flags & SEMANTIC_LIR_FLAG_INDEXED) != 0u)
            admit(operands.b, position, total, function_id);
    }
    else if (op == SEMANTIC_LIR_OP_AGGREGATE_COPY)
    {
        admit(operands.a, position, total, function_id);
        admit(operands.b, position, total, function_id);
    }
    else if (op == SEMANTIC_LIR_OP_IF_BEGIN ||
             op == SEMANTIC_LIR_OP_BRANCH_IF)
        admit(operands.a, position, total, function_id);

    uint source_hir = opt_ir_source_hir[row];
    if (semantic_lir_is_call(op) && source_hir < gParams.function_capacity)
    {
        uint start = semantic_lir_call_arg_start_by_hir[source_hir];
        uint count = semantic_lir_call_arg_count_by_hir[source_hir];
        for (uint ordinal = 0u; ordinal < count; ++ordinal)
        {
            uint arg_row = start + ordinal;
            if (arg_row >= gParams.call_arg_capacity) break;
            SemanticLirCallArg argument = semantic_lir_call_args[arg_row];
            if (argument.call_instruction == row)
                admit(argument.value_instruction, position, total, function_id);
        }
    }
    if (op == SEMANTIC_LIR_OP_AGGREGATE_NEW)
    {
        uint element_total = min(gParams.aggregate_capacity,
            semantic_lir_aggregate_element_total[0u]);
        for (uint ordinal = 0u; ordinal < operands.b; ++ordinal)
        {
            uint element_row = operands.a + ordinal;
            if (element_row >= element_total) break;
            SemanticLirAggregateElement element =
                semantic_lir_aggregate_elements[element_row];
            if (element.aggregate_instruction == row)
                admit(element.value_instruction, position, total, function_id);
        }
    }
}

[shader("compute")]
[numthreads(32, 1, 1)]
void main(uint3 gid: SV_GroupID, uint3 ltid: SV_GroupThreadID)
{
    if (gid.x >= gParams.worker_count) return;
    uint total = min(gParams.semantic_capacity, opt_ir_total[0u]);
    for (;;)
    {
        if (ltid.x == 0u)
            ssa_work_try_pop_batch(gParams.semantic_capacity, 32u,
                x86_liveness_work_state, batch_begin, batch_count);
        GroupMemoryBarrierWithGroupSync();
        if (batch_count == 0u)
        {
            if (ssa_work_quiescent(x86_liveness_work_state)) return;
            continue;
        }
        if (ltid.x < batch_count)
        {
            uint row = ssa_work_read_published(
                x86_liveness_work_queue, batch_begin + ltid.x);
            if (row < total) admit_dependencies(row, total);
        }
        GroupMemoryBarrierWithGroupSync();
        if (ltid.x == 0u)
            ssa_work_finish_batch(x86_liveness_work_state, batch_count);
        GroupMemoryBarrierWithGroupSync();
    }
}
