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
import codegen.lir.x86.common;
import primitive_types;
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
// Two words per value: the reader that claimed it, then that reader's next
// dependency ordinal.
RWStructuredBuffer<uint> x86_liveness_walk;

static const uint INVALID = 0xffffffffu;
static const uint DISPATCH_X_STRIDE = 16776960u;

static const uint VARIABLE_NONE = 0u;
static const uint VARIABLE_CALL_ARGUMENTS = 1u;
static const uint VARIABLE_AGGREGATE_ELEMENTS = 2u;

// The values one live node reads: up to three operands, then the rows of its
// call arguments or aggregate elements.
struct Dependencies
{
    uint position;
    uint function_id;
    uint fixed0;
    uint fixed1;
    uint fixed2;
    uint fixed_count;
    uint variable_kind;
    uint variable_start;
    uint variable_count;
};

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

Dependencies dependencies(uint row, uint total)
{
    Dependencies deps;
    deps.position = INVALID;
    deps.function_id = INVALID;
    deps.fixed0 = INVALID;
    deps.fixed1 = INVALID;
    deps.fixed2 = INVALID;
    deps.fixed_count = 0u;
    deps.variable_kind = VARIABLE_NONE;
    deps.variable_start = 0u;
    deps.variable_count = 0u;
    if (!opt_ir_node_is_executable(row, total)) return deps;
    uint position = x86_position_by_semantic[row];
    uint function_id = function_for_node(row);
    if (position == INVALID || function_id == INVALID) return deps;
    deps.position = position;
    deps.function_id = function_id;
    OptIrNodeCore core = opt_ir_core[row];
    OptIrNodeOperands operands = opt_ir_operands[row];
    uint op = opt_ir_op(core);
    // A binary operation, or a comparison this row reads through, whose
    // operands are the dependencies unless one encodes as an immediate.
    bool binary = false;
    uint binary_op = op;
    OptIrNodeCore binary_core = core;
    uint left = INVALID;
    uint right = INVALID;
    if (op == SEMANTIC_LIR_OP_VALUE_GET)
    {
        if (operands.a < gParams.token_capacity)
        {
            uint definition = x86_decl_analysis_by_token[operands.a].definition;
            if (definition < total &&
                x86_position_by_semantic[definition] < position)
            {
                deps.fixed0 = definition;
                deps.fixed_count = 1u;
            }
        }
    }
    else if (op == SEMANTIC_LIR_OP_VALUE_SET || op == SEMANTIC_LIR_OP_STORE)
    {
        if (op == SEMANTIC_LIR_OP_STORE &&
            (core.flags & (SEMANTIC_LIR_FLAG_INDEXED |
                           SEMANTIC_LIR_FLAG_FIELD)) != 0u)
        {
            deps.fixed0 = operands.a;
            if ((core.flags & SEMANTIC_LIR_FLAG_INDEXED) != 0u)
                deps.fixed1 = operands.b;
            deps.fixed2 = operands.c;
            deps.fixed_count = 3u;
        }
        else
        {
            deps.fixed0 = operands.b;
            deps.fixed_count = 1u;
        }
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
            binary = true;
            left = operands.a;
            right = operands.b;
        }
    }
    else if (op == SEMANTIC_LIR_OP_NEGATE ||
             op == SEMANTIC_LIR_OP_LOGICAL_NOT ||
             op == SEMANTIC_LIR_OP_CONVERT || op == SEMANTIC_LIR_OP_DROP ||
             op == SEMANTIC_LIR_OP_PLACE_LOAD || op == SEMANTIC_LIR_OP_FIELD_ADDRESS ||
             op == SEMANTIC_LIR_OP_RETURN)
    {
        deps.fixed0 = operands.a;
        deps.fixed_count = 1u;
    }
    else if (op == SEMANTIC_LIR_OP_INDEX_ADDRESS || op == SEMANTIC_LIR_OP_PLACE_STORE ||
             op == SEMANTIC_LIR_OP_AGGREGATE_COPY)
    {
        deps.fixed0 = operands.a;
        deps.fixed1 = operands.b;
        deps.fixed_count = 2u;
    }
    else if (op == SEMANTIC_LIR_OP_LOAD)
    {
        deps.fixed0 = operands.a;
        if ((core.flags & SEMANTIC_LIR_FLAG_INDEXED) != 0u)
            deps.fixed1 = operands.b;
        deps.fixed_count = 2u;
    }
    else if (op == SEMANTIC_LIR_OP_IF_BEGIN ||
             op == SEMANTIC_LIR_OP_BRANCH_IF)
    {
        // A scalar comparison read only by this branch stays dead, so scatter
        // fuses it into the branch (COMPARE_BRANCH_FALSE: cmp; jcc) instead of
        // materializing a Boolean with setcc and testing it. The branch then
        // reads the comparison's operands itself.
        // Likewise a Boolean `!v` read only by this branch: the branch tests v
        // (or fuses v's comparison with the predicate negated) and jumps on
        // the other sense, so the NOT stays dead. Its last use still covers
        // the branch in case another reader makes it live, and scatter then
        // tests the NOT as before.
        uint condition = operands.a;
        if (opt_ir_node_is_executable(condition, total) &&
            function_for_node(condition) == function_id &&
            opt_ir_op(opt_ir_core[condition]) == SEMANTIC_LIR_OP_LOGICAL_NOT &&
            opt_ir_core[condition].type_id == 2u &&
            opt_ir_operands[condition].a < total &&
            (opt_ir_core[opt_ir_operands[condition].a].type_id == 2u ||
             opt_ir_op(opt_ir_core[opt_ir_operands[condition].a]) ==
                 SEMANTIC_LIR_OP_COMPARE))
        {
            uint ignored;
            InterlockedMax(x86_last_use_by_semantic[condition], position, ignored);
            condition = opt_ir_operands[condition].a;
            // v may be a comparison another row reads (`a || b` stores it);
            // scatter then tests v's value here.
            InterlockedMax(x86_last_use_by_semantic[condition], position, ignored);
        }
        if (fusible_comparison(condition, total, function_id))
        {
            binary = true;
            binary_op = SEMANTIC_LIR_OP_COMPARE;
            binary_core = opt_ir_core[condition];
            left = opt_ir_operands[condition].a;
            right = opt_ir_operands[condition].b;
        }
        else
        {
            deps.fixed0 = condition;
            deps.fixed_count = 1u;
        }
    }
    if (binary)
    {
        uint immediate = immediate_operand(binary_op, binary_core, left, right, total);
        if (immediate != 1u) deps.fixed0 = left;
        if (immediate != 2u) deps.fixed1 = right;
        deps.fixed_count = 2u;
    }

    uint source_hir = opt_ir_source_hir[row];
    if (semantic_lir_is_call(op) && source_hir < gParams.function_capacity)
    {
        uint start = semantic_lir_call_arg_start_by_hir[source_hir];
        uint count = semantic_lir_call_arg_count_by_hir[source_hir];
        deps.variable_kind = VARIABLE_CALL_ARGUMENTS;
        deps.variable_start = start;
        deps.variable_count = min(count,
            gParams.call_arg_capacity - min(start, gParams.call_arg_capacity));
    }
    else if (op == SEMANTIC_LIR_OP_AGGREGATE_NEW)
    {
        uint element_total = min(gParams.aggregate_capacity,
            semantic_lir_aggregate_element_total[0u]);
        deps.variable_kind = VARIABLE_AGGREGATE_ELEMENTS;
        deps.variable_start = operands.a;
        deps.variable_count = min(operands.b,
            element_total - min(operands.a, element_total));
    }
    return deps;
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
        Dependencies deps = dependencies(node, total);
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
