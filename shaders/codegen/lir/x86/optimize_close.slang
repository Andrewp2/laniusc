// Computes transitive value liveness with a persistent global work queue.
// Work is proportional to live nodes and local operand arity, never to a
// whole function assigned to one invocation.

import codegen.lowering_ir;
import codegen.optimization_ir;
import codegen.lir.optimization.execution_owner;
import codegen.lir.optimization.ssa_sparse_work;
import codegen.lir.x86.common;
import primitive_types;
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
StructuredBuffer<X86ValueAnalysis> x86_value_by_semantic;
RWStructuredBuffer<uint> x86_last_use_by_semantic;
RWStructuredBuffer<uint> x86_live_by_semantic;
RWStructuredBuffer<uint> x86_liveness_work_state;
RWStructuredBuffer<uint> x86_liveness_work_queue;

static const uint INVALID = 0xffffffffu;

groupshared uint batch_begin;
groupshared uint batch_count;
groupshared uint batch_done;

uint function_for_node(uint row)
{
    uint owner = opt_ir_source_hir[row];
    return owner < gParams.function_capacity
        ? semantic_function_id_by_hir[owner] : INVALID;
}

void admit(uint value, uint position, uint total, uint function_id)
{
    if (!opt_ir_node_is_executable(value, total) ||
        function_for_node(value) != function_id) return;
    uint ignored;
    InterlockedMax(x86_last_use_by_semantic[value], position, ignored);
    uint prior = atomic_u32_compare_exchange(
        x86_live_by_semantic, value, 0u, X86_SEMANTIC_LIVE);
    if (prior != 0u) return;
    uint required;
    ssa_work_publish(value, gParams.semantic_capacity,
        x86_liveness_work_state, x86_liveness_work_queue, required);
}

bool fusible_comparison(uint row, uint total, uint function_id)
{
    if (!opt_ir_node_is_executable(row, total) ||
        function_for_node(row) != function_id) return false;
    OptIrNodeCore core = opt_ir_core[row];
    uint type_id = core.type_id;
    // Integer, Boolean, char and pointer operands; COMPARE_BRANCH_FALSE has a
    // one-word body for each (see plan_compare and plan_specialized).
    return opt_ir_op(core) == SEMANTIC_LIR_OP_COMPARE &&
        type_id >= 2u && type_id <= 17u && type_id != 5u &&
        type_id != 7u && type_id != 15u;
}

// Which operand of a binary or comparison scatter encodes as an immediate
// (1: left, 2: right, 0: neither), mirroring its BINARY, COMPARE,
// COMPARE_BRANCH_FALSE and SELECT_STORE rules. That constant then needs no
// register or emitted row of its own.
uint immediate_operand(uint op, OptIrNodeCore core, uint left_row, uint right_row,
                       uint total)
{
    bool lk = left_row < total && x86_value_by_semantic[left_row].known != 0u;
    bool rk = right_row < total && x86_value_by_semantic[right_row].known != 0u;
    uint left = lk ? x86_value_by_semantic[left_row].value : 0u;
    uint right = rk ? x86_value_by_semantic[right_row].value : 0u;
    uint type_id = core.type_id;
    uint width = 0u;
    bool right_width = right_row < total &&
        x86_width_immediate_operand(type_id, opt_ir_core[right_row],
            opt_ir_operands[right_row], x86_value_by_semantic[right_row], width);
    if (op == SEMANTIC_LIR_OP_COMPARE)
    {
        if (x86_semantic_type_is_aggregate(core)) return 0u;
        if ((lk || rk) && x86_integer_immediate_operation(SEMANTIC_LIR_OP_COMPARE, type_id,
                rk ? right : left))
            return rk ? 2u : 1u;
        return right_width && scalar_is_wide_integer(type_id) ? 2u : 0u;
    }
    if (rk && (x86_constant_divisor_kind(op, type_id, right) != X86_CONSTANT_DIVISOR_NONE ||
               x86_integer_immediate_operation(op, type_id, right)))
        return 2u;
    uint amount = 0u;
    if (right_row < total && scalar_is_wide_integer(type_id) &&
        (op == SEMANTIC_LIR_OP_SHIFT_LEFT || op == SEMANTIC_LIR_OP_SHIFT_RIGHT) &&
        x86_constant_shift_amount(opt_ir_core[right_row], opt_ir_operands[right_row],
            x86_value_by_semantic[right_row], amount) && amount <= 63u)
        return 2u;
    if (!rk && lk && x86_integer_immediate_commutative(op) &&
        x86_integer_immediate_operation(op, type_id, left))
        return 1u;
    if (right_width && x86_width_immediate_operation(op)) return 2u;
    uint mask = 0u;
    if (op == SEMANTIC_LIR_OP_BIT_AND && right_row < total &&
        x86_zero_extended_mask_operand(type_id, opt_ir_core[right_row],
            opt_ir_operands[right_row], mask))
        return 2u;
    return 0u;
}

void admit_dependencies(uint row, uint total)
{
    if (!opt_ir_node_is_executable(row, total)) return;
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
        // Two constant operands that scatter folds (x86_fold_integer_binary)
        // lower to one immediate row that reads neither operand.
        uint folded;
        bool constant_operands = operands.a < total && operands.b < total &&
            x86_value_by_semantic[operands.a].known != 0u &&
            x86_value_by_semantic[operands.b].known != 0u;
        if (!constant_operands || !x86_fold_integer_binary(op, core.type_id, operands.c,
                x86_value_by_semantic[operands.a].value,
                x86_value_by_semantic[operands.b].value, folded))
        {
            uint immediate = immediate_operand(op, core, operands.a, operands.b, total);
            if (immediate != 1u) admit(operands.a, position, total, function_id);
            if (immediate != 2u) admit(operands.b, position, total, function_id);
        }
    }
    else if (op == SEMANTIC_LIR_OP_NEGATE ||
             op == SEMANTIC_LIR_OP_LOGICAL_NOT ||
             op == SEMANTIC_LIR_OP_CONVERT || op == SEMANTIC_LIR_OP_DROP ||
             op == SEMANTIC_LIR_OP_PLACE_LOAD || op == SEMANTIC_LIR_OP_FIELD_ADDRESS ||
             op == SEMANTIC_LIR_OP_RETURN)
        admit(operands.a, position, total, function_id);
    else if (op == SEMANTIC_LIR_OP_INDEX_ADDRESS || op == SEMANTIC_LIR_OP_PLACE_STORE)
    {
        admit(operands.a, position, total, function_id);
        admit(operands.b, position, total, function_id);
    }
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
    {
        // A scalar comparison read only by this branch stays dead, so scatter
        // fuses it into the branch (COMPARE_BRANCH_FALSE: cmp; jcc) instead of
        // materializing a Boolean with setcc and testing it. The branch then
        // reads the comparison's operands itself.
        uint condition = operands.a;
        if (fusible_comparison(condition, total, function_id))
        {
            OptIrNodeOperands comparison = opt_ir_operands[condition];
            uint immediate = immediate_operand(SEMANTIC_LIR_OP_COMPARE,
                opt_ir_core[condition], comparison.a, comparison.b, total);
            if (immediate != 1u) admit(comparison.a, position, total, function_id);
            if (immediate != 2u) admit(comparison.b, position, total, function_id);
        }
        else admit(condition, position, total, function_id);
    }

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
        // One lane schedules; every lane takes the same exit and
        // barrier path, and reads the batch before it can change.
        if (ltid.x == 0u)
        {
            ssa_work_try_pop_batch(gParams.semantic_capacity, 32u,
                x86_liveness_work_state, batch_begin, batch_count);
            batch_done = batch_count == 0u &&
                    ssa_work_quiescent(x86_liveness_work_state)
                ? 1u : 0u;
        }
        GroupMemoryBarrierWithGroupSync();
        uint work_begin = batch_begin;
        uint work_count = batch_count;
        bool work_done = batch_done != 0u;
        GroupMemoryBarrierWithGroupSync();
        if (work_done) return;
        if (work_count == 0u) continue;
        if (ltid.x < work_count)
        {
            uint row = ssa_work_read_published(
                x86_liveness_work_queue, work_begin + ltid.x);
            if (row < total) admit_dependencies(row, total);
        }
        GroupMemoryBarrierWithGroupSync();
        if (ltid.x == 0u)
            ssa_work_finish_batch(x86_liveness_work_state, work_count);
    }
}
