import codegen.lowering_ir;
import codegen.optimization_ir;
import codegen.lir.x86.common;
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
StructuredBuffer<uint> semantic_schedule_order;
StructuredBuffer<uint> opt_ir_source_hir;
StructuredBuffer<uint> semantic_function_id_by_hir;
StructuredBuffer<uint> x86_position_by_semantic;
RWStructuredBuffer<uint> x86_last_use_by_semantic;
RWStructuredBuffer<uint> x86_live_by_semantic;
StructuredBuffer<X86ValueAnalysis> x86_value_by_semantic;
StructuredBuffer<X86DeclarationAnalysis> x86_decl_analysis_by_token;
RWStructuredBuffer<X86SelectInfo> x86_select_by_semantic;

static const uint INVALID = 0xffffffffu;
static const uint DISPATCH_X_STRIDE = 16776960u;

bool scalar_gpr_type(uint type_id)
{
    return type_id == 1u || type_id == 2u || type_id == 3u ||
        type_id == 4u || type_id == 6u || type_id == 8u;
}

bool same_function(uint row, uint total, uint function_id)
{
    if (row >= total) return false;
    uint owner = opt_ir_source_hir[row];
    return owner < gParams.function_capacity &&
        semantic_function_id_by_hir[owner] == function_id;
}

bool direct_integer_constant(uint row, uint total, out uint value)
{
    value = 0u;
    if (row >= total) return false;
    X86ValueAnalysis analysis = x86_value_by_semantic[row];
    value = analysis.value;
    return analysis.known != 0u;
}

bool masked_single_bit(uint row, uint total)
{
    if (row >= total ||
        opt_ir_op(opt_ir_core[row]) != SEMANTIC_LIR_OP_BIT_AND)
        return false;
    OptIrNodeOperands operands = opt_ir_operands[row];
    uint mask;
    bool constant_mask = direct_integer_constant(operands.a, total, mask) ||
        direct_integer_constant(operands.b, total, mask);
    return constant_mask && mask != 0u && (mask & (mask - 1u)) == 0u;
}

bool select_arm_value_op(OptIrNodeCore core)
{
    uint op = opt_ir_op(core);
    return op == SEMANTIC_LIR_OP_NOP ||
        op == SEMANTIC_LIR_OP_CONST_I32 ||
        op == SEMANTIC_LIR_OP_VALUE_GET ||
        op == SEMANTIC_LIR_OP_ADD || op == SEMANTIC_LIR_OP_SUB ||
        op == SEMANTIC_LIR_OP_MUL ||
        op == SEMANTIC_LIR_OP_BIT_AND ||
        op == SEMANTIC_LIR_OP_BIT_OR ||
        op == SEMANTIC_LIR_OP_BIT_XOR ||
        op == SEMANTIC_LIR_OP_LOGICAL_AND ||
        op == SEMANTIC_LIR_OP_LOGICAL_OR ||
        op == SEMANTIC_LIR_OP_COMPARE ||
        op == SEMANTIC_LIR_OP_NEGATE ||
        op == SEMANTIC_LIR_OP_LOGICAL_NOT;
}

bool scalar_assignment(uint row, uint total, out uint declaration,
                       out uint value)
{
    declaration = INVALID;
    value = INVALID;
    if (row >= total) return false;
    OptIrNodeCore core = opt_ir_core[row];
    uint op = opt_ir_op(core);
    if ((op != SEMANTIC_LIR_OP_VALUE_SET && op != SEMANTIC_LIR_OP_STORE) ||
        (core.flags & (SEMANTIC_LIR_FLAG_INDEXED |
                       SEMANTIC_LIR_FLAG_FIELD)) != 0u ||
        !scalar_gpr_type(core.type_id))
        return false;
    OptIrNodeOperands operands = opt_ir_operands[row];
    declaration = operands.a;
    value = operands.b;
    return declaration < gParams.token_capacity && value < total;
}

bool pure_select_arm(uint first_position, uint store_position, uint total,
                     uint function_id)
{
    if (first_position > store_position ||
        store_position - first_position > 16u)
        return false;
    uint operation_cost = 0u;
    for (uint position = first_position; position < store_position;
         position += 1u)
    {
        uint row = semantic_schedule_order[position];
        if (!same_function(row, total, function_id)) return false;
        OptIrNodeCore core = opt_ir_core[row];
        if (!select_arm_value_op(core)) return false;
        uint op = opt_ir_op(core);
        if (op != SEMANTIC_LIR_OP_NOP &&
            op != SEMANTIC_LIR_OP_CONST_I32 &&
            op != SEMANTIC_LIR_OP_VALUE_GET)
        {
            operation_cost += 1u;
            if (operation_cost > 2u) return false;
        }
    }
    return true;
}

void mark_coalescible_value_get(uint row, uint position, uint total)
{
    OptIrNodeCore core = opt_ir_core[row];
    if (opt_ir_op(core) != SEMANTIC_LIR_OP_VALUE_GET ||
        !scalar_gpr_type(core.type_id) ||
        x86_live_by_semantic[row] != X86_SEMANTIC_LIVE)
        return;
    uint declaration = opt_ir_operands[row].a;
    uint last_use = x86_last_use_by_semantic[row];
    if (declaration >= gParams.token_capacity || last_use < position ||
        last_use >= total || last_use - position > 64u)
        return;

    // A VALUE_GET is a snapshot. It may share the declaration's physical home
    // only while that home cannot change before the snapshot's final use.
    // Calls also invalidate parameter aliases because their incoming ABI homes
    // are caller-saved even when the source declaration is immutable. Indirect
    // stores conservatively end the proof because a local may be address-taken.
    for (uint cursor = position + 1u; cursor <= last_use; cursor += 1u)
    {
        uint candidate = semantic_schedule_order[cursor];
        if (candidate >= total) return;
        OptIrNodeCore candidate_core = opt_ir_core[candidate];
        OptIrNodeOperands candidate_operands =
            opt_ir_operands[candidate];
        uint op = opt_ir_op(candidate_core);
        if (semantic_lir_is_call(op)) return;
        if (op == SEMANTIC_LIR_OP_VALUE_SET &&
            candidate_operands.a == declaration)
            return;
        if (op == SEMANTIC_LIR_OP_STORE)
        {
            if ((candidate_core.flags & (SEMANTIC_LIR_FLAG_INDEXED |
                                         SEMANTIC_LIR_FLAG_FIELD)) != 0u ||
                candidate_operands.a == declaration)
                return;
        }
    }
    uint ignored;
    InterlockedMax(x86_live_by_semantic[row],
        X86_SEMANTIC_COALESCED_ALIAS, ignored);
}

void retain_value(uint value, uint position, uint total, uint function_id)
{
    if (!same_function(value, total, function_id)) return;
    uint ignored;
    InterlockedMax(x86_live_by_semantic[value], X86_SEMANTIC_LIVE, ignored);
    InterlockedMax(x86_last_use_by_semantic[value], position, ignored);
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint position = linear_dispatch_thread_id_2d(dtid, DISPATCH_X_STRIDE);
    uint total = min(gParams.semantic_capacity, opt_ir_total[0u]);
    if (position >= total) return;
    uint branch_row = semantic_schedule_order[position];
    if (branch_row >= total) return;
    mark_coalescible_value_get(branch_row, position, total);
    if (position == 0u) return;
    if (branch_row >= total ||
        opt_ir_op(opt_ir_core[branch_row]) !=
            SEMANTIC_LIR_OP_IF_BEGIN)
        return;

    uint owner = opt_ir_source_hir[branch_row];
    if (owner >= gParams.function_capacity) return;
    uint function_id = semantic_function_id_by_hir[owner];
    if (function_id >= gParams.function_capacity) return;

    OptIrNodeOperands branch = opt_ir_operands[branch_row];
    if (branch.c != 1u || branch.a >= total || branch.b >= total ||
        semantic_schedule_order[position - 1u] != branch.a ||
        !same_function(branch.a, total, function_id) ||
        !same_function(branch.b, total, function_id) ||
        opt_ir_op(opt_ir_core[branch.a]) !=
            SEMANTIC_LIR_OP_COMPARE ||
        opt_ir_core[branch.a].type_id == X86_LIR_TY_FLOAT ||
        x86_last_use_by_semantic[branch.a] != position ||
        opt_ir_op(opt_ir_core[branch.b]) != SEMANTIC_LIR_OP_ELSE)
        return;

    OptIrNodeOperands comparison = opt_ir_operands[branch.a];
    uint left_constant;
    uint right_constant;
    if (direct_integer_constant(comparison.a, total, left_constant) &&
        direct_integer_constant(comparison.b, total, right_constant))
        return;
    bool left_zero = direct_integer_constant(
        comparison.a, total, left_constant) && left_constant == 0u;
    bool right_zero = direct_integer_constant(
        comparison.b, total, right_constant) && right_constant == 0u;
    // A masked single-bit equality is typically data-dependent and therefore
    // difficult for a branch predictor. Other comparisons remain branches;
    // eagerly executing both arms can lose badly when their outcome follows a
    // predictable range or modulo pattern.
    if (comparison.c > 1u ||
        !((left_zero && masked_single_bit(comparison.b, total)) ||
          (right_zero && masked_single_bit(comparison.a, total))))
        return;

    uint else_position = x86_position_by_semantic[branch.b];
    uint end_row = opt_ir_operands[branch.b].a;
    if (!same_function(end_row, total, function_id) ||
        opt_ir_op(opt_ir_core[end_row]) !=
            SEMANTIC_LIR_OP_CONTROL_END)
        return;
    uint end_position = x86_position_by_semantic[end_row];
    if (else_position <= position + 1u || else_position >= end_position ||
        end_position >= total || end_position == 0u)
        return;

    uint true_store_position = else_position - 1u;
    uint false_store_position = end_position - 1u;
    uint true_store = semantic_schedule_order[true_store_position];
    uint false_store = semantic_schedule_order[false_store_position];
    if (!same_function(true_store, total, function_id) ||
        !same_function(false_store, total, function_id))
        return;
    uint true_declaration;
    uint true_value;
    uint false_declaration;
    uint false_value;
    if (!scalar_assignment(true_store, total, true_declaration, true_value) ||
        !scalar_assignment(false_store, total, false_declaration, false_value) ||
        true_declaration != false_declaration ||
        !pure_select_arm(position + 1u, true_store_position, total, function_id) ||
        !pure_select_arm(
            else_position + 1u, false_store_position, total, function_id))
        return;

    X86SelectInfo info;
    info.condition = branch.a;
    info.true_value = true_value;
    info.false_value = false_value;
    info.declaration = true_declaration;
    x86_select_by_semantic[end_row] = info;
    x86_live_by_semantic[branch.a] = 0u;
    x86_live_by_semantic[branch_row] = 0u;
    x86_live_by_semantic[branch.b] = 0u;
    x86_live_by_semantic[true_store] = 0u;
    x86_live_by_semantic[false_store] = 0u;
    x86_live_by_semantic[end_row] = X86_SEMANTIC_SELECT;

    uint immediate;
    bool left_immediate = direct_integer_constant(
        comparison.a, total, immediate) &&
        x86_integer_immediate_operation(SEMANTIC_LIR_OP_COMPARE,
            opt_ir_core[branch.a].type_id, immediate);
    bool right_immediate = direct_integer_constant(
        comparison.b, total, immediate) &&
        x86_integer_immediate_operation(SEMANTIC_LIR_OP_COMPARE,
            opt_ir_core[branch.a].type_id, immediate);
    if (left_immediate)
        retain_value(comparison.b, end_position, total, function_id);
    else
    {
        retain_value(comparison.a, end_position, total, function_id);
        if (!right_immediate)
            retain_value(comparison.b, end_position, total, function_id);
    }
    retain_value(true_value, end_position, total, function_id);
    retain_value(false_value, end_position, total, function_id);
}
