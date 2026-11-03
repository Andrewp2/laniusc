import codegen.lowering_ir;
import primitive_types;
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
        // SELECT_STORE moves 32 bits: bool, i32, u32 and char.
        !(core.type_id == 2u || core.type_id == 3u || core.type_id == 4u ||
          core.type_id == 6u))
        return false;
    OptIrNodeOperands operands = opt_ir_operands[row];
    declaration = operands.a;
    value = operands.b;
    return declaration < gParams.token_capacity && value < total;
}

// A RETURN of one 32-bit scalar value (bool, i32, u32 or char).
bool scalar_return(uint row, uint total, out uint value)
{
    value = INVALID;
    if (row >= total || opt_ir_op(opt_ir_core[row]) != SEMANTIC_LIR_OP_RETURN)
        return false;
    value = opt_ir_operands[row].a;
    if (value >= total) return false;
    uint type_id = opt_ir_core[value].type_id;
    return !x86_semantic_type_is_aggregate(opt_ir_core[value]) &&
        (type_id == 2u || type_id == 3u || type_id == 4u || type_id == 6u);
}

// Whether `value`, produced just before `position`, only steers control
// flow: it is the condition of the branch at `position`, directly, through
// a `!`, or through an enclosing `&&`/`||` that stores it in its temporary
// and tests it next (`t = v; !v` or `t = v; t`).
bool steers_branch(uint value, uint position, uint total, uint function_id)
{
    for (uint step = 0u; step < 8u; ++step)
    {
        if (position >= total) return false;
        uint row = semantic_schedule_order[position];
        if (!same_function(row, total, function_id)) return false;
        uint op = opt_ir_op(opt_ir_core[row]);
        OptIrNodeOperands operands = opt_ir_operands[row];
        if ((op == SEMANTIC_LIR_OP_IF_BEGIN || op == SEMANTIC_LIR_OP_BRANCH_IF) &&
            operands.a == value)
            return true;
        if (op == SEMANTIC_LIR_OP_LOGICAL_NOT && operands.a == value)
        {
            value = row;
            position += 1u;
            continue;
        }
        if (op != SEMANTIC_LIR_OP_VALUE_SET || operands.b != value ||
            position + 1u >= total)
            return false;
        uint next = semantic_schedule_order[position + 1u];
        if (!same_function(next, total, function_id)) return false;
        uint next_op = opt_ir_op(opt_ir_core[next]);
        if (!((next_op == SEMANTIC_LIR_OP_LOGICAL_NOT &&
               opt_ir_operands[next].a == value) ||
              (next_op == SEMANTIC_LIR_OP_VALUE_GET &&
               opt_ir_operands[next].a == operands.a)))
            return false;
        value = next;
        position += 2u;
    }
    return false;
}

bool memory_read(uint row, uint total)
{
    if (row >= total) return false;
    uint op = opt_ir_op(opt_ir_core[row]);
    return op == SEMANTIC_LIR_OP_LOAD || op == SEMANTIC_LIR_OP_PLACE_LOAD;
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
    // 64-bit and 8/16-bit integers have register homes too (decl_slots_scatter).
    bool wide = (core.type_id >= 9u && core.type_id <= 14u) ||
        core.type_id == 16u || core.type_id == 17u;
    if (opt_ir_op(core) != SEMANTIC_LIR_OP_VALUE_GET ||
        !(scalar_gpr_type(core.type_id) || wide) ||
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
        if (opt_ir_may_write_memory(candidate_core)) return;
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
    // `if (c) { x = t; } else { x = f; }` and `if (c) { x = t; }` whose arms
    // are short and cannot trap, call or write memory become a select
    // (SELECT_STORE, a CMOV). The condition is an integer comparison, or any
    // other Boolean value, tested against zero; a negation read only here is
    // folded into the select (flag X86_SELECT_NEGATED on the condition).
    bool else_arm = branch.c == 1u;
    if (branch.c > 1u || branch.a >= total || branch.b >= total ||
        semantic_schedule_order[position - 1u] != branch.a ||
        !same_function(branch.a, total, function_id) ||
        !same_function(branch.b, total, function_id) ||
        opt_ir_op(opt_ir_core[branch.b]) !=
            (else_arm ? SEMANTIC_LIR_OP_ELSE : SEMANTIC_LIR_OP_CONTROL_END))
        return;
    // A `!v` read only by this branch (optimize_close leaves it dead, for the
    // branch to test v on the other sense) folds into the select: v is then
    // a live Boolean value, or a comparison only the NOT read.
    uint condition = branch.a;
    bool negated = false;
    if (opt_ir_op(opt_ir_core[branch.a]) == SEMANTIC_LIR_OP_LOGICAL_NOT &&
        opt_ir_core[branch.a].type_id == 2u &&
        x86_last_use_by_semantic[branch.a] == position)
    {
        uint operand = opt_ir_operands[branch.a].a;
        if (same_function(operand, total, function_id) &&
            (opt_ir_op(opt_ir_core[operand]) == SEMANTIC_LIR_OP_COMPARE
                ? x86_live_by_semantic[operand] == 0u
                : opt_ir_core[operand].type_id == 2u &&
                  x86_live_by_semantic[operand] != 0u))
        {
            condition = operand;
            negated = true;
        }
    }
    OptIrNodeCore condition_core = opt_ir_core[condition];
    bool comparison_condition =
        opt_ir_op(condition_core) == SEMANTIC_LIR_OP_COMPARE;
    if (comparison_condition)
    {
        // SELECT_STORE compares 32 bits.
        uint compared = condition_core.type_id;
        if (!(compared == 2u || compared == 3u || compared == 4u ||
              compared == 6u) ||
            // optimize_close leaves a comparison read only by its branch dead
            // (fused into COMPARE_BRANCH_FALSE); a live one must end here.
            (x86_live_by_semantic[condition] != 0u &&
             x86_last_use_by_semantic[condition] != position))
            return;
        OptIrNodeOperands comparison = opt_ir_operands[condition];
        uint left_constant;
        uint right_constant;
        if (direct_integer_constant(comparison.a, total, left_constant) &&
            direct_integer_constant(comparison.b, total, right_constant))
            return;
    }
    else if (condition_core.type_id != 2u ||
             x86_live_by_semantic[condition] == 0u)
        return;

    uint else_position = else_arm
        ? x86_position_by_semantic[branch.b] : INVALID;
    uint end_row = else_arm ? opt_ir_operands[branch.b].a : branch.b;
    if (!same_function(end_row, total, function_id) ||
        opt_ir_op(opt_ir_core[end_row]) !=
            SEMANTIC_LIR_OP_CONTROL_END)
        return;
    uint end_position = x86_position_by_semantic[end_row];
    if (end_position >= total || end_position <= position + 1u ||
        (else_arm &&
         (else_position <= position + 1u || else_position >= end_position)))
        return;

    uint true_store_position = (else_arm ? else_position : end_position) - 1u;
    uint true_store = semantic_schedule_order[true_store_position];
    if (!same_function(true_store, total, function_id) ||
        !pure_select_arm(position + 1u, true_store_position, total, function_id))
        return;
    // The select's row: the arms' CONTROL_END for an assignment, the final
    // RETURN for `if (c) { return t; } [else] { return f; }` (with no else,
    // a few pure rows may compute f after the CONTROL_END).
    uint select_row = end_row;
    uint select_position = end_position;
    uint true_declaration = INVALID;
    uint true_value;
    uint false_store = INVALID;
    uint false_value = INVALID;
    bool returns = scalar_return(true_store, total, true_value);
    if (returns)
    {
        // A return chosen by a call result or a loaded value is usually a
        // predictable exit test (a lookup's found check); as a branch the
        // core runs past the load, as a cmov it waits for it. Return
        // selects take only comparisons of values already in registers.
        if (!comparison_condition ||
            memory_read(opt_ir_operands[condition].a, total) ||
            memory_read(opt_ir_operands[condition].b, total))
            return;
        uint false_position = end_position - 1u;
        if (!else_arm)
        {
            false_position = end_position + 1u;
            while (false_position < total && false_position - end_position <= 16u &&
                   same_function(semantic_schedule_order[false_position], total, function_id) &&
                   opt_ir_op(opt_ir_core[semantic_schedule_order[false_position]]) !=
                       SEMANTIC_LIR_OP_RETURN)
                false_position += 1u;
        }
        if (false_position >= total) return;
        false_store = semantic_schedule_order[false_position];
        if (!same_function(false_store, total, function_id) ||
            !scalar_return(false_store, total, false_value) ||
            opt_ir_core[false_value].type_id != opt_ir_core[true_value].type_id ||
            !pure_select_arm(else_arm ? else_position + 1u : end_position + 1u,
                false_position, total, function_id))
            return;
        select_row = false_store;
        select_position = false_position;
    }
    else
    {
        if (!scalar_assignment(true_store, total, true_declaration, true_value))
            return;
        // `a && b` and `a || b` lower to `t = a; if (t) / if (!a) { t = b; }`
        // and one read of t after the CONTROL_END. When that read is t's
        // last and only steers a branch, a select would compute t just to
        // test it: keep the branch.
        uint read_position = end_position + 1u;
        if (read_position < total)
        {
            uint read = semantic_schedule_order[read_position];
            if (same_function(read, total, function_id) &&
                opt_ir_op(opt_ir_core[read]) == SEMANTIC_LIR_OP_VALUE_GET &&
                opt_ir_operands[read].a == true_declaration &&
                x86_decl_analysis_by_token[true_declaration].last_read ==
                    read_position + 1u &&
                steers_branch(read, read_position + 1u, total, function_id))
                return;
        }
        if (else_arm)
        {
            uint false_store_position = end_position - 1u;
            false_store = semantic_schedule_order[false_store_position];
            uint false_declaration;
            if (!same_function(false_store, total, function_id) ||
                !scalar_assignment(false_store, total, false_declaration, false_value) ||
                true_declaration != false_declaration ||
                !pure_select_arm(
                    else_position + 1u, false_store_position, total, function_id))
                return;
        }
    }

    X86SelectInfo info;
    info.condition = condition | (negated ? X86_SELECT_NEGATED : 0u);
    info.true_value = true_value;
    info.false_value = false_value;
    info.declaration = true_declaration;
    x86_select_by_semantic[select_row] = info;
    if (comparison_condition || negated) x86_live_by_semantic[branch.a] = 0u;
    x86_live_by_semantic[branch_row] = 0u;
    if (else_arm) x86_live_by_semantic[branch.b] = 0u;
    if (else_arm && !returns) x86_live_by_semantic[false_store] = 0u;
    x86_live_by_semantic[true_store] = 0u;
    x86_live_by_semantic[select_row] = X86_SEMANTIC_SELECT;
    end_position = select_position;

    if (!comparison_condition)
    {
        retain_value(condition, end_position, total, function_id);
        retain_value(true_value, end_position, total, function_id);
        retain_value(false_value, end_position, total, function_id);
        return;
    }
    OptIrNodeOperands comparison = opt_ir_operands[condition];
    uint immediate;
    bool left_immediate = direct_integer_constant(
        comparison.a, total, immediate) &&
        x86_integer_immediate_operation(SEMANTIC_LIR_OP_COMPARE,
            opt_ir_core[condition].type_id, immediate);
    bool right_immediate = direct_integer_constant(
        comparison.b, total, immediate) &&
        x86_integer_immediate_operation(SEMANTIC_LIR_OP_COMPARE,
            opt_ir_core[condition].type_id, immediate);
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
